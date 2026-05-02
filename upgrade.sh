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

function init {
    # initialize the script by getting information and creating dirs for the next steps

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

    # init variables
    declare -g overall_failure=0

    # create logfile path pattern
    logpattern=$(date "+%Y-%m-%d_%H-%M-%S")

    # create logdir path
    LOGDIR="/var/log/system-security-upgrader/${logpattern}_upgrade/"
    REFLECTOR_LOG="${LOGDIR}reflector.log"
    PACMAN_LOG="${LOGDIR}pacman.log"

    # create neccessary dirs
    mkdir -p /var/log/system-security-upgrader/
    mkdir "$LOGDIR"

    # create security check trigger dir
    mkdir -p /var/lib/system-security-upgrader/

    echo "Executing upgrade script as root..."
}
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

function update_mirrorlists {
    # update the mirrorlists using reflector
    local REFLECTOR_LOG="${LOGDIR}reflector.log"
    run_cmd "Updating the mirrorlists" "$REFLECTOR_LOG" 300 reflector --latest 20 --country Germany,Netherlands,Belgium --sort rate --save /etc/pacman.d/mirrorlist
}

function upgrade_system {
    # upgrade the system
    local pacman_logfile="${LOGDIR}pacman.log"
    run_cmd "Upgrading the system" "$pacman_logfile" pacman -Syu --noconfirm
}

function end_script {
    # end the script by asking the user wether to reboot, and creating a trigger file for phase 2
    # ask the user if the system should reboot
    while true; do
        read -p "Upgrade successful. Reboot now? (y/n) " answer
        if [[ "${answer,}" == "y" ]]; then
            echo "$user" >/var/lib/system-security-upgrader/pending-check # touch file so that the service knows when to run
            reboot
        elif [[ "${answer,}" == "n" ]]; then
            echo "USER: $user"
            echo "$user" >/var/lib/system-security-upgrader/pending-check # create the file with the user in it so that the service knows when to run and knows the right user
            echo "After the next reboot, the security of the system will be checked."
            exit 0
        else
            echo "Please enter valid input. Possible options: 'y' for yes (reboot now) and 'n' for no (do not reboot now)."
        fi
    done
}
function main {
    # init the script
    init "$@"

    # update the mirrorlists
    set +e
    run_cmd "Updating the mirrorlists" "$REFLECTOR_LOG" 300 reflector --latest 20 --country Germany,Netherlands,Belgium --sort rate --save /etc/pacman.d/mirrorlist
    reflector_exit_code="$?"
    set -e
    local reflector_evaluation
    reflector_evaluation="$(evaluate_failure "$reflector_exit_code" "$REFLECTOR_LOG")"
    local reflector_level="${reflector_evaluation%%|*}"
    local reflector_reason="${reflector_evaluation##*|}"
    echo "INFO: Mirrorlist updating with reflector: level=$reflector_level, reason=$reflector_reason"
    if [[ "$reflector_level" -eq 3 ]]; then
        echo "FATAL: Error while updating mirrorlists with reflector: $reflector_reason"
        exit 1
    elif [[ "$reflector_level" -eq 2 ]]; then
        echo "ERROR: Possible issue while updating mirrorlists with reflector: $reflector_reason. Check logfile: ${REFLECTOR_LOG@Q}"
        echo "INFO: Exiting because mirrorlist update is crucial for the next steps. Please fix the issue and try again."
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
        echo "FATAL: Error while upgrading the system with pacman: $pacman_reason"
        exit 1
    elif [[ "$pacman_level" -eq 2 ]]; then
        echo "ERROR: Error while upgrading the system with pacman: $pacman_reason. Check logfile: ${PACMAN_LOG@Q}"
        exit 1
    fi
    echo "INFO: System upgrade with pacman finished"

    # echo the time
    echo "Updating the mirrorlists & upgrading the system took $SECONDS seconds."
    echo "Logs of the used tools have been logged to ${LOGDIR@Q}"

    # end the script by asking the user wether to reboot or not
    end_script
}

# call main with all args, as given
main "$@"
