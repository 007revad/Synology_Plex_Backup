#!/usr/bin/env bash
# shellcheck disable=SC2317,SC2181
#--------------------------------------------------------------------------
# Backup Synology NAS Plex Database to tgz file in Backup folder.
# v1.6.0  15-Dec-2022  007revad
#
# Working in DSM 7 and DSM 6 - Tested in DSM 7.1.1 and DSM 6.2.4
#
#                    ***** MUST BE RUN AS ROOT *****
#
# Run as ROOT from Synology task scheduler, WinSCP, Putty etc:
# /volume1/scripts/backup_synology_plex_to_tar.sh
# Change /volume1/scripts/ to path where this script is located
#
# To do a test run on just Plex's Logs folder run:
# /volume1/scripts/backup_synology_plex_to_tar.sh test
#
# Gist on Github: https://gist.github.com/007revad
# Script verified at https://www.shellcheck.net/
#--------------------------------------------------------------------------

# NEW Tested and working in DSM 7 (and DSM 6).
# NEW Added option to disable logging every file that is backed up.
# NEW Made system log and DSM notifications optional settings.
# CHANGED Fixed Plex status check for DSM 7.
# CHANGED Cleaned up output from Plex start/stop commands for DSM 7.
# CHANGED 'test' and 'error' arguments to backup Plex's Logs folder instead of Profiles folder.


# TODO Get synodsmnotify working in DSM 7

# TODO Maybe change errors in shell and log to only appear if there are tar errors in the error log.
#      All other errors are already logged in the main log file (need to check that they all are).

# TODO Maybe add email notification. Not really needed as task scheduler can send emails.

# TODO Create Restore script ???

#--------------------------------------------------------------------------

# Set location to save tgz file to
Backup_Directory="/volume1/Backups/Plex_Backup"

# This script gets the brand, model and hostname from the NAS for logging and backup file name.
# Set Name= to "brand", "model", "hostname" or some nickname.
# If Name= is blank the Synology's hostname will be used.
Name="brand"

# Log all files backed up.
# Set LogAll= to "yes" or "no". Blank is the same as no.
LogAll="no"

# Add success or failed entry to DSM system log.
# Set SysLog= to "yes" or "no". Blank is the same as no.
SysLog="yes"

# Add success or failed entry to DSM notifications.
# Set Notify= to "yes" or "no". Blank is the same as no.
Notify="yes"


#--------------------------------------------------------------------------
#               Nothing below here should need changing
#--------------------------------------------------------------------------

# Set date and time variables

# Timer variable to log time taken to backup PMS
start="${SECONDS}"

# Get Start Time and Date
Started=$( date )

# Get Today's date for filename
Now=$( date '+%Y%m%d')
# Get Today's date and time for filename in case filename exists
NowLong=$( date '+%Y%m%d-%H%M')


#--------------------------------------------------------------------------
# Set NAS name (used in backup and log filenames)

#case "$Name" in
case "${Name,,}" in
    brand)
        # Get NAS Brand
        if [[ -f /etc/synoinfo.conf ]]; then
             Nas="$(get_key_value /etc/synoinfo.conf company_title)"
        fi
        ;;
    model)
        # Get Synology model
        if [[ -f /proc/sys/kernel/syno_hw_version ]]; then
            Nas=$(cat /proc/sys/kernel/syno_hw_version)
        fi
        ;;
    hostname|"")
        # Get Hostname
        Nas=$( hostname )
        ;;
    *)
        # Set NAS to nickname
        Nas="$Name"
        ;;
esac


#--------------------------------------------------------------------------
# Set temporary log filenames (we get the Plex version later)

# Set backup filename
Backup_Name="${Nas}"_"${Now}"_Plex_"${Version}"_Backup

# If file exists already include time in name
BackupPN="$Backup_Directory/$Backup_Name"
if [[ -f $BackupPN.tgz ]] || [[ -f $BackupPN.log ]] || [[ -f "$BackupPN"_ERROR.log ]]; then
    Backup_Name="${Nas}"_"${NowLong}"_Plex_"${Version}"_Backup
fi

# Set log filename
Log_File="${Backup_Directory}"/"${Backup_Name}".log

