# ZFS Dataset Snapshot Content Diff Checker

This Bash script is designed to check for differences between the current content of ZFS datasets and their latest snapshots and generate a report detailing any changes. It can also send a summary of the changes to a Discord channel if the `-n` or `--notify` option is specified.

## Table of Contents

- [Background](#background)
- [Overview](#overview)
- [Usage](#usage)
- [Requirements](#requirements)
- [Script Details](#script-details)
  - [Set Paths](#set-paths)
  - [Parse Arguments](#parse-arguments)
  - [Initialize Values](#initialize-values)
  - [Collect Snapshot Content Data](#collect-snapshot-content-data)
  - [Generate Report](#generate-report)
  - [Discord Data / Notification](#discord-data--notification)
- [Discord Webhook Script](#discord-webhook-script)
- [Permissions for Running `zfs diff`](#permissions-for-running-zfs-diff)
- [Excluded Datasets and Paths](#excluded-datasets-and-paths)


## Background

The script was primarily created to address the need for monitoring and reviewing changes to the content of my home servers. Its main purpose is to help identify unintended deletions or any unwanted modifications either by me or caused by various media and file services running on the servers. While not currently configured, the intention is to automate the script to run before scheduled backups of snapshots, allowing for review and immediate action if necessary. This to help prevent undesired changes from going unnoticed until backups are eventually purged over time.

## Overview

This script helps ZFS administrators keep track of changes within their ZFS datasets by comparing the current content with the latest snapshots. It identifies modifications, deletions, additions, and renames of files and directories within the specified datasets.

**Compatibility Note:** This script has been tested on **Ubuntu Server 22.04** and should work on other Linux operating systems running OpenZFS.

## Usage

To use this script, you can follow the instructions below:

```bash
Usage: `./zfs-content-diff-check.sh [OPTIONS]`

Options:
  -p, --parent <dataset>:   Set the parent dataset. If none, all datasets will be checked.
  -n, --notify:             Set to send Discord notification with a summary.
  -h, --help:               Show this help message and exit.
```

For more information on the options and usage, on the `zfs diff` command refer to the [official ZFS documentation](https://openzfs.github.io/openzfs-docs/man/master/8/zfs-diff.8.html).

## Requirements

Before using this script, make sure you have the following requirements:

- OpenZFS
- Discord Channel (if you want to receive notifications)

## Script Details

### Set Paths

The script starts by setting various file paths for configuration and reporting. It determines the location of the script itself and sets paths for notification scripts, diff report files, and files for excluding datasets and paths.

### Parse Arguments

The script parses command-line arguments to determine the parent dataset to check and whether to send notifications to Discord. It provides a usage message if invalid options are provided.

### Initialize Values

Several variables are initialized to keep track of modified, deleted, added, and renamed files and directories within the ZFS datasets.

### Collect Snapshot Content Data

The script collects information about ZFS snapshots, including the most recent snapshot for each dataset. It then uses `zfs diff` to identify changes between the current content and the latest snapshots, excluding paths and datasets specified in the exclusion files.

### Generate Report

A report is generated summarizing the changes found in the ZFS datasets. The report is formatted as a table, and excluded datasets and paths are listed at the end.

### Discord Data / Notification

If the `-n` or `--notify` option is specified, the script generates JSON blocks for different types of changes (modified, deleted, added, renamed) and sends a summary of these changes to a Discord channel using a webhook.

## Discord Webhook Script

To enable Discord notifications, you will need a separate `discord-webhook.sh` script for sending notifications. You can find and clone this script from another GitHub repository dedicated to Discord webhooks:

[GitHub Repository: discord-webhook-notification](https://github.com/norsemanGrey/discord-webhook-notification)

Make sure to configure and set up the `discord-webhook.sh` script correctly, and ensure it's available in your environment for the notifications to work.

![zfs-snapshot-diff-checker-discord-notification-example](https://github.com/norsemanGrey/zfs-snapshot-diff/assets/16608441/a576581e-95dc-4bb0-8aff-722923fc444b)

## Permissions for Running `zfs diff`

Running the `zfs diff` command requires sudo privileges. To resolve this, you need to grant `diff` permissions to the user in question on the pools intended to be monitored by issuing the following command:

```bash
sudo zfs allow -u <user> diff <pool>
```

This command grants the user the necessary permissions to execute zfs diff on the specified pool without requiring root privileges.

## Excluded Datasets and Paths

You can specify datasets and directories that should not be monitored for changes by creating two exclusion files:

1. **Excluded Datasets File (`.ignore-datasets.txt`):** List the names of datasets (one per line) that you want to exclude from monitoring. These could be datasets such as Docker containers datasets (if running Docker on ZFS), or other datasets not desirable for change tracking.

2. **Excluded Paths File (`.ignore-paths.txt`):** List the directory paths (relative to the dataset) that you want to exclude from monitoring. This is useful for excluding specific directories within datasets that you don't want to track for changes (GIT directories, databases, etc.)

If these files do not exist, the script will create them. You can manually edit these files to add or remove entries as needed.
