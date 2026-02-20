#!/bin/bash

# strict mode
set -Eeuo pipefail

# trap errors
trap 'echo "Error on line $LINENO: command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

function check_args {
    echo
}

function init {
    # checking if the root user is actually running the script
    if [[ "$EUID" -ne 0 ]]; then
        echo "Permission Error: This script needs root privileges or sudo." # logging does not work at this point
        exit 1
    fi

    # get the user that should own the ai summary
    # getting the user who executed the script
    user="${1:-$SUDO_USER}"
    # check if the user have a home dir for config
    if [[ -d "/home/${user}" ]]; then
        echo "The user ${user@Q} has a home dir."
    else
        echo "The user ${user@Q} does not have a home dir."
        echo "Please restart the script by substituting the user with 'su <username>' or append the username as first argument."
        exit 1
    fi  
    
    # create logfile path pattern
    logpattern=$(date "+%Y-%m-%d_%H-%M-%S")

    # create logdir path
    logdir="/var/log/system-security-upgrader/${logpattern}_upgrade/"

    # create neccessary dirs
    mkdir -p /var/log/system-security-upgrader/
    mkdir "$logdir"

    # create security check trigger dir
    mkdir -p /var/lib/system-security-upgrader/

    echo "Executing upgrade script as root..."
}
function run_cmd {
    local description="$1"
    shift
    local logfile="$1"
    shift

    echo "${description}..."
    if "$@" &>> "$logfile" 2>&1; then
        echo "${description}... Done"
    else
        local exit_code="$?"
        echo "${description} failed with exit code ${exit_code}. Check logfile: '${logfile}'"
        exit "$exit_code"
    fi
}
function update_mirrorlists {
    # update the mirrorlists
    local reflector_logfile="${logdir}reflector.log"
    run_cmd "Updating the mirrorlists" "$reflector_logfile" reflector --latest 20 --country Germany,Netherlands,Belgium  --sort rate --save /etc/pacman.d/mirrorlist 
}
function upgrade_system {
    # upgrade the system
    local pacman_logfile="${logdir}pacman.log"
    run_cmd "Upgrading the system" "$pacman_logfile" pacman -Syu --noconfirm 
}
function end_script {
    # ask the user if the system should reboot
    while true; do
        read -p "Upgrade successful. Reboot now? (y/n) " answer
        if [[ "${answer,}" == "y" ]]; then
            touch /var/lib/system-security-upgrader/pending-check # touch file so that the service knows when to run
            reboot
        elif [[ "${answer,}" == "n" ]]; then
            echo "$user" > /var/lib/system-security-upgrader/pending-check # create the file with the user in it so that the service knows when to run and knows the right user
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
    update_mirrorlists

    # upgrade the system
    upgrade_system

    # echo the time
    echo "Updating the mirrorlists & upgrading the system took $SECONDS seconds."
    echo "Logs of the used tools have been logged to ${logdir@Q}"

    # end the script by asking the user wether to reboot or not
    end_script
}

# call main with all args, as given
main "$@"

