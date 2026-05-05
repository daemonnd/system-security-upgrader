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

function check_args {
    :
}

function init {
    source /usr/local/lib/system-security-upgrader/state-lib "$1"
}
function output_results {
    convert_date

    echo
    if [[ "$is_invalid" -eq 1 ]]; then
        echo "State file status: INVALID"
    else
        echo "State file status: VALID"
    fi

    if [[ "$is_stale" -eq 1 ]]; then
        echo "Freshness: STALE"
    else
        echo "Freshness: FRESH"
    fi

    echo "State: $state"
    echo "Sate Reason: $state_reason"
    echo "Last Attempt: ${last_attempt_date:-N/A}" # when the last run of user-maintenance was
    echo "Last Success: ${last_success_date:-N/A}" # when the last success was
    echo "Failure Count: ${failure_count:-N/A}"    # how many times user maintenance failed in a row
    echo "Last Log Path: ${last_log_path:-N/A}"    # log path of latest user maintenance run
}

function main {
    echo "########################################"
    echo "######## ${1:-} ########"
    echo "########################################"
    echo
    check_args "$@"
    init "$@"
    get_values

    detect_freshness

    validate_existence
    if [[ "$is_invalid" -eq 1 ]]; then
        output_results
        return
    fi

    validate_type
    if [[ "$is_invalid" -eq 1 ]]; then
        output_results
        return
    fi

    check_temporal_ordering
    if [[ "$is_invalid" -eq 1 ]]; then
        output_results
        return
    fi

    check_consistency
    if [[ "$is_invalid" -eq 1 ]]; then
        output_results
        return
    fi

    convert_date
    check_health_state
    output_results
    return

}

# call main with all args, as given
main "$@"