# Set error log filename
Err_Log_File="${Backup_Directory}"/"${Backup_Name}"_ERROR.log


#--------------------------------------------------------------------------
# Create temp error log

# Create temp directory for temp error log
Tmp_Dir=$(mktemp -d -t plex_to_tar-XXXXXX)

# Create temp error log
Tmp_Err_Log_File=$(mktemp "${Tmp_Dir}"/errorlog-XXXXXX)


#--------------------------------------------------------------------------
# Create trap and clean up function

# Tmp logs clean up function
cleanup() {
    arg1=$?
    # Move tmp_error_log to error log if tmp_error_log is not empty
    if [[ -s $Tmp_Err_Log_File ]] && [[ -d $Backup_Directory ]]; then
        mv "${Tmp_Err_Log_File}" "${Err_Log_File}"
        if [[ $? -gt "0" ]]; then
            echo "WARNING Failed moving ${Tmp_Err_Log_File} to ${Err_Log_File}" |& tee -a "${Err_Log_File}"
        fi
    fi
    # Delete our tmp directory
    if [[ -d $Tmp_Dir ]]; then
        rm -rf "${Tmp_Dir}"
        if [[ $? -gt "0" ]]; then
            echo "WARNING Failed deleting ${Tmp_Dir}" |& tee -a "${Err_Log_File}"
        fi
    fi

    # Log and notify of success or errors
    if [[ -f $Err_Log_File ]]; then
        # Log and notify backup had errors
        if [[ ! -f $Log_File ]]; then
            # Add script name to top of log file
            basename -- "$0" |& tee -a "${Log_File}"
        fi
        echo -e "\nWARNING Plex backup had errors! See error log:" |& tee -a "${Log_File}"
        #echo "${Err_Log_File}" |& tee -a "${Log_File}"
        # Remove /volume#/ from error log path
        Err_Log_Short=$(printf %s "${Err_Log_File}"| sed "s/\/volume.*\///g")
        echo -e "${Err_Log_Short}\n" |& tee -a "${Log_File}"

        # Add entry to Synology system log
        if [[ $Brand == "Synology" ]] && [[ ${SysLog,,} == "yes" ]]; then
            if [[ $Version ]]; then
                synologset1 sys warn 0x11100000 "Plex ${Version} backup had errors. See ERROR.log"
            else
                synologset1 sys warn 0x11100000 "Plex backup had errors. See ERROR.log"
            fi
        fi

        if [[ $Dsm == 6 ]] && [[ ${Notify,,} == "yes" ]]; then
            # Add DSM 6 notification
            synodsmnotify @administrators "Plex Backup Errors" "See: ${Backup_Name}_ERROR.log"
###            synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "Plex Media Server\n\nSyno.Plex Update task failed. DSM not sufficient version."}'

        elif [[ $Dsm == 7 ]] && [[ ${Notify,,} == "yes" ]]; then
            # Add DSM 7 notification
            #synodsmnotify @administrators "Plex Backup Errors" "See: ${Backup_Name}_ERROR.log"
            # returns: title: 'Plex Backup Errors' is neither mail string key nor i18n format.
            synodsmnotify @administrators '{"Plex Backup Errors" "See: ${Backup_Name}_ERROR.log"}'
            # returns: title: '{"Plex Backup Errors" "See: ${Backup_Name}_ERROR.log"}' is not mail string key
            # Send email and/or SMS
###            synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "Plex Media Server\n\nSyno.Plex Update task failed. DSM not sufficient version."}'
        fi
    else
        # Log and notify of backup success
        echo -e "\nPlex backup completed successfully" |& tee -a "${Log_File}"

        # Add entry to Synology system log
        if [[ $Brand == "Synology" ]] && [[ ${SysLog,,} == "yes" ]]; then
            if [[ $Version ]]; then
                synologset1 sys info 0x11100000 "Plex ${Version} backup completed successfully"
            else
                synologset1 sys info 0x11100000 "Plex backup completed successfully"
            fi
        fi

        if [[ $Dsm == 6 ]] && [[ ${Notify,,} == "yes" ]]; then
            # Add DSM 6 notification
            synodsmnotify @administrators "Plex Backup Finished" "Plex backup completed successfully."
            # Send email and/or SMS - NOT WORKING YET
###            synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "Plex Media Server\n\nSyno.Plex Update task failed. DSM not sufficient version."}'

        elif [[ $Dsm == 7 ]] && [[ ${Notify,,} == "yes" ]]; then
            # Add DSM 7 notification - NOT WORKING YET
            #synodsmnotify @administrators "Plex Backup Finished" "Plex backup completed successfully."
            # returns: title: 'Plex Backup Finished' is neither mail string key nor i18n format.
            synodsmnotify @administrators '{"Plex Backup Finished" "Plex backup completed successfully."}'
            # returns: title: '{"Plex Backup Finished" "Plex backup completed successfully."}' is not mail string key
            # Send email and/or SMS - NOT WORKING YET
###            synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "Plex Media Server\n\nSyno.Plex Update task failed. DSM not sufficient version."}'
        fi
    fi
    exit "${arg1}"
}

