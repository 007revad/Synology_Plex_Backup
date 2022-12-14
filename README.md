# Synology_Plex_Backup

<a href="https://github.com/007revad/Synology_Plex_Backup/releases"><img src="https://img.shields.io/github/release/007revad/Synology_Plex_Backup.svg"></a>
<a href="https://hits.seeyoufarm.com"><img src="https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fgithub.com%2F007revad%2FSynology_Plex_Backup&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=hits&edge_flat=false"/></a>

### Description

This is a bash script to backup a Synology's Plex Media Server settings and database, and log the results.

The script works in DSM 7 and DSM 6.

#### What the script does:

-   Gets your Synology's hostname and model (for use in the backup filename and log name).
-   Checks that the script is running as root.
-   Checks it is running on a Synology.
-   Gets Plex Media Server's version (for the backup filename and log).
-   Gets the volume and share name where Plex Media Server's database is located.
-   Checks that your specified backup location exists.
-   Stops Plex Media Server, then checks Plex actually stopped.
-   Backs up Plex Media Server to a tgz file (**excluding the folders listed in plex_backup_exclude.txt**).
-   Starts Plex Media Server.
-   Optionally adds an entry to the Synology's system log stating if the backup succeded or failed.
-   Optionally sends a notification to DSM if Plex Backup completed, or had errors (**only works in DSM 6 for now**).

#### It also saves a log in the same location as the backup file, including:

-   Logging the start and end time plus how long the backup took.
-   Logging every file that was backed up (can be disabled).
-   Logging any errors to a separate error log file to make it easy for you to see if there were errors.

The Synology's hostname, date, and Plex Media Server version are included in the backup's filename in case you need to roll Plex back to an older version or you save backups from more than one Plex Server.

**Example of the backup's auto-generated filenames:** 
-   DISKSTATION_20221025_Plex_1.29.0.6244_Backup.tgz
-   DISKSTATION_20221025_Plex_1.29.0.6244_Backup.log
-   DISKSTATION_20221025_Plex_1.29.0.6244_Backup_ERROR.log (**only if there was an error**)

If you run multiple backups on the same day the time will be included in the filename.

**Example of the backup's auto-generated filenames when run more than once on the same day:** 
-   DISKSTATION_20221025_1920_Plex_1.29.0.6244_Backup.tgz
-   DISKSTATION_20221025_1920_Plex_1.29.0.6244_Backup.log

### Settings

You need to set **backupDirectory=** near the top of the script (below the header). Set it to the location where you want the backup saved to. 

**For example:**

```YAML
backupDirectory="/volume1/Backups/Plex_Backups"
```

**There are also a few optional settings:**

The script gets the brand, model and hostname from the NAS to use logs and backup name.
Set Name= to "brand", "model", "hostname" or some nickname. If Name= is blank the Synology's hostname will be used.

```YAML
Name="brand"
```

Log all files backed up. If enabled all files added to the tgz archive will be logged.
Set LogAll= to "yes" or "no". Blank is the same as no.

```YAML
LogAll="no"
```

Add Plex backup success or Plex backup failed entry to DSM system log.
Set SysLog= to "yes" or "no". Blank is the same as no.

```YAML
SysLog="yes"
```

Add success or failed entry to DSM notifications.
Set Notify= to "yes" or "no". Blank is the same as no.

```YAML
Notify="yes"
```

### Requirements

Make sure that plex_backup_exclude.txt is in the same folder as backup_synology_plex_to_tar.sh

**Note:** Due to some of the commands used **this script needs to be run as root, or be scheduled to run as root**.


### Testing the script

If you run the script with the **test** argument it will only backup Plex's Logs folder.

```YAML
"/volume1/scripts/Backup_Plex_on_Synology.sh" test
```

If you run the script with the **error** argument it will only backup Plex's Logs folder and cause an error so you can test the error logging.

```YAML
"/volume1/scripts/Backup_Plex_on_Synology.sh" error
```
