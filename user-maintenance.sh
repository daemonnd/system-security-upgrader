#!/bin/bash

set -Eeuo pipefail

readonly STATE_FILE="/var/lib/system-security-upgrader/user-maintenance.state"
readonly STATE_DIR="/var/lib/system-security-upgrader"
export STATE_FILE
export STATE_DIR
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

# source files
# state manager
source ./state-manager.sh
# failure evaluator
source ./failure-evaluator.sh
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
