#!/bin/bash

# strict mode
set -Eeuo pipefail

# rm tmp files function
function rm_tmp_files {
    :
}

# Cleanup function
function cleanup {
    local exit_code="$?"
    echo "Script run-full-user-maintenance.sh interrupted or failed. Cleaning up..."

    # remove tmp files
    rm_tmp_files
    # exit the script, preserving the exit code
    exit "$exit_code"
}

# trap errors
trap 'echo "Error on line $LINENO in run-full-user-maintenance.sh: command \"$BASH_COMMAND\" exited with status $?" >&2' ERR
# trap signals
trap 'cleanup' INT TERM ERR

function check_args {
    :
}

function init {
    # checking if the root user is actually running the script
    if [[ "$EUID" -ne 0 || -z "$SUDO_USER" ]]; then
        echo "Permission Error: This script needs root privileges or sudo." # logging does not work at this point
        exit 1
    fi
}

function main {
    check_args "$@"
    init "$@"
    /usr/local/lib/system-security-upgrader/user-maintenance
    /usr/local/lib/system-security-upgrader/read-state "user-maintenance.state"
}

# call main with all args, as given
main "$@"