trap cleanup EXIT


#--------------------------------------------------------------------------
# Check that script is running as root

if [[ $( whoami ) != "root" ]]; then
    if [[ -d $Backup_Directory ]]; then
        echo ERROR: This script must be run as root! |& tee -a "${Tmp_Err_Log_File}"
        echo ERROR: "$( whoami )" is not root. Aborting. |& tee -a "${Tmp_Err_Log_File}"
    else
        # Can't log error because $Backup_Directory does not exist
        echo
        echo ERROR: This script must be run as root!
        echo ERROR: "$( whoami )" is not root. Aborting.
        echo
    fi
    # Add entry to Synology system log
    if [[ $Brand == "Synology" ]] && [[ ${SysLog,,} == "yes" ]]; then
        synologset1 sys warn 0x11100000 "Plex backup failed. Needs to run as root."
    fi
    # Abort script because it isn't being run by root
    exit 255
fi


#--------------------------------------------------------------------------
# Check script is running on a Synology NAS

if [[ -f /etc/synoinfo.conf ]]; then Brand="$(get_key_value /etc/synoinfo.conf company_title)"; fi
# Returns: Synology

if [[ $Brand != "Synology" ]]; then
    if [[ -d $Backup_Directory ]]; then
        echo Checking script is running on a Synology NAS |& tee -a "${Tmp_Err_Log_File}"
        echo ERROR: "$( hostname )" is not a Synology! Aborting. |& tee -a "${Tmp_Err_Log_File}"
    else
        # Can't log error because $Backup_Directory does not exist
        echo
        echo Checking script is running on a Synology NAS
        echo ERROR: "$( hostname )" is not a Synology! Aborting.
        echo
    fi
    # Can't Add entry to Synology system log because script not running on an Synology
    # Abort script because it's being run on the wrong NAS brand
    exit 255
fi


#--------------------------------------------------------------------------
# Find Plex Media Server location

# Get DSM major version
if [[ -f /etc/synoinfo.conf ]]; then Dsm="$(get_key_value /etc.defaults/VERSION majorversion)"; fi

# Get the Plex Media Server data location
if [[ $Dsm == 6 ]]; then
    Plex_Data_Path=$(head -n 1 "/var/packages/Plex Media Server/target/plex_library_path")
    # Returns "/volume1/Plex/Library/Application Support"
    Plex_PKG="Plex Media Server" # for synopkg version|stop|status|start $Plex_PKG
elif [[ $Dsm == 7 ]]; then
    Plex_Data_Path=$(readlink /var/packages/PlexMediaServer/shares/PlexMediaServer)
    # Returns "/volume1/PlexMediaServer"
    Plex_Data_Path="${Plex_Data_Path}/AppData"
    Plex_PKG="PlexMediaServer" # for synopkg version|stop|status|start $Plex_PKG
else
    echo "DSM $Dsm is not supported! Aborting." |& tee -a "${Tmp_Err_Log_File}"
    if [[ ${SysLog,,} == "yes" ]]; then
        # Add entry to Synology system log
        synologset1 sys warn 0x11100000 "Plex backup failed. DSM $Dsm is not supported!"
    fi
    # Abort script because it's being run on the wrong NAS brand
    exit 255
fi

