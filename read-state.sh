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
    echo "Script read-state.sh interrupted or failed. Cleaning up..."

    # remove tmp files
    rm_tmp_files
    # exit the script, preserving the exit code
    exit "$exit_code"
}

# trap errors
trap 'echo "Error on line $LINENO in read-state.sh: command \"$BASH_COMMAND\" exited with status $?" >&2' ERR
# trap signals
trap 'cleanup' INT TERM ERR

# define constants
readonly STATE_FILE="/var/lib/system-security-upgrader/user-maintenance.state"

function check_args {
    :
}

function init {
    :
}

function read_state_file {
    if ! cat /var/lib/system-security-upgrader/user-maintenance.state; then
        echo "ERROR: Could not read state file /var/lib/system-security-upgrader/user-maintenance.state"
    fi
}

function get_values {
    last_attempt=$(grep 'last_attempt' <"$STATE_FILE" | awk -F '=' ' { print $2 } ')
    last_success=$(grep 'last_success' <"$STATE_FILE" | awk -F '=' ' { print $2 } ')
    failure_count=$(grep 'failure_count' <"$STATE_FILE" | awk -F '=' ' { print $2 } ')
    last_log_path=$(grep 'last_log_path' <"$STATE_FILE" | awk -F '=' ' { print $2 } ')
}

function convert_date {
    last_attempt_date=$(date -d "@$last_attempt" '+%Y-%m-%d')
    last_success_date=$(date -d "@$last_success" '+%Y-%m-%d')
}

function detect_state {
    if [[ -z "$last_log_path" ]]; then
        state="UNKNOWN"
    elif [[ "$failure_count" -ge 3 ]]; then
        state="FAILED"
    elif [[ "$last_success_date" < "$last_attempt_date" ]]; then
        state="DEGRADED"
    elif [[ "$last_success_date" == "$last_attempt_date" ]]; then
        state="OK"
    else
        state="UNKNOWN"
    fi
}

function main {
    check_args "$@"
    init "$@"
    get_values
}

# call main with all args, as given
main "$@"
