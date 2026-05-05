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
    now="$(date +%s)"
    is_stale=0
    state=""
    state_reason=""
    is_invalid=0
    local state_file_name="${1:-}"
    readonly STATE_FILE=/var/lib/system-security-upgrader/"$state_file_name"
    echo "DEBUG: State file: $STATE_FILE"
}

function read_state_file {
    if ! cat "$STATE_FILE"; then
        echo "ERROR: Could not read state file $STATE_FILE"
    fi
}

function get_values {
    if ! last_attempt=$(grep 'last_attempt' <"$STATE_FILE" | awk -F '=' ' { print $2 } '); then
        echo "ERROR: Could not extract last_attempt from state file"
    fi
    if ! last_success=$(grep 'last_success' <"$STATE_FILE" | awk -F '=' ' { print $2 } '); then
        echo "ERROR: Could not extract last_success from state file"
    fi
    if ! failure_count=$(grep 'failure_count' <"$STATE_FILE" | awk -F '=' ' { print $2 } '); then
        echo "ERROR: Could not extract failure_count from state file"
    fi
    if ! last_log_path=$(grep 'last_log_path' <"$STATE_FILE" | awk -F '=' ' { print $2 } '); then
        echo "ERROR: Could not extract last_log_path from state file"
    fi
}

function convert_date {
    if [[ -z "$last_attempt" ]]; then
        last_attempt_date="N/A"
    else
        last_attempt_date=$(date -d "@$last_attempt" '+%Y-%m-%d')
    fi
    if [[ -z "$last_success" ]]; then
        last_success_date="N/A"
    else
        last_success_date=$(date -d "@$last_success" '+%Y-%m-%d')
    fi
}

# function to check the existence of all required values in the state file
function validate_existence {
    if [[ -z "$last_attempt" ]]; then
        echo "ERROR: last_attempt value is missing in state file"
        state="UNKNOWN"
        state_reason="Missing last_attempt value, cannot determine state"
        is_invalid=1
        return
    fi
    if [[ -z "$last_success" ]]; then
        echo "ERROR: last_success value is missing in state file"
        state="UNKNOWN"
        state_reason="Missing last_success value, cannot determine state"
        is_invalid=1
        return
    fi
    if [[ -z "$failure_count" ]]; then
        echo "ERROR: failure_count value is missing in state file"
        state="UNKNOWN"
        state_reason="Missing failure_count value, cannot determine state"
        is_invalid=1
        return
    fi
    if [[ -z "$last_log_path" ]]; then
        echo "ERROR: last_log_path value is missing in state file"
        state="UNKNOWN"
        state_reason="Missing last_log_path value, cannot determine state"
        is_invalid=1
        return
    fi
}

function validate_type {
    if ! [[ "$last_attempt" =~ ^[0-9]+$ ]]; then
        echo "ERROR: last_attempt value is not a valid integer"
        state="INVALID"
        state_reason="Invalid type of last_attempt value, cannot determine state"
        is_invalid=1
        return
    fi
    if ! [[ "$last_success" =~ ^[0-9]+$ ]]; then
        echo "ERROR: last_success value is not a valid integer"
        state="INVALID"
        state_reason="Invalid type of last_success value, cannot determine state"
        is_invalid=1
        return
    fi
    if ! [[ "$failure_count" =~ ^[0-9]+$ ]]; then
        echo "ERROR: failure_count value is not a valid integer"
        state="INVALID"
        state_reason="Invalid type of failure_count value, cannot determine state"
        is_invalid=1
        return
    fi

    if [[ "$last_attempt" -gt "$now" ]]; then
        echo "ERROR: last_attempt value is in the future, which is unexpected"
        state="INVALID"
        state_reason="Invalid last_attempt value, cannot determine state"
        is_invalid=1
        return
    fi
    if [[ "$last_success" -gt "$now" ]]; then
        echo "ERROR: last_success value is in the future, which is unexpected"
        state="INVALID"
        state_reason="Invalid last_success value, cannot determine state"
        is_invalid=1
        return
    fi
}

# function to check the temporal ordering of last_success and last_attempt,
# as last_success should not be after last_attempt.
# This would indicate an inconsistency in the state file and make it impossible to determine the state of user maintenance
function check_temporal_ordering {
    if [[ "$last_success" -gt "$last_attempt" ]]; then
        echo "ERROR: last_success value is after last_attempt value, which is unexpected"
        state="INVALID"
        state_reason="Invalid temporal ordering of last_success and last_attempt, cannot determine state"
        is_invalid=1
        return
    fi
}

# function to check the consistency of failure_count with last_success and last_attempt,
# and determine if the state file is valid.
# If last_success and last_attempt are the same, then failure_count should be 0.
# If last_success is before last_attempt, then failure_count should be greater than 0.
# Any inconsistency would indicate an invalid state file and make it impossible to determine the state of user maintenance
function check_consistency {
    if [[ "$last_success" -eq "$last_attempt" ]]; then
        if [[ "$failure_count" -ne 0 ]]; then
            echo "ERROR: failure_count value is $failure_count, which is unexpected when last_success and last_attempt are the same"
            state="INVALID"
            state_reason="Invalid consistency of failure_count with last_success and last_attempt, cannot determine state"
            is_invalid=1
            return
        fi
    fi
    if [[ "$last_attempt" -gt "$last_success" ]]; then
        if [[ "$failure_count" -eq 0 ]]; then
            echo "ERROR: failure_count value is $failure_count, which is unexpected when last_success is before last_attempt"
            state="INVALID"
            state_reason="Invalid consistency of failure_count with last_success and last_attempt, cannot determine state"
            is_invalid=1
            return
        fi
    fi
}

function check_health_state {
    # if failure_count is greater than or equal to 3, then state is FAILED
    if [[ "$failure_count" -ge 3 ]]; then
        state="FAILED"
        state_reason="Failure count is $failure_count, which is greater than or equal to 3"
        return
    # if last_success is before last_attempt and failure_count is less than 3, then state is DEGRADED
    elif [[ "$last_success" -lt "$last_attempt" && "$failure_count" -lt 3 && "$failure_count" -gt 0 ]]; then
        state="DEGRADED"
        state_reason="Last success date $last_success_date is before last attempt date $last_attempt_date"
        return
    # if last_success is the same as last_attempt and failure_count is 0, then state is OK
    elif [[ "$last_success" == "$last_attempt" && "$failure_count" -eq 0 ]]; then
        state="OK"
        state_reason="Last success date $last_success_date is the same as last attempt date $last_attempt_date"
        return
    else
        state="UNKNOWN"
        state_reason="Could not determine state based on the values in the state file"
        is_invalid=1
        return
    fi
}

function detect_freshness {
    if [[ "$last_success" -le $(date -d '8 days ago' "+%s") ]]; then
        is_stale=1
    else
        is_stale=0
    fi
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
