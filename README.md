# Project Overview

Semi-automated Arch Linux system upgrade followed by security auditing, with clear separation of concerns, reliable hand-off points, and fully offline AI summarization support.

# Contents

- [Features](#features)
- [Motivations](#motivations)
- [Structure](#structure)
- [Dependencies](#dependencies)
- [Installation](#installation)
- [Usage](#usage)
- [Logging](#logging)
- [Troubleshooting](#troubleshooting)
- [Future improvements](#future-improvements)
- [Author Info](#author-info)
- [License](#license)

---

# Features

- Automated mirror updates with reflector
- Full system upgrade with pacman
- Post-reboot security checks (lynis, rkhunter)
- AI-powered summary generation of security tool outputs (optional)
- Updating of user packages from yay and flatpak (done manually)
- dashboard file for a quick view of how the updates went and the security is doing

---

# Motivations

- learn systemd and daemons better
- automate security checks and upgrade
- try to really finish a project

---

# Structure

## Logs /var/log/system-security-upgrader/ log files of used tools

- `YYYY-mm-dd_HH-MM-SS_upgrade/` log files of system upgrades
- `YYYY-mm-dd_HH-MM-SS_security-check/` log files of security check tools
- `YYYY-mm-dd_HH-MM-SS_user-maintenance/` log files of user package upgrade tools

## Variable State Information /var/lib/system-security-upgrader/

- `dashboard.md` dashboard file
- `sys-upgrade.state` state of latest system upgrade
- `security-check.state` state of latest security check
- `user-maintenance.state` state of latest user package upgrade
- (after sys upgrade) `pending-check` condition path for security-upgrader.service
- (after security check) `pending-ai-summary` condition path for security-summarizer.service
- `summaries/` directory for all AI summaries
  - `user/` username of user owning the summaries
    - `YYYY-mm-dd_HH-MM-SS_ai-summary.md` AI summaries of security tools

## Executables /usr/local/sbin/

- `user-upgrade` for manually running the user package updates
- `security-check` for manually running the security tools

## Helper Scripts /usr/local/lib/system-security-upgrader/

- `ai-summarizer` AI summarizer of security tool logs
- `dashboard-builder` for rebuilding the dashboard
- `failure-evaluator` for evaluating the failure of used tools
- `read-state` for reading the state files and display in logs
- `state-lib` for validating the state files and set vars used in read-state and dashboard-builder
- `state-manager` for writing to state files and updating them - upgrade for upgrading the system
- `user-maintenance` for upgrading the user packages

---

# Dependencies

- Arch-system
- reflector # for updating the mirrorlists
- lynis # for security checking
- [fabric](https://github.com/danielmiessler/Fabric) + AI model (ollama, openai, anthropic, ...) # for ai summary
- bash # script interpreter
- systemd # for daemons and reboot
- rkhunter # for rootkit checking

---

# Installation ## One-line install

```bash
curl -fsSL <https://raw.githubusercontent.com/daemonnd/system-security-upgrader/main/install.sh> "$USER" | sudo bash
```

## Manual installation

```bash
git clone "<https://github.com/daemonnd/system-security-upgrader.git>" system-security-upgrader
cd system-security-upgrader/
sudo ./install.sh user local # for not cloning the repo
```

# Logging

Main Logfile: `/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_script/tool.log`
Note: The dirname YYYY-mm-dd_HH-MM-SS is named by the time the script STARTED.
Inside the logfile, the timestamps are just after it actually happened.
Inside logfile structure: YYYY-mm-dd_HH-MM-SS - LOGLEVEL: message ## Logs of the tools (reflector, pacman, lynis)

```bash
cat /var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_upgrade/*# logs from the upgrade script
cat /var/log/system.security-upgrader/YYYY-mm-dd_HH-MM-SS_security-check/* # logs from the security check script
The logs of user-upgrade go to stdout. ## Logs of the services
bash
journalctl -u sys-upgrade.timer # for the system upgrade timer
journalctl -u sys-upgrade.service # for the system upgrade
journalctl -u security-upgrader.service # for the system upgrade dashboard writing and the security tools
journalctl -u security-summarizer.service # for the ai summarizer
```

# Usage

```bash
user-upgrade
```

This will make the user package upgrade run. Everything else is executed automatically

---

# Troubleshooting

## Common errors

- Invalid user: run install.sh <username> # local # (if you don't want to clone the repo) The username appended needs a home directory under /home/
- Permission denied: use sudo for upgrade script and check the file permissions that should be 755.
- Command not found: check $PATH and shebang in the scripts
- AI summary fails: check model availability, test the model manually, for this script a default configured model is required in fabric, finish fabric --setup

## Test without reboot

### System Upgrade

This shows how to test the sys upgrade + security tool run + AI summary generation

1. Upgrade the system manually with systemctl start sys-upgrade.service
2. Run the security tools with security-check (that does NOT immediately update the dashboard file, it will get updated after the AI summary, to do that run systemctl start security-upgrader.service)
3. Run AI summary with systemctl start security-summarizer.service
4. See the state with `cat /var/lib/system-security-upgrader/dashboard.md`

### User Upgrade

This shows how to test the user upgrade

1. Update the user packages with user-upgrade
2. See the state with cat /var/lib/system-security-upgrader/dashboard.md

---

# Limitations

- cannot detect stuck-but-running processes
- user package updates are done manually because yay is an interactive tool

---

# Future improvements

- do not create trigger file for securit-check.sh, if pacman did not upgraded anything
- country selection for reflector
- email notifications
- dry-run mode
- add non-interactive mode
- remove orphanage packages
- check ufw status
- add systemctl --failed to security-check.sh
- add analyze journalctl/system logs to ai input to not only spot security vulnerabilities but also find errors
- check if the internet connection works
- let the security script create a pkglist
- send message to user (telegram or email) with the ai summary
- add json config
- add log cleanup

---

# Author Info

- username: daemonnd
- email: find at github profile

---

# License MIT

