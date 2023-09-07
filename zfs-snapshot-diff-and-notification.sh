#!/bin/bash

#### SET PATHS ####

# Get filePath to where this script is located.
thisScriptFile=$(readlink -f "${0}")
thisScriptPath=$(dirname "${thisScriptFile}")
parentDirPath=$(dirname "${thisScriptPath}")

# Set other paths.
notifyScript="${parentDirPath}/notification/discord-webhook.sh"
diffReportFile="${thisScriptPath}/snapshot-diff-report.txt"
ignoreDatasetFile="${thisScriptPath}/.ignore-datasets.txt"
ignorePathFile="${thisScriptPath}/.ignore-paths.txt"

# Create files if they don't exist.
touch -a "${ignoreDatasetFile}"
touch -a "${ignorePathFile}"

#### PARSE ARGUMENTS ####

# Usage function.
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -p, --parent <dataset>    Set the parent dataset. If none all will be checked."
    echo "  -n, --notify              Set to send Discord notification with summary."
    echo "  -h, --help                Show this help message and exit."
    echo ""
    echo "https://openzfs.github.io/openzfs-docs/man/master/8/zfs-diff.8.html"
}

# Parsed from command line arguments.
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--parent)
            parentDataset="$2"
            shift 2
            ;;
        -n|--notify)
            discordNotify=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Invalid option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

# Validate dataset argument if provided.
if [ -n "${parentDataset}" ]; then

  if ! zfs list -H "${parentDataset}" &>/dev/null; then
    echo "Error: Dataset '${parentDataset}' does not exist."
    exit 1
  fi

fi

#### INITIALIZE VALUES ####

modifiedEntry=()
modifiedFields=
modifiedFilesCounter=0
modifiedFoldersCounter=0

deletedEntry=()
deletedFields=
deletedFilesCounter=0
deletedFoldersCounter=0

addedEntry=()
addedFields=
addedFilesCounter=0
addedFoldersCounter=0

renamedEntry=()
renamedFields=
renamedFilesCounter=0
renamedFoldersCounter=0

#### COLLECT SNAPSHOT DATA ####

# Get a list of snapshots under parent or all if no parent dataset provided.
if [[ -z "${parentDataset}" ]]; then

    snapshots=$(zfs list -t snapshot -H -o name,creation)

    poolCount=$(zpool list -H | wc -l)

else

    snapshots=$(zfs list -t snapshot -H -o name,creation "${parentDataset}" -r)

    poolCount=1

fi

# Filter list down to a unique list of datasets that excluds datasets with names from ignore-file.
datasetsWithSnapshotsList=$(echo "${snapshots}" | grep -vFf "${ignoreDatasetFile}" | awk -F"@" '{print $1}' | uniq)

# Convert list to an array.
readarray -t datasetsWithSnapshots <<< "$datasetsWithSnapshotsList"

