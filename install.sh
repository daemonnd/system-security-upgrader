#!/bin/bash

# strict mode
set -euo pipefail

# trap errors
trap 'echo "Error on line $LINENO: command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

function check_args {
    : "${1:?ERROR: A valid username with home dir has to be given as first argument}"
    if [[ -d "/home/$1" ]]; then
        echo "$1 is a valid username with home dir."
        user="$1"
    else
        echo "Please enter a valid username with home dir as first argument. $1 does not have a home directory in /home."
        exit 1
    fi
    # if the user wants to install locally
    install_locally=0
    if [[ -z "${2-}" ]]; then
        :
    elif [[ "$2" == "local" ]]; then
        install_locally=1
    else
        echo "Invalid second argument: ${2@Q}. Only local is accepted as second argument."
        exit 1
    fi
}

function init {
    # checking if the root user is actually running the script
    if [[ "$EUID" -ne 0 ]]; then
        echo "Permission Error: This script needs root privileges or sudo."
        exit 1
    fi
    # get the user
    user="$SUDO_USER"
}
function clone {
    git clone https://github.com/daemonnd/system-security-upgrader.git && cd system-security-upgrader
}
function ai_summarizer_unit {
    # create the unit
    cat <<EOF >/etc/systemd/system/security-summarizer.service
[Unit]
Description=Run ai summary against logs of security tools
After=security-upgrader.service
Wants=security-upgrader.service
ConditionPathExists=/var/lib/system-security-upgrader/pending-ai-summary

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ai-summarizer
ExecStartPost=+/usr/bin/rm -f /var/lib/system-security-upgrader/pending-ai-summary
User=${user}
Group=${user}

[Install]
WantedBy=multi-user.target
EOF
    # reload systemctl
    systemctl daemon-reload
}

# validate the installation by checking if the files are in place and the services are enabled
function post_install {
    if [[ ! $(which upgrade) == "/usr/local/sbin/upgrade" ]]; then
        echo "Error: upgrade script is not in place."
        exit 1
    fi
    if [[ ! $(which security-check) == "/usr/local/sbin/security-check" ]]; then
        echo "Error: security-check script is not in place."
        exit 1
    fi
    if [[ ! $(which user-upgrade) == "/usr/local/sbin/user-upgrade" ]]; then
        echo "Error: user-upgrade script is not in place."
        exit 1
    fi
    if [[ ! $(which ai-summarizer) == "/usr/local/bin/ai-summarizer" ]]; then
        echo "Error: ai-summarizer script is not in place."
        exit 1
    fi
    if [[ ! $(which state-manager) == "/usr/local/lib/system-security-upgrader/state-manager" ]]; then
        echo "Error: state-manager script is not in place."
        exit 1
    fi
    if [[ ! $(which failure-evaluator) == "/usr/local/lib/system-security-upgrader/failure-evaluator" ]]; then
        echo "Error: failure-evaluator script is not in place."
        exit 1
    fi
    if [[ ! $(which read-state) == "/usr/local/lib/system-security-upgrader/read-state" ]]; then
        echo "Error: read-state script is not in place."
        exit 1
    fi
    if [[ ! $(systemctl is-enabled security-upgrader.service) == "enabled" ]]; then
        echo "Error: security-upgrader.service is not enabled."
        exit 1
    fi
    if [[ ! $(systemctl is-enabled security-summarizer.service) == "enabled" ]]; then
        echo "Error: security-summarizer.service is not enabled."
        exit 1
    fi
}
function main {
    init "$@"
    check_args "$@"
    if [[ "$install_locally" -eq 1 ]]; then
        echo "Installing system security upgrader from current directory for user $user..."
    else
        echo "Installing system security upgrader from github for user $user..."
        clone
    fi
    ai_summarizer_unit
    #check_args "$@" # not needed, because of $SUDO_USER

    # create necessary directories
    mkdir -p /usr/local/lib/system-security-upgrader
    mkdir -p /var/lib/system-security-upgrader
    mkdir -p /var/log/system-security-upgrader
    chown root:root /usr/local/lib/system-security-upgrader
    chown root:root /var/lib/system-security-upgrader
    chown root:root /var/log/system-security-upgrader
    chmod 755 /usr/local/lib/system-security-upgrader
    chmod 755 /var/lib/system-security-upgrader
    chmod 755 /var/log/system-security-upgrader

    # copy scripts
    cp upgrade.sh /usr/local/sbin/upgrade
    cp security-check.sh /usr/local/sbin/security-check
    cp ./user-maintenance.sh /usr/local/sbin/user-upgrade

    cp ./failure-evaluator.sh /usr/local/lib/system-security-upgrader/failure-evaluator
    cp ./state-manager.sh /usr/local/lib/system-security-upgrader/state-manager
    cp ./ai-summarizer.sh /usr/local/lib/ai-summarizer
    cp ./read-state.sh /usr/local/lib/system-security-upgrader/read-state
    # change owner to root for the scripts
    chown root:root /usr/local/sbin/upgrade
    chown root:root /usr/local/sbin/security-check
    chown root:root /usr/local/sbin/user-upgrade

    chown root:root /usr/local/lib/system-security-upgrader/failure-evaluator
    chown root:root /usr/local/lib/system-security-upgrader/state-manager
    chown "$user":"$user" /usr/local/lib/ai-summarizer
    chown root:root /usr/local/lib/system-security-upgrader/read-state

    # set permissions
    chmod 750 /usr/local/sbin/upgrade
    chmod 750 /usr/local/sbin/security-check
    chmod 750 /usr/local/sbin/user-upgrade

    chmod 750 /usr/local/lib/system-security-upgrader/failure-evaluator
    chmod 750 /usr/local/lib/system-security-upgrader/state-manager
    chmod 750 /usr/local/lib/ai-summarizer
    chmod 750 /usr/local/lib/system-security-upgrader/read-state
    # set up daemon
    cp security-upgrader.service /etc/systemd/system/security-upgrader.service

    # reload daemons
    systemctl daemon-reload

    # enable services
    systemctl enable security-upgrader.service
    systemctl enable security-summarizer.service

    # create .config dir & copy system prompts in there for fabric
    mkdir -p "/home/${user}/.config/system-security-upgrader/system_prompts"
    cp -r system_prompts/* "/home/${user}/.config/system-security-upgrader/system_prompts/"
    chown "$user":"$user" "/home/${user}/.config/system-security-upgrader/"
    chown "$user":"$user" "/home/${user}/.config/system-security-upgrader/"*

    # cp patterns to fabric
    cp -r -- "/home/${user}/.config/system-security-upgrader/system_prompts/." /home/${user}/.config/fabric/patterns/

    echo "System security upgrader has been installed successfully!"
}

# call main with all args, as given
main "$@"
