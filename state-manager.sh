#!/bin/bash

# strict mode
set -Eeuo pipefail

# ---------------------------------------------------------------------------------
# State Manager
# ---------------------------------------------------------------------------------
# function to set the state variables to their default values,
# which are used when the state file is not valid or does not exist.
function set_state_to_default {
    last_attempt=0
    last_success=0
    failure_count=0
    last_log_path=""
}

# function to read the state from the state file.
# If the state file does not exist, it sets the state to default values.
function read_state {
    if [[ ! -f "$STATE_FILE" ]]; then
        touch "$STATE_FILE"
        set_state_to_default
    fi

    last_attempt=$(grep 'last_attempt' <"$STATE_FILE" | awk -F '=' ' { print $2 } ')
    last_attempt=$(echo "${last_attempt%% *}")
    last_success=$(grep 'last_success' <"$STATE_FILE" | awk -F '=' ' { print $2 } ')
    last_success=$(echo "${last_success%% *}")
    failure_count=$(grep 'failure_count' <"$STATE_FILE" | awk -F '=' ' { print $2 } ')
    failure_count=$(echo "${failure_count%% *}")
    last_log_path=$(grep 'last_log_path' <"$STATE_FILE" | awk -F '=' ' { print $2 } ')
    last_log_path=$(echo "${last_log_path%% *}")

    local last_attempt_valid
    last_attempt_valid=$(validate_date "$last_attempt" "last_attempt")
    if [[ "$last_attempt_valid" -eq 0 ]]; then
        set_state_to_default
    fi

    local last_success_valid
    last_success_valid=$(validate_date "$last_success" "last_success")
    if [[ "$last_success_valid" -eq 0 ]]; then
        set_state_to_default
    fi

    if [[ "$failure_count" =~ ^[0-9]+$ ]]; then
        :
    else
        set_state_to_default
    fi

    if [[ ! -d "$last_log_path" ]]; then
        last_log_path="Unknown"
    fi

    echo "last_attempt=${last_attempt:-0}"
    echo "last_success=${last_success:-0}"
    echo "failure_count=${failure_count:-0}"
    echo "last_log_path=${last_log_path:-}"
}

# function to validate that a given string is a valid date in the YYYY-mm-dd format.
# It returns true if the date is valid, and false otherwise.
# It also takes a description as a second argument, which is used for error messages.
# valid: 1 invalid: 0
function validate_date {
    local last_attempt="$1"
    if [[ "$last_attempt" =~ ^[0-9]+$ ]]; then
        echo 1
    else
        echo 0
    fi
}

# function to gather the state info, which is needed to update the state after the execution of the tools.
# It reads the current state and updates it based on whether there was an overall failure or not.
# It returns a string with the new state values separated by |, so that they can be easily parsed by the caller.
gather_state_info() {

    last_attempt=$(date "+%s")

    if [[ "$overall_failure" -eq 0 ]]; then
        last_success=$last_attempt
        failure_count=0
    else
        local current_state
        current_state=$(read_state)
        failure_count=$(echo "$current_state" | grep '^failure_count=' | awk -F '=' ' { print $2 } ')
        failure_count=$((failure_count + 1))
        last_success=$(echo "$current_state" | grep '^last_success=' | awk -F '=' ' { print $2 } ')
    fi

    local last_log_path="$LOG_DIR"

    echo "$last_attempt|$last_success|$failure_count|$last_log_path"
}

# function to atomically write the state
update_state() {
    local last_attempt="$1"
    local last_success="$2"
    local failure_count="$3"
    local last_log_path="$4"

    local temp_file="${STATE_FILE}.tmp.$$"

    if ! mkdir -p "$STATE_DIR"; then
        echo "ERROR: Failed to create state directory" >&2
        exit 1
    fi

    # write state to a temporary file first,
    # so that we don't end up with a corrupted state file if the script is interrupted while writing
    {
        echo "last_attempt=$last_attempt"
        echo "last_success=$last_success"
        echo "failure_count=$failure_count"
        echo "last_log_path=$last_log_path"
    } >"$temp_file"

    # moving the temporary file to the final location is an atomic operation,
    # so it either succeeds completely or fails without changing the existing state file
    if ! mv "$temp_file" "$STATE_FILE"; then
        rm -f "$temp_file"
        echo "FATAL: Failed to write state file, this run is silent and did not updated the state file" >&2
        exit 1
    fi

    # changing ownership of state file to root,
    # so that it cannot be modified by non-root users
    # and thus ensures the integrity of the state file
    chown root:root "$STATE_FILE"
    # setting permissions to 644, so that it is readable by everyone but only writable by root
    chmod 644 "$STATE_FILE"
}
