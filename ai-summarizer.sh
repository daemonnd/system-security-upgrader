#!/bin/bash

# strict mode
set -Eeuo pipefail

# trap errors
trap 'echo "Error on line $LINENO: command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

function init {
    # check if the trigger file exists with read permission
    if [[ ! -r /var/lib/system-security-upgrader/pending-ai-summary ]]; then
        echo "ERROR: There is no file at '/var/lib/system-security-upgrader/pending-ai-summary', therefore this script can't pe executed properley."
        exit 1
    fi
    # get the user & logdir
    declare -a tmp_arr
    mapfile -t tmp_arr < /var/lib/system-security-upgrader/pending-ai-summary
    user="${tmp_arr[0]}"
    logdir="${tmp_arr[1]}"
    logpattern="${tmp_arr[2]}"
    #echo "user: ${user@Q}"
    #echo "logdir: ${logdir@Q}"

    # DEBUG
    echo "USER: $user"

    # check if the prompts are there # TODO

    summaryfile="/var/lib/system-security-upgrader/summaries/"${user}"/"${logpattern}"_ai-summary.md"
    
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
    # tool: $1
    local tool="$1"
    echo "Running local ai against the logs of ${tool}..."

    echo >> "$summaryfile"
    echo "# $tool" >> "$summaryfile"
    echo >> "$summaryfile"

    filter "${logdir}${tool}.log"  | fabric -sp "system_security_upgrader_$1" >> "$summaryfile"
    echo "Running local ai against the logs of ${tool}... Done"
}
function main {
    init "$@"
    run_ai "lynis" &
    lynis_ai_pid="$!"
    run_ai "rkhunter" &
    rkhunter_ai_pid="$!"

    wait "$lynis_ai_pid" "$rkhunter_ai_pid"
    
    echo "The summary have been saved at"
    echo "$summaryfile"
    rm "/var/lib/system-security-upgrader/pending-ai-summary"
    echo "The trigger file for the ai summary has been removed successfully."
    # DEBUG
    echo "USER: $user"
    ls "/var/lib/system-security-upgrader/"
    ls "/var/lib/system-security-upgrader/summaries/"
    ls "/var/lib/system-security-upgrader/summaries/user/"

}

# call main with all args, as given
main "$@"