# Loop throught datsets with snapshots.
for dataset in "${datasetsWithSnapshots[@]}"; do

    # Count number of datasets checked.
    ((datasetCount++))

    # Clear change data for new dataset
    modifyChange=
    deletedChange=
    addedChange=
    renamedChange=

    # Get the latest snapshot for the current dataset
    snapshot=$(echo "${snapshots}" | grep "${dataset}@" | tail -1)
    snapshotName=$(echo "${snapshot}" | awk '{print $1}') 
    snapshotDate=$(echo "${snapshot}" | cut -d' ' -f2-)

    # Get all changes to dataset files since snapshot.
    snapshotDiff=$(sudo zfs diff -hHF "${snapshotName}" | sort | grep -vFf "${ignorePathFile}")

    # Collect and sort data on each change.
    while IFS=$'\t' read -r change typeSymbol file; do

        # Remove trailing "/" (awk is needed for rename change)
        file=$(echo "${file%/}" | awk '{print $1}')

        # Split file/folder name and path.
        filePath=$(echo -e "${file%/*}")  
        fileName=$(echo -e "${file##*/}")

        # Check file type.
        if [[ $typeSymbol == "/" ]]; then

            type="Directory"
            fileFormatted=":file_folder:  ${fileName}"

        elif [[ $typeSymbol == "F" ]]; then

            type="File"
            fileFormatted=":page_facing_up:  ${fileName}"

        else            

            type="Other"
            fileFormatted=":receipt:  ${fileName}"

        fi
        
        # Combine data for report entry.
        reportEntry="${dataset}|${filePath}|${type}|${fileName}|${snapshotDate}"

        # Generate change data for each change type.
        case "$change" in
        -)
            deletedEntry+=("Deleted|${reportEntry}")
            deletedChange=""$deletedChange"- "$fileFormatted"\n"
            [ $typeSymbol == "F" ] && ((deletedFilesCounter++))
            [ $typeSymbol == "/" ] && ((deletedFoldersCounter++)) ;;
        +)
            addedEntry+=("Added|${reportEntry}")
            addedChange=""$addedChange"- "$fileFormatted"\n"
            [ $typeSymbol == "F" ] && ((addedFilesCounter++))
            [ $typeSymbol == "/" ] && ((addedFoldersCounter++)) ;;            
        M)
            modifiedEntry+=("Modified|${reportEntry}")
            modifyChange=""$modifyChange"- "$fileFormatted"\n"
            [ $typeSymbol == "F" ] && ((modifiedFilesCounter++))
            [ $typeSymbol == "/" ] && ((modifiedFoldersCounter++)) ;;            
        R)
            renamedEntry+=("Renamed|${reportEntry}")
            renamedChange=""$renamedChange"- "$fileFormatted"\n"
            [ $typeSymbol == "F" ] && ((renamedFilesCounter++))
            [ $typeSymbol == "/" ] && ((renamedFoldersCounter++)) ;;
        esac

    done <<< "$snapshotDiff"

    # Build JSON data if notification set.
    if [[ "${discordNotify}" = true ]]; then

        # Generate change field JSON.
        generateChangeField() {

            local name="$1"
            local value="$2"

            echo    "{
                        \"name\": \"$name\",
                        \"value\": \"$value\"
                    },"

        }

        # Format date for Discord notification.
        snapshotDateFormatted=$(echo "__*"${snapshotDate#"${snapshotDate%%[![:space:]]*}"}"*__")

        # Build and combine change JSON fields.
        if [[ -n "${modifyChange}" ]]; then

            changeField=$(generateChangeField "${dataset}" "${snapshotDateFormatted}\n${modifyChange//$'\n\n'/}")
            modifiedFields+="$changeField"

        fi
        if [[ -n "${deletedChange}" ]]; then

            changeField=$(generateChangeField "${dataset}" "${snapshotDateFormatted}\n${deletedChange//$'\n\n'/}")
            deletedFields+=" $changeField"
            
        fi
        if [[ -n "${addedChange}" ]]; then

            changeField=$(generateChangeField "${dataset}" "${snapshotDateFormatted}\n${addedChange//$'\n\n'/}")
            addedFields+=" $changeField"
            
        fi
        if [[ -n "${renamedChange}" ]]; then

            changeField=$(generateChangeField "${dataset}" "${snapshotDateFormatted}\n${renamedChange//$'\n\n'/}")
            renamedFields+=" $changeField"

        fi

    fi      

done

#### GENERATE REPORT ####

header="Change|Dataset|Path|Type|File|Since"
spacer=(""$' '"|"$' '"|"$' '"|"$' '"|"$' '"|"$' '"")
diffReportTable=("${header[@]}" "${spacer[@]}" "${deletedEntry[@]}" "${spacer[@]}" "${modifiedEntry[@]}" "${spacerEntry[@]}" "${renamedEntry[@]}"  "${spacer[@]}" "${addedEntry[@]}" )

{
  printf '%s\n' "${diffReportTable[@]}" | column -t -s "|"
  echo -e "\nExcluded datasets containing the following:"
  cat "${ignoreDatasetFile}"
  echo -e "\n\nExcluded paths containing the following:"
  cat "${ignorePathFile}"
} > "${diffReportFile}"

#### DISCORD DATA / NOTIFICATION ####

# Build JSON data and send Discord notification if set.
if [[ "${discordNotify}" = true ]]; then

    # Build change report JSON blocks.
    if [[ -n "${modifiedFields}" ]]; then

        modifiedJsonBlock='{
                            "title": ":hammer:  Modified",
                            "description": "A total of **'${modifiedFilesCounter}'** files and **'${modifiedFoldersCounter}'** directories has been **modified** since the last snapshot of their respective datasets (excluding ignored paths and datasets).",
                            "color": "16027660",
                            "fields": [ '${modifiedFields%?}' ]
                        },'
    fi
    if [[ -n "${deletedFields}" ]]; then

        deletedJsonBlock='{
                            "title": ":x:  Deleted",
                            "description": "A total of **'${deletedFilesCounter}'** files and **'${deletedFoldersCounter}'** directories has been **deleted** since the last snapshot of their respective datasets (excluding ignored paths and datasets).",
                            "color": "14495300",
                            "fields": [ '${deletedFields%?}' ]
                        },'

    fi
    if [[ -n "${renamedFields}" ]]; then

        renamedJsonBlock='{
                            "title": ":paintbrush:  Renamed",
                            "description": "A total of **'${renamedFilesCounter}'** files and **'${renamedFoldersCounter}'** directories has been **renamed** since the last snapshot of their respective datasets (excluding ignored paths and datasets).",
                            "color": "3901635",
                            "fields": [ '${renamedFields%?}' ]
                        },'

    fi
    if [[ -n "${addedFields}" ]]; then

        addedJsonBlock='{
                            "title": ":jigsaw: Added",
                            "description": "A total of **'${addedFilesCounter}'** files and **'${addedFoldersCounter}'** directories has been **added** since the last snapshot of their respective datasets (excluding ignored paths and datasets).",
                            "color": "7909721",
                            "fields": [ '${addedFields%?}' ]
                        },'

    fi

    # Combine change report JSON blocks.
    embeds=''${deletedJsonBlock}'
            '${modifiedJsonBlock}'
            '${renamedJsonBlock}'
            '${addedJsonBlock}''

    # Create content /description section
    content="Report summary from ZFS dataset snapshot diff checker script on **$HOSTNAME** machine. The script checked **${datasetCount}** dataset(s) on **${poolCount}** pool(s) for changes since last snaphot."                                     

    # Pass data to Discord webhooks script for notification.
    ${notifyScript} -c "${content}" -e "${embeds}" -f "${diffReportFile}"

fi