# Check Plex Media Server data path exists
if [[ ! -d $Plex_Data_Path ]]; then
    echo Plex Media Server data path invalid! Aborting. |& tee -a "${Tmp_Err_Log_File}"
    echo "${Plex_Data_Path}" |& tee -a "${Tmp_Err_Log_File}"
    if [[ $Brand == "Synology" ]] && [[ ${SysLog,,} == "yes" ]]; then
        # Add entry to Synology system log
        synologset1 sys warn 0x11100000 "Plex backup failed. Plex data path invalid."
    fi
    # Abort script because Plex data path invalid
    exit 255
fi


#--------------------------------------------------------------------------
# Get Plex Media Server version

Version=$(synopkg version "$Plex_PKG")
# Returns 1.29.2.6364-6000 or 1.29.2.6364-7000
# Plex version without DSM number
Version=$(printf %s "${Version}"| cut -d '-' -f1)
# Returns 1.29.2.6364


#--------------------------------------------------------------------------
# Re-assign log names to include Plex version

# Backup filename
Backup_Name="${Nas}"_"${Now}"_Plex_"${Version}"_Backup

# If file exists already include time in name
BackupPN="$Backup_Directory/$Backup_Name"
if [[ -f $BackupPN.tgz ]] || [[ -f $BackupPN.log ]] || [[ -f "$BackupPN"_ERROR.log ]]; then
    Backup_Name="${Nas}"_"${NowLong}"_Plex_"${Version}"_Backup
fi

# Log file filename
Log_File="${Backup_Directory}"/"${Backup_Name}".log

# Error log filename
Err_Log_File="${Backup_Directory}"/"${Backup_Name}"_ERROR.log


#--------------------------------------------------------------------------
# Start logging

# Log NAS brand, model, DSM version and hostname
Model=$(cat /proc/sys/kernel/syno_hw_version)
DSMversion="$(get_key_value /etc.defaults/VERSION productversion)"
BuildNum="$(get_key_value /etc.defaults/VERSION buildnumber)"
echo "${Brand}" "${Model}" DSM "${DSMversion}"-"${BuildNum}" |& tee -a "${Log_File}"
echo "Hostname: $( hostname )" |& tee -a "${Log_File}"

# Log Plex version
echo Plex version: "${Version}" |& tee -a "${Log_File}"


#--------------------------------------------------------------------------
# Check if backup directory exists

if [[ ! -d $Backup_Directory ]]; then
    echo "ERROR: Backup directory not found! Aborting backup." |& tee -a "${Log_File}" "${Tmp_Err_Log_File}"
    if [[ $Brand == "Synology" ]] && [[ ${SysLog,,} == "yes" ]]; then
        # Add entry to Synology system log
        synologset1 sys warn 0x11100000 "Plex backup failed. Backup directory not found."
    fi
    # Abort script because backup directory not found
    exit 255
fi


#--------------------------------------------------------------------------
# Stop Plex Media Server

echo "Stopping Plex..." |& tee -a "${Log_File}"
# synopkg MUST be run as root
synopkg stop "$Plex_PKG" >/dev/null 2> >(tee -a "${Log_File}" "${Tmp_Err_Log_File}" >&2)
wait
# Give sockets a moment to close
sleep 5


#--------------------------------------------------------------------------
# Check if Plex has stopped

echo Checking status of Plex processes... |& tee -a "${Log_File}"
Response=$(synopkg status "$Plex_PKG")
if [[ ! $(grep "package is stopped" <<< "$Response") ]]; then
    echo "ERROR: Plex is still running! Aborting backup." |& tee -a "${Log_File}" "${Tmp_Err_Log_File}"
    # Start Plex to make sure it's not left partially running
    synopkg start "$Plex_PKG" >/dev/null 2> >(tee -a "${Log_File}" "${Tmp_Err_Log_File}" >&2)
    if [[ $Brand == "Synology" ]] && [[ ${SysLog,,} == "yes" ]]; then
        # Add entry to Synology system log
        synologset1 sys warn 0x11100000 "Plex backup failed. Plex didn't shut down."
    fi
    # Abort script because Plex didn't shut down fully
    exit 255
fi


#--------------------------------------------------------------------------
# Backup Plex Media Server

