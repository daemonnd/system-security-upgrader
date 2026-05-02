#!/bin/bash

set -Eeuo pipefail

readonly STATE_FILE="/var/lib/system-security-upgrader/user-maintenance.state"
readonly STATE_DIR="/var/lib/system-security-upgrader"
readonly LOG_BASE_DIR="/var/log/system-security-upgrader"
readonly PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

declare -g HOME=""
declare -g LOG_DIR=""
declare -g YAY_LOG=""
declare -g FLATPAK_LOG=""
declare -g overall_failure=0
declare -g env_level=1
declare -g env_reason="ok"

# -----------------------------------------------------------------------------
# 1. Environment Validator
# -----------------------------------------------------------------------------

SUDO_USER="${SUDO_USER:-$USER}"

if [[ -z "${SUDO_USER+x}" || -z "$SUDO_USER" ]]; then
    env_level=3
    env_reason="SUDO_USER is not set or empty"
fi

if ! home_from_getent="$(getent passwd "$SUDO_USER" | cut -d: -f6)"; then
    env_level=3
    env_reason="could not get user home from getent"
fi

if [[ -z "$home_from_getent" ]]; then
    env_level=3
    env_reason="home directory from getent is empty"
fi

HOME="$home_from_getent"

# -----------------------------------------------------------------------------
# 2. Command Executor
# -----------------------------------------------------------------------------
#
# function to execute a non-interactive command with a timeout and log its output to a file.
execute_command() {
    set +e
    local timeout_seconds="$1"
    shift
    local log_file="$1"
    shift

    timeout "$timeout_seconds" "$@" </dev/null >>"$log_file" 2>&1
    local exit_code=$?

    echo "$exit_code"
    set -e
}

# -----------------------------------------------------------------------------
# 3. Failure Evaluator
# -----------------------------------------------------------------------------
#
# function to evaluate the failure of a command based on its exit code and the content of its log file.
# It uses common conventions for exit codes and also checks for common error keywords in the log file.
# Return:
# Error level| reason for the error
evaluate_failure() {
    local exit_code="$1"
    local log_file="$2"

    if [[ "$exit_code" -eq 126 || "$exit_code" -eq 127 ]]; then
        echo "3|The command did not execute at all"
    elif [[ ! -r "$log_file" ]]; then
        echo "2|Logfile does not exist"
    elif [[ "$exit_code" -eq 124 ]]; then
        echo "2|Timout reached"
    elif [[ "$exit_code" -ne 0 ]]; then
        echo "2|Exit code of command is $exit_code, not 0"
        return
    elif [[ -f "$log_file" ]]; then
        if grep -qiE "(error:|failed)" "$log_file" 2>/dev/null; then
            echo "2|Logs of tool contained keywords that are common for errors"
            return
        else
            echo "1|success"
        fi
    else
        echo "2|Unknown failure with exit code $exit_code"
    fi
}

# -----------------------------------------------------------------------------
# 4. State Manager
# -----------------------------------------------------------------------------
# function to set the state variables to their default values,
# which are used when the state file is not valid or does not exist.
set_state_to_default() {
    last_attempt=0
    last_success=0
    failure_count=0
    last_log_path=""
}

