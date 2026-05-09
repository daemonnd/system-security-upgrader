#!/bin/bash

# strict mode
set -Eeuo pipefail

# Cleanup function
function cleanup {
    echo "Script interupted or failed. Cleaning up..."
    echo "Ai summary did npt complete."
    echo "Possible causes:"
    echo "  - Script was interupted"

    exit 1
}
# trap errors
trap 'echo "Error on line $LINENO: command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

# trap signals
trap 'cleanup' INT TERM

function init {
    # check if the trigger file exists with read permission
    if [[ ! -r /var/lib/system-security-upgrader/pending-ai-summary ]]; then
        echo "ERROR: There is no file at '/var/lib/system-security-upgrader/pending-ai-summary', therefore this script can't pe executed properley."
        exit 1
    fi
    # get the user & logdir
    declare -a tmp_arr
    mapfile -t tmp_arr </var/lib/system-security-upgrader/pending-ai-summary
    user="${tmp_arr[0]}"
    logdir="${tmp_arr[1]}"
    logpattern="${tmp_arr[2]}"
    #echo "user: ${user@Q}"
    #echo "logdir: ${logdir@Q}"

    # DEBUG
    echo "USER: $user"

    # check if the prompts are there # TODO

    summaryfile=/var/lib/system-security-upgrader/summaries/"${user}"/"${logpattern}"_ai-summary.md

    echo "User: $user"
    echo "Summaryfile: $summaryfile"
    echo "The initialization of this script went well."
    echo
}
function check_args {
    echo
}

function filter {
    local logfile="$1"
    if [[ ! -r "$logfile" ]]; then
        echo "Permission error: logfile ${logfile@Q} can't be read by user ${user@Q}"
        exit 1
    fi
    echo "filterning ${logfile}..."
    awk '
        /Warning:|Suggestion:/ {
        sub(/^.*Warning: /, "Warning: ")
        sub(/^.*Suggestion: /, "Suggestion: ")
        print
    }
    ' "$logfile" | awk '!seen[$0]++' # uniq the loglines
    echo "filterning ${logfile}... Done"
}
function run_ai {
    local temp_file="${summaryfile}.tmp.$$"
    # tool: $1
    local tool="$1"
    echo "Running local ai against the logs of ${tool}..."

    {
        echo
        echo "# $tool"
        echo
    } >>"$temp_file"

    filter "${logdir}${tool}.log" | "/home/${user}/.local/bin/fabric" "-sp" "system_security_upgrader_$1" >>"$temp_file"
    echo "Running local ai against the logs of ${tool}... Done"

    # write atomically to the summary file
    rm -f "$temp_file"
    if ! mv "$temp_file" "$summaryfile"; then
        echo "FATAL: Failed to write state file, this run is silent and did not updated the ai summary file" >&2
        exit 1
    fi

}
function main {
    init "$@"
    run_ai "lynis"
    run_ai "rkhunter"

    echo "The summary have been saved at"
    echo "$summaryfile"
}

# call main with all args, as given
main "$@"