echo "=======================================" |& tee -a "${Log_File}"
echo "Backing up Plex Media Server data files:" |& tee -a "${Log_File}"

Exclude_File="$( dirname -- "$0"; )/plex_backup_exclude.txt"

# Check for test or error arguments
if [[ -n $1 ]] && [[ ${1,,} == "error" ]]; then
    # Trigger an error to test error logging
    Test="Plex Media Server/Logs/ERROR/"
    echo "Running small error test backup of Logs folder" |& tee -a "${Log_File}"
elif [[ -n $1 ]] && [[ ${1,,} == "test" ]]; then
    # Test on small Logs folder only
    Test="Plex Media Server/Logs/"
    echo "Running small test backup of Logs folder" |& tee -a "${Log_File}"
fi

# Check if exclude file exists
# Must come after "Check for test or error arguments"
if [[ -f $Exclude_File ]]; then
    # Unset arguments
    while [[ $1 ]]
    do
        shift
    done
    # Set -X excludefile arguments for tar
    set -- "$@" "-X"
    set -- "$@" "${Exclude_File}"
else
    echo "INFO: No exclude file found." |& tee -a "${Log_File}"
fi

# Use short variable names so tar command is not too long
BD="${Backup_Directory}"
BN="${Backup_Name}"
PDP="${Plex_Data_Path}"
LF="${Log_File}"
TELF="${Tmp_Err_Log_File}"
PMS="Plex Media Server"

# Run tar backup command
if [[ -n $Test ]]; then
    # Running backup test or error test
    if [[ ${LogAll,,} == "yes" ]]; then
        tar -cvpzf "${BD}"/"${BN}".tgz -C "${PDP}" "${Test}" > >(tee -a "${LF}") 2> >(tee -a "${LF}" "${TELF}" >&2)
    else
        # Don't log all backed up files.
        echo "Only logging errors" |& tee -a "${Log_File}"
        tar -cvpzf "${BD}"/"${BN}".tgz -C "${PDP}" "${Test}" 2> >(tee -a "${LF}" "${TELF}" >&2)
    fi
else
    # Backup to tgz with PMS version and date in file name, send all output to shell and log, plus errors to error.log
    # Using -C to change directory to Plex's DSM 7 Appdata, or DSM 6 Library, folder to not backup absolute path
    # and avoid "tar: Removing leading /" error
    if [[ ${LogAll,,} == "yes" ]]; then
        tar -cvpzf "${BD}"/"${BN}".tgz "$@" -C "${PDP}" "$PMS/" > >(tee -a "${LF}") 2> >(tee -a "${LF}" "${TELF}" >&2)
    else
        # Don't log all backed up files.
        echo "Only logging errors" |& tee -a "${Log_File}"
        tar -cvpzf "${BD}"/"${BN}".tgz "$@" -C "${PDP}" "$PMS/" 2> >(tee -a "${LF}" "${TELF}" >&2)
    fi
fi


#--------------------------------------------------------------------------
# Start Plex Media Server

echo "=======================================" |& tee -a "${Log_File}"
echo Starting Plex... |& tee -a "${Log_File}"

# synopkg must be run as root
#synopkg start "$Plex_PKG" >/dev/null
synopkg start "$Plex_PKG" >/dev/null 2> >(tee -a "${Log_File}" "${Tmp_Err_Log_File}" >&2)
wait


#--------------------------------------------------------------------------
# Append the time taken to stdout and log file

# End Time and Date:
Finished=$( date )

# bash timer variable to log time taken to backup PMS:
end="${SECONDS}"

# Elapsed time in seconds:
Runtime=$(( end - start ))

# Append start and end date/time and runtime
echo -e "\nBackup Started: " "${Started}" |& tee -a "${Log_File}"
echo "Backup Finished:" "${Finished}" |& tee -a "${Log_File}"
# Append days, hours, minutes and seconds from $Runtime
printf "Backup Duration: " |& tee -a "${Log_File}"
printf '%dd:%02dh:%02dm:%02ds\n' \
$((Runtime/86400)) $((Runtime%86400/3600)) $((Runtime%3600/60)) \ $((Runtime%60)) |& tee -a "${Log_File}"


#--------------------------------------------------------------------------
# Trigger cleanup function
exit 0
