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
execute_command() {
    set +e

    local timeout_seconds="$1"
    shift
    local log_file="$1"
    shift
    printf 'EXEC:' >>"$log_file"
    for arg in "$@"; do
        printf ' [%s]' "$arg" >>"$log_file"
    done
    printf '\n' >>"$log_file"
    if [[ "$#" -eq 0 ]]; then
        echo "NO COMMAND PROVIDED" >&2
        return 2
    fi

    for arg in "$@"; do
        printf 'ARG=%q\n' "$arg" >>"$log_file"
    done

    timeout "$timeout_seconds" -- "$@" </dev/null >>"$log_file" 2>&1
    local exit_code=$?

    echo "$exit_code"
    set -e
}

# -----------------------------------------------------------------------------
# 3. Failure Evaluator
# -----------------------------------------------------------------------------
# Return:
# Error level
#
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
set_state_to_default() {
    last_attempt=0
    last_success=0
    failure_count=0
    last_log_path=""
}

read_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        set_state_to_default
        return
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
        return
    fi

    local last_success_valid
    last_success_valid=$(validate_date "$last_success" "last_success")
    if [[ "$last_success_valid" == "false" ]]; then
        set_state_to_default
        return
    fi

    if [[ "$failure_count" =~ ^[0-9]+$ ]]; then
        :
    else
        echo "failure_count is $failure_count in $STATE_FILE, but it has to be an integer" >&2
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

validate_date() {
    local last_attempt="$1"
    local description="$2"
    if [[ "$last_attempt" =~ ^[0-9]+$ ]]; then
        :
    else
        echo "$description is $last_attempt in $STATE_FILE, but it has to be a date in the YYYY-mm-dd format." >&2
    fi
}

gather_state_info() {
    local last_success
    local failure_count
    local last_attempt

    last_attempt=$(date "+%s")

    if [[ "$overall_failure" -eq 0 ]]; then
        last_success=$last_attempt
        failure_count=0
    else
        local current_state
        current_state=$(read_state)
        failure_count=$(echo "$current_state" | grep '^failure_count=' | cut -d= -f2)
        failure_count=$((failure_count + 1))
    fi

    local last_log_path="$LOG_DIR"

    echo "$last_attempt|$last_success|$failure_count|$last_log_path"
}

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

    {
        echo "last_attempt=$last_attempt"
        echo "last_success=$last_success"
        echo "failure_count=$failure_count"
        echo "last_log_path=$last_log_path"
    } >"$temp_file"

    if ! mv "$temp_file" "$STATE_FILE"; then
        rm -f "$temp_file"
        echo "ERROR: Failed to write state file" >&2
        exit 1
    fi

    chmod 644 "$STATE_FILE"
}

# -----------------------------------------------------------------------------
# 5. Orchestrator
# -----------------------------------------------------------------------------
create_log_directory() {
    local timestamp
    timestamp="$(date +%Y-%m-%d_%H-%M-%S)"

    LOG_DIR="${LOG_BASE_DIR}/${timestamp}_user-maintenance"

    echo "INFO: Log directory: $LOG_DIR"

    if ! mkdir -p "$LOG_DIR"; then
        echo "ERROR: Failed to create log directory" >&2
        exit 1
    fi

    YAY_LOG="${LOG_DIR}/yay.log"
    FLATPAK_LOG="${LOG_DIR}/flatpak.log"

    touch "$YAY_LOG"
    touch "$FLATPAK_LOG"
}

run_yay() {
    local exit_code

    exit_code=$(
        execute_command 3600 "$YAY_LOG" \
            runuser -u "$SUDO_USER" -- \
            env HOME="$HOME" \
            yay -Syu --noconfirm
    )
    echo "$exit_code"
}

run_flatpak() {
    local exit_code
    exit_code=$(execute_command 1200 "$FLATPAK_LOG" "sudo" "runuser" "-u" "user" "--" "env" "HOME=/home/user" "flatpak" "update" "--assumeyes")
    echo "$exit_code"
}

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
    echo "Env validated successfully"
    echo "USER=$SUDO_USER"

    create_log_directory
    echo "log dir created successfully"
    echo "home: $HOME"

    local yay_exit_code
    echo "before running yay"
    yay_exit_code=$(run_yay)
    echo "after runnning yay"
    #yay_exit_code=0
    local yay_evaluation
    yay_evaluation="$(evaluate_failure "$yay_exit_code" "$YAY_LOG")"
    local yay_level="${yay_evaluation%%|*}"
    local yay_reason="${yay_evaluation##*|}"
    echo "yay evaluation: level=$yay_level, reason=$yay_reason"
    echo "yay exit code: $yay_exit_code"
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
    echo "INFO: yay executed successfully"

    local flatpak_exit_code
    #flatpak_exit_code=$(run_flatpak)
    flatpak_exit_code=0
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
    echo "INFO: flatpak executed successfully"

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
