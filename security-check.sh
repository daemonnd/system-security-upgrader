#!/bin/bash

# strict mode
set -euo pipefail

# trap errors
trap 'echo "Error on line $LINENO: command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

function check_args {
    echo 
}

function init {
    # checking if the root user is actually running the script
    if [[ "$EUID" -ne 0 ]]; then
        echo "Permission Error: This script needs root privileges or sudo." # logging does not work at this point
        exit 1
    fi
    
    # create logfile path pattern
    logpattern=$(date "+%Y-%m-%d_%H-%M-%S")

    # create logdir path
    logdir="/var/log/system-security-upgrader/${logpattern}_security-check/"

    # create neccessary dirs
    mkdir -p /var/log/system-security-upgrader/
    mkdir "/var/log/system-security-upgrader/${logpattern}_security-check"

    echo "Executing upgrade script as root..."
}
function run_cmd {
    local description="$1"
    shift
    local logfile="$1"
    shift

    echo "${description}..."
    if "$@" &>> "$logfile" 2>&1; then
        echo "${description}... Done"
    else
        local exit_code="$?"
        if [[ "$description" =~ "rkhunter" && "$exit_code" -eq 1 ]]; then
            echo "Updating rkhunter database had at least 1 Warning. Check logfile: '${logfile}'"
            return
        else
            echo "${description} failed with exit code ${exit_code}. Check logfile: '${logfile}'"
            exit "${exit_code}"
        fi
    fi
}
function run_lynis {
    run_cmd "Using lynis to audit the system" "${logdir}lynis.log" lynis audit system --quiet --no-colors --cron-job --log-file "${logdir}lynis.log"
}
function run_rkhunter {
    # update rkhunter
    local rkhunter_update_logfile="${logdir}rkhunter_update.log"
    run_cmd "Updating rkhunter database" "$rkhunter_update_logfile"  rkhunter --update --logfile "$rkhunter_update_logfile"

    # update rkhunter's file prosperties
    local rkhunter_propupd_logfile="${logdir}rkhunter_propupd.log"
    run_cmd "Updating rkhunter file prosperties" "$rkhunter_propupd_logfile" rkhunter --propupd --logfile "$rkhunter_propupd_logfile"

    # run rkhunter with warnings only
    local rkhunter_warnings_logfile="${logdir}rkhunter_warnings.log"
    run_cmd "Running rkhunter with warnings only" "$rkhunter_warnings_logfile" rkhunter --check --sk --nocolors --rwo 
    
}

function main {
    init
    echo "Executing security check script..."
    run_lynis &
    lynis_pid="$!"
    run_rkhunter
    rkhunter_pid="$!"

    wait "$lynis_pid" "$rkhunter_pid"


    echo "All the security checks have been performed. It took $SECONDS seconds."
    rm -f /var/lib/system-security-upgrader/pending-check # remove file that triggers the security check
    echo "The 'security-upgrader.service' daemon has been disabled by removing the condition path '/var/lib/system-security-upgrader/pending-check'."

    echo "All the logs have been written to ${logdir@Q}"
    exit 0
}

# call main with all args, as given
main "$@"

