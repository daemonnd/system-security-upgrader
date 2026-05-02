#!/bin/bash

# strict mode
set -Eeuo pipefail

# Cleanup function
function cleanup {
    echo
    echo "Script interupted or failed. Cleaning up..."
    echo "Upgrade script did not complete."
    echo "Possible causes:"
    echo "  - Script was interupted"

    exit 1
}

# trap errors
trap 'echo "Error on line $LINENO: command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

# trap signals
trap 'cleanup' INT TERM
function check_args {
    echo
}

# ---------------------------------------------------------------------------------
# 1. Initialization
# ---------------------------------------------------------------------------------
# initialize the script by getting information and creating dirs for the next steps
function init {

    # checking if the root user is actually running the script
    if [[ "$EUID" -ne 0 || -z "$SUDO_USER" ]]; then
        echo "Permission Error: This script needs root privileges or sudo." # logging does not work at this point
        exit 1
    fi

    # get the user that should own the ai summary
    # getting the user who executed the script
    user="$SUDO_USER"
    # check if the user have a home dir for config
    home_dir=$(getent passwd "$user" | awk -F ':' ' { print $6 } ')
    if [[ -d "$home_dir" ]]; then
        echo "The user ${user@Q} has a home dir."
    else
        echo "The user ${user@Q} does not have a home dir."
        echo "Please restart the script by substituting the user with 'su <username>' or running $(install.sh) as a valid user with a homedir."
        exit 1
    fi

    # initialize variables
    export overall_failure=0
    # define variables for state file
    STATE_FILE="/var/lib/system-security-upgrader/sys-upgrade.state"
    STATE_DIR="/var/lib/system-security-upgrader/"

    # create logfile path pattern
    logpattern=$(date "+%Y-%m-%d_%H-%M-%S")

    # create logdir path
    LOG_DIR="/var/log/system-security-upgrader/${logpattern}_upgrade/"
    REFLECTOR_LOG="${LOG_DIR}reflector.log"
    PACMAN_LOG="${LOG_DIR}pacman.log"

    # create neccessary dirs
    mkdir -p "$LOG_DIR"

    # create security check trigger dir
    mkdir -p /var/lib/system-security-upgrader/

    echo "Executing upgrade script as root..."
}

# ---------------------------------------------------------------------------------
# 2. Command Executor
# ---------------------------------------------------------------------------------
# function to run a command with a description, log its output to a logfile, and handle any failures by returning the exit code of the command
function run_cmd {
    # runs a command, logs its output, and handles any failures
    local description="$1"
    shift
    local logfile="$1"
    shift
    local timeout_seconds="$1"
    shift

    echo "${description}..."
    if timeout "$timeout_seconds" "$@" >>"$logfile" 2>&1; then
        echo "${description}... Done"
        return 0
    else
        local exit_code="$?"
        return "$exit_code"
    fi
}

# ---------------------------------------------------------------------------------
# 3. Failure Evaluator
# ---------------------------------------------------------------------------------
# function to evaluate the failure of a command based on its exit code and logfile, and to return a severity level and a reason for the failure
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
        if grep -qiE "(error:)" "$log_file" 2>/dev/null; then # does not include "failed" because reflector's warnings include "failed" as well, which are not necessarily an issue
            echo "2|Logs of tool contained keywords that are common for errors"
            return
        else
            echo "1|success"
        fi
    else
        echo "2|Unknown failure with exit code $exit_code"
    fi
}

# ---------------------------------------------------------------------------------
# 4. State Manager
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

# ---------------------------------------------------------------------------------
# 5. Orchestration
# ---------------------------------------------------------------------------------

# function to end the script by asking the user wether to reboot, and creating a trigger file for phase 2
function end_script {
    # ask the user if the system should reboot
    while true; do
        read -p "Upgrade successful. Reboot now? (y/n) " answer
        if [[ "${answer,}" == "y" ]]; then
            echo "$user" >/var/lib/system-security-upgrader/pending-check # touch file so that the service knows when to run
            reboot
        elif [[ "${answer,}" == "n" ]]; then
            echo "$user" >/var/lib/system-security-upgrader/pending-check # create the file with the user in it so that the service knows when to run and knows the right user
            echo "After the next reboot, the security of the system will be checked."
            exit 0
        else
            echo "Please enter valid input. Possible options: 'y' for yes (reboot now) and 'n' for no (do not reboot now)."
        fi
    done
}

