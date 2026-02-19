#!/bin/bash

# strict mode
set -euo pipefail

# trap errors
trap 'echo "Error on line $LINENO: command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

function check_args {
    echo 
}

function main {
    # checking if the root user is actually running the script
    if [[ "$EUID" -ne 0 ]]; then
        echo "Permission Error: This script needs root privileges or sudo."
        exit 1
    fi

    # copy scripts
     cp upgrade.sh /usr/local/sbin/upgrade
     cp security-check.sh /usr/local/sbin/security-check

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

    echo "System security upgrader has been installed successfully!"
}

# call main with all args, as given
main "$@"

