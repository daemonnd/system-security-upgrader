#!/bin/bash

# strict mode
set -euo pipefail

# trap errors
trap 'echo "ERROR on line $LINENO: command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

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
        echo "Permission ERROR: This script needs root privileges or sudo."
        exit 1
    fi
    # get the user
    user="$SUDO_USER"
}
function clone {
    git clone https://github.com/daemonnd/system-security-upgrader.git && cd system-security-upgrader
}
function sys_upgrade_unit {
    cat <<EOF >/etc/systemd/system/sys-upgrade.service
[Unit]
Description=Upgrade the system
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/lib/system-security-upgrader/upgrade ${user} 0
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
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
ExecStart=/usr/local/lib/system-security-upgrader/ai-summarizer
ExecStartPost=+/usr/bin/rm -f /var/lib/system-security-upgrader/pending-ai-summary
User=${user}
Group=${user}

[Install]
WantedBy=multi-user.target
EOF
}

function security_upgrader_unit {
    # create the unit
    cat <<EOF >/etc/systemd/system/security-upgrader.service
[Unit]
Description=Run post-upgrade security checks
After=network-online.target
Wants=network-online.target
ConditionPathExists=/var/lib/system-security-upgrader/pending-check


[Service]
Type=oneshot
ExecStartPre=/usr/local/lib/system-security-upgrader/read-state sys-upgrade.state
ExecStart=/usr/local/sbin/security-check
ExecStartPost=/usr/local/lib/system-security-upgrader/read-state security-check.state
User=root
Group=root
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
}

# validate the installation by checking if the files are in place and the services are enabled
function post_install {
    if [[ ! $(which security-check) == "/usr/local/sbin/security-check" ]]; then
        echo "ERROR: security-check script is not in place."
        exit 1
    fi
    if [[ ! $(which user-upgrade) == "/usr/local/sbin/user-upgrade" ]]; then
        echo "ERROR: user-upgrade script is not in place."
        exit 1
    fi
    if [[ ! -f "/usr/local/lib/system-security-upgrader/upgrade" ]]; then
        echo "ERROR: upgrade script is not in place."
        exit 1
    fi
    if [[ ! -f "/usr/local/lib/system-security-upgrader/ai-summarizer" ]]; then
        echo "ERROR: ai-summarizer script is not in place."
        exit 1
    fi
    if [[ ! -f "/usr/local/lib/system-security-upgrader/user-maintenance" ]]; then
        echo "ERROR: user-maintenance script is not in place."
        exit 1
    fi
    if [[ ! -f "/usr/local/lib/system-security-upgrader/state-manager" ]]; then
        echo "ERROR: state-manager script is not in place."
        exit 1
    fi
    if [[ ! -f "/usr/local/lib/system-security-upgrader/failure-evaluator" ]]; then
        echo "ERROR: failure-evaluator script is not in place."
        exit 1
    fi
    if [[ ! -f "/usr/local/lib/system-security-upgrader/read-state" ]]; then
        echo "ERROR: read-state script is not in place."
        exit 1
    fi
    if [[ ! $(systemctl is-enabled security-upgrader.service) == "enabled" ]]; then
        echo "ERROR: security-upgrader.service is not enabled."
        exit 1
    fi
    if [[ ! $(systemctl is-enabled security-summarizer.service) == "enabled" ]]; then
        echo "ERROR: security-summarizer.service is not enabled."
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
    sys_upgrade_unit
    security_upgrader_unit
    ai_summarizer_unit
    # reload systemctl
    systemctl daemon-reload

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
    cp security-check.sh /usr/local/sbin/security-check
    cp ./run-full-user-maintenance.sh /usr/local/sbin/user-upgrade

    cp ./upgrade.sh /usr/local/lib/system-security-upgrader/upgrade
    cp ./failure-evaluator.sh /usr/local/lib/system-security-upgrader/failure-evaluator
    cp ./user-maintenance.sh /usr/local/lib/system-security-upgrader/user-maintenance
    cp ./state-manager.sh /usr/local/lib/system-security-upgrader/state-manager
    cp ./ai-summarizer.sh /usr/local/lib/system-security-upgrader/ai-summarizer
    cp ./read-state.sh /usr/local/lib/system-security-upgrader/read-state
    # change owner to root for the scripts
    chown root:root /usr/local/sbin/security-check
    chown root:root /usr/local/sbin/user-upgrade

    chown root:root /usr/local/lib/system-security-upgrader/upgrade
    chown root:root /usr/local/lib/system-security-upgrader/failure-evaluator
    chown root:root /usr/local/lib/system-security-upgrader/state-manager
    chown "$user":"$user" /usr/local/lib/system-security-upgrader/ai-summarizer
    chown root:root /usr/local/lib/system-security-upgrader/read-state

    # set permissions
    chmod 750 /usr/local/sbin/security-check
    chmod 750 /usr/local/sbin/user-upgrade

    chmod 750 /usr/local/lib/system-security-upgrader/upgrade
    chmod 750 /usr/local/lib/system-security-upgrader/failure-evaluator
    chmod 750 /usr/local/lib/system-security-upgrader/state-manager
    chmod 750 /usr/local/lib/system-security-upgrader/ai-summarizer
    chmod 750 /usr/local/lib/system-security-upgrader/read-state
    # set up daemon

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

    # check if the installation went successfull
    post_install

    echo "System security upgrader has been installed successfully!"
}

# call main with all args, as given
main "$@"