# main orchestration function, which calls the other functions in the right order and handles their output
function main {
    # init the script
    init "$@"

    # update the mirrorlists
    set +e
    run_cmd "Updating the mirrorlists" "$REFLECTOR_LOG" 300 reflector --latest 10 --country Germany,Netherlands,Belgium --sort rate --save /etc/pacman.d/mirrorlist
    reflector_exit_code="$?"
    set -e
    local reflector_evaluation
    reflector_evaluation="$(evaluate_failure "$reflector_exit_code" "$REFLECTOR_LOG")"
    local reflector_level="${reflector_evaluation%%|*}"
    local reflector_reason="${reflector_evaluation##*|}"
    echo "INFO: Mirrorlist updating with reflector: level=$reflector_level, reason=$reflector_reason"
    if [[ "$reflector_level" -eq 3 ]]; then
        overall_failure=1
        echo "FATAL: Error while updating mirrorlists with reflector: $reflector_reason"
        local state_info
        state_info=$(gather_state_info)
        last_attempt=$(awk -F '|' ' { print $1 } ' <<<"$state_info")
        last_success=$(awk -F '|' ' { print $2 } ' <<<"$state_info")
        failure_count=$(awk -F '|' ' { print $3 } ' <<<"$state_info")
        last_log_path=$(awk -F '|' ' { print $4 } ' <<<"$state_info")
        update_state "$last_attempt" "$last_success" "$failure_count" "$last_log_path"
        exit 1
    elif [[ "$reflector_level" -eq 2 ]]; then
        overall_failure=1
        echo "ERROR: Possible issue while updating mirrorlists with reflector: $reflector_reason. Check logfile: ${REFLECTOR_LOG@Q}"
        echo "INFO: Exiting because mirrorlist update is crucial for the next steps. Please fix the issue and try again."
        local state_info
        state_info=$(gather_state_info)
        last_attempt=$(awk -F '|' ' { print $1 } ' <<<"$state_info")
        last_success=$(awk -F '|' ' { print $2 } ' <<<"$state_info")
        failure_count=$(awk -F '|' ' { print $3 } ' <<<"$state_info")
        last_log_path=$(awk -F '|' ' { print $4 } ' <<<"$state_info")
        update_state "$last_attempt" "$last_success" "$failure_count" "$last_log_path"
        exit 1
    fi
    echo "INFO: Reflector finished updating the mirrorlists"

    # upgrade the system
    set +e
    run_cmd "Upgrading the system" "$PACMAN_LOG" 3600 pacman -Syu --noconfirm
    pacman_exit_code="$?"
    set -e
    local pacman_evaluation
    pacman_evaluation="$(evaluate_failure "$pacman_exit_code" "$PACMAN_LOG")"
    local pacman_level="${pacman_evaluation%%|*}"
    local pacman_reason="${pacman_evaluation##*|}"
    echo "INFO: System upgrade with pacman: level=$pacman_level, reason=$pacman_reason"
    if [[ "$pacman_level" -eq 3 ]]; then
        overall_failure=1
        echo "FATAL: Error while upgrading the system with pacman: $pacman_reason"
        local state_info
        state_info=$(gather_state_info)
        last_attempt=$(awk -F '|' ' { print $1 } ' <<<"$state_info")
        last_success=$(awk -F '|' ' { print $2 } ' <<<"$state_info")
        failure_count=$(awk -F '|' ' { print $3 } ' <<<"$state_info")
        last_log_path=$(awk -F '|' ' { print $4 } ' <<<"$state_info")
        update_state "$last_attempt" "$last_success" "$failure_count" "$last_log_path"
        exit 1
    elif [[ "$pacman_level" -eq 2 ]]; then
        overall_failure=1
        echo "ERROR: Error while upgrading the system with pacman: $pacman_reason. Check logfile: ${PACMAN_LOG@Q}"
        local state_info
        state_info=$(gather_state_info)
        last_attempt=$(awk -F '|' ' { print $1 } ' <<<"$state_info")
        last_success=$(awk -F '|' ' { print $2 } ' <<<"$state_info")
        failure_count=$(awk -F '|' ' { print $3 } ' <<<"$state_info")
        last_log_path=$(awk -F '|' ' { print $4 } ' <<<"$state_info")
        update_state "$last_attempt" "$last_success" "$failure_count" "$last_log_path"
        exit 1
    fi
    echo "INFO: System upgrade with pacman finished"

    # update the state file with new information
    local state_info
    state_info=$(gather_state_info)
    last_attempt=$(awk -F '|' ' { print $1 } ' <<<"$state_info")
    last_success=$(awk -F '|' ' { print $2 } ' <<<"$state_info")
    failure_count=$(awk -F '|' ' { print $3 } ' <<<"$state_info")
    last_log_path=$(awk -F '|' ' { print $4 } ' <<<"$state_info")
    update_state "$last_attempt" "$last_success" "$failure_count" "$last_log_path"

    # echo the time
    echo "Updating the mirrorlists & upgrading the system took $SECONDS seconds."
    echo "Logs of the used tools have been logged to ${LOG_DIR@Q}"

    # end the script by asking the user wether to reboot or not
    end_script
}

# call main with all args, as given
main "$@"
