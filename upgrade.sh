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
    if [[ "$EUID" -ne 0 ]]; then
        echo "Permission Error: This script needs root privileges or sudo." # logging does not work at this point
        exit 1
    fi

    # get the user that should own the ai summary
    # getting the user who executed the script
    user="${1:?ERROR: The first arg has to be the username of the regular user}"
    echo "DEBUG: user home directory:"
    if ! getent passwd "$user" | awk -F ':' ' { print $6 } '; then
        echo "ERROR: It seems that the user $user does not have a home dir."
        exit 1
    fi
    reboot="${2:?ERROR: second arg must be 0 or 1}"
    if [[ -z "$reboot" || ("$reboot" != "0" && "$reboot" != "1") ]]; then
        echo "ERROR: second arg for reboot or not is not 0 or 1, it is $reboot"
        exit 1
    fi
    # check if the user have a home dir for config
    home_dir=$(getent passwd "$user" | awk -F ':' ' { print $6 } ')
    if [[ -d "$home_dir" ]]; then
        echo "The user ${user@Q} has a home dir."
    else
        echo "The user ${user@Q} does not have a home dir."
        echo "Please restart the script by substituting the user with 'su <username>' or running install.sh as a valid user with a homedir."
        exit 1
    fi

    # initialize variables
    export overall_failure=0
    # define variables for state file
    export STATE_FILE="/var/lib/system-security-upgrader/sys-upgrade.state"
    export STATE_DIR="/var/lib/system-security-upgrader/"

    # create logfile path pattern
    logpattern=$(date "+%Y-%m-%d_%H-%M-%S")

    # create logdir path
    export LOG_DIR="/var/log/system-security-upgrader/${logpattern}_upgrade/"
    REFLECTOR_LOG="${LOG_DIR}reflector.log"
    PACMAN_LOG="${LOG_DIR}pacman.log"

    # source files
    # state manager
    source /usr/local/lib/system-security-upgrader/state-manager
    # failure evaluator
    source /usr/local/lib/system-security-upgrader/failure-evaluator
    # create neccessary dirs
    mkdir -p "$LOG_DIR"

    # create security check trigger dir
    mkdir -p /var/lib/system-security-upgrader/

    echo "Executing upgrade script as root..."
    echo "INFO: Log directory: $LOG_DIR"
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
# 5. Orchestration
# ---------------------------------------------------------------------------------

# function to end the script by asking the user wether to reboot, and creating a trigger file for phase 2
function end_script {
    if [[ "$reboot" -eq 1 ]]; then
        echo "rebooting..."
        echo "$user" >/var/lib/system-security-upgrader/pending-check # touch file so that the service knows when to run
        reboot
    elif [[ "$reboot" -eq 0 ]]; then
        echo "$user" >/var/lib/system-security-upgrader/pending-check # create the file with the user in it so that the service knows when to run and knows the right user
        echo "After the next reboot, the security of the system will be checked."
        exit 0
    else
        echo "Invalid second arg for determining if the system should reboot: $reboot"
    fi
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
        echo "ERROR: Error while updating mirrorlists with reflector: $reflector_reason. Check logfile: ${REFLECTOR_LOG@Q}"
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