# function to read the state from the state file.
# If the state file does not exist, it sets the state to default values.
read_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
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
    if [[ "$last_attempt_valid" == "false" ]]; then
        set_state_to_default
    fi

    local last_success_valid
    last_success_valid=$(validate_date "$last_success" "last_success")
    if [[ "$last_success_valid" == "false" ]]; then
        return
    fi

    if [[ "$failure_count" =~ ^[0-9]+$ ]]; then
        :
    else
        set_state_to_default
    fi

    if [[ ! -f "$last_log_path" ]]; then
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
validate_date() {
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
        failure_count=$(echo "$current_state" | grep '^failure_count=' | cut -d= -f2)
        failure_count=$((failure_count + 1))
        last_success=$(echo "$current_state" | grep '^last_success=' | cut -d= -f2)
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

# -----------------------------------------------------------------------------
# 5. Orchestrator
# -----------------------------------------------------------------------------
#
# create a log directory for the current run, which is based on the current timestamp.
create_log_directory() {
    local timestamp
    timestamp="$(date +%Y-%m-%d_%H-%M-%S)"

    LOG_DIR="${LOG_BASE_DIR}/${timestamp}_user-maintenance"

    echo "INFO: Log directory: $LOG_DIR"

    if ! mkdir -p "$LOG_DIR"; then
        echo "ERROR: Failed to create log directory, exiting" >&2
        exit 1
    fi

    YAY_LOG="${LOG_DIR}/yay.log"
    FLATPAK_LOG="${LOG_DIR}/flatpak.log"

    touch "$YAY_LOG"
    touch "$FLATPAK_LOG"
}

# run yay interactively as the user,
# so that it can ask for password if needed and also
# has access to the correct home directory and thus the yay database
run_yay() {
    sudo -u "$SUDO_USER" env HOME="$HOME" yay -Syu --needed 2>&1 | tee "$YAY_LOG"
}

# run flatpak as root, but with the environment of the user, so that it
# has access to the correct home directory and thus the flatpak installation
# of the user. It does not need to ask for password, because it is already run with sudo
run_flatpak() {
    local exit_code
    exit_code=$(execute_command 1200 "$FLATPAK_LOG" "sudo" "runuser" "-u" "user" "--" "env" "HOME=/home/user" "flatpak" "update" "--assumeyes")
    echo "$exit_code"
}

# main function to orchestrate the execution of the script
main() {
    if [[ "$env_level" -eq 3 ]]; then
        overall_failure=1
        echo "FATAL: Error while validating the environment: $env_reason"
        local state_info
        state_info=$(gather_state_info)
        last_attempt=$(awk -F '|' '{print $1}' <<<"$state_info")
        last_success=$(awk -F '|' '{print $2}' <<<"$state_info")
        failure_count=$(awk -F '|' '{print $3}' <<<"$state_info")
        last_log_path=$(awk -F '|' '{print $4}' <<<"$state_info")
        update_state "$last_attempt" "$last_success" "$failure_count" "$last_log_path"
        exit 1
    elif [[ "$env_level" -eq 2 ]]; then
        echo "ERROR: Error while validating the environment: $env_reason"
        overall_failure=1
    fi
    echo "INFO: Env validated successfully"

    create_log_directory

    # run yay with set +e,
    # so that we can capture the exit code and evaluate it,
    # instead of exiting immediately on failure
    set +e
    run_yay
    local yay_exit_code="$?"
    set -e

    # evaluate the failure of yay based on its exit code and the content of its log file,
    # and update the overall failure level accordingly
    local yay_evaluation
    yay_evaluation="$(evaluate_failure "$yay_exit_code" "$YAY_LOG")"
    local yay_level="${yay_evaluation%%|*}"
    local yay_reason="${yay_evaluation##*|}"
    echo "INFO: yay evaluation: level=$yay_level, reason=$yay_reason"
    if [[ "$yay_level" -eq 3 ]]; then
        overall_failure=1
        echo "FATAL: Error while updating packages with yay: $yay_reason"
        local state_info
        state_info=$(gather_state_info)
        last_attempt=$(awk -F '|' '{print $1}' <<<"$state_info")
        last_success=$(awk -F '|' '{print $2}' <<<"$state_info")
        failure_count=$(awk -F '|' '{print $3}' <<<"$state_info")
        last_log_path=$(awk -F '|' '{print $4}' <<<"$state_info")
        update_state "$last_attempt" "$last_success" "$failure_count" "$last_log_path"
        exit 1
    elif [[ "$yay_level" -eq 2 ]]; then
        echo "ERROR: Error while updating packages with yay: $yay_reason"
        overall_failure=1
    fi
    echo "INFO: yay finished updating aur packages"

    local flatpak_exit_code
    flatpak_exit_code=$(run_flatpak)

    # evaluate the failure of flatpak based on its exit code and the content of its log file,
    # and update the overall failure level accordingly
    local flatpak_evaluation
    flatpak_evaluation="$(evaluate_failure "$flatpak_exit_code" "$FLATPAK_LOG")"
    local flatpak_level="${flatpak_evaluation%%|*}"
    local flatpak_reason="${flatpak_evaluation##*|}"
    if [[ "$flatpak_level" -eq 3 ]]; then
        overall_failure=1
        echo "FATAL: Error while updating packages with flatpak: $flatpak_reason"
        local state_info
        state_info=$(gather_state_info)
        last_attempt=$(awk -F '|' '{print $1}' <<<"$state_info")
        last_success=$(awk -F '|' '{print $2}' <<<"$state_info")
        failure_count=$(awk -F '|' '{print $3}' <<<"$state_info")
        last_log_path=$(awk -F '|' '{print $4}' <<<"$state_info")
        update_state "$last_attempt" "$last_success" "$failure_count" "$last_log_path"
        exit 1
    elif [[ "$flatpak_level" -eq 2 ]]; then
        echo "ERROR: Error while updating packages with flatpak: $flatpak_reason"
        overall_failure=1
    fi
    echo "INFO: flatpak finished updating flatpaks"

    local state_info
    state_info=$(gather_state_info)
    last_attempt=$(awk -F '|' '{print $1}' <<<"$state_info")
    last_success=$(awk -F '|' '{print $2}' <<<"$state_info")
    failure_count=$(awk -F '|' '{print $3}' <<<"$state_info")
    last_log_path=$(awk -F '|' '{print $4}' <<<"$state_info")
    update_state "$last_attempt" "$last_success" "$failure_count" "$last_log_path"

    if [[ "$overall_failure" -eq 0 ]]; then
        exit 0
    else
        echo "INFO: Exiting with 1 because something had failure level 2"
        exit 1
    fi
}

main "$@"
