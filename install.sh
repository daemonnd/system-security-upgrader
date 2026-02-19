#!/bin/bash

# strict mode
set -euo pipefail

# trap errors
trap 'echo "Error on line $LINENO: command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

function check_args {
    echo "${1:?ERROR: A valid username with home dir has to be given as first argument}"
    if [[ -d "/home/$1" ]]; then
        echo "$1 is a valid username with home dir."
        username="$1"
    else
        echo "Please enter a valid username with home dir."
        exit 1
    fi
}

function main {
    # checking if the root user is actually running the script
    if [[ "$EUID" -ne 0 ]]; then
        echo "Permission Error: This script needs root privileges or sudo."
        exit 1
    fi
    check_args "$@"

    # copy scripts
     cp upgrade.sh /usr/local/sbin/upgrade
     cp security-check.sh /usr/local/sbin/security-check
     cp ai-summarizer.sh /usr/local/bin/security_upgrader_ai-summarizer

    # set permissions
     chmod +x /usr/local/sbin/upgrade
     chmod +x /usr/local/sbin/security-check
    # change owner to root for the scripts
     chown root:root /usr/local/sbin/upgrade
     chown root:root /usr/local/sbin/security-check

    # set up daemon
     cp security-upgrader.service /etc/systemd/system/security-upgrader.service

    # reload daemons
     systemctl daemon-reload    

     # enable service
     systemctl enable security-upgrader.service

     # create .config dir & copy system prompts in there for fabric
     mkdir -p "/home/${username}/.config/system-security-upgrader/system_prompts"
     cp -r system_prompts/* "/home/${username}/.config/system-security-upgrader/system_prompts/"

    echo "System security upgrader has been installed successfully!"
}

# call main with all args, as given
main "$@"

