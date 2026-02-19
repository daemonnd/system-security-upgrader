# Project Overview
This project was designed to perform a full system upgrade on an arch or arch-based system. After the system upgrade, it reboots and does security checks with rkhunter, lynis, and arch-audit, then summarizes results with local ollama AI.

# Motivations
- learn systemd and daemons better
- automate security checks and upgrade

# Structure
`~/scripts/system-security-upgrader/` development dir
	`README.md` docs
	`upgrade.sh` update mirrorlist with reflector, upgrade system & reboot
	`security-check.sh` check system security, summarize with ai
	`install.sh` installation script
`/var/log/system-security-upgrader/` log files
`/usr/local/sbin/upgrade` deployment of `~/scripts/system-security-upgrader/upgrade.sh` 
`/usr/local/sbin/security-check` deployment of `~/scripts/system-security-upgrader/security-check.sh`

# Dependencies
- Arch-system 
- reflector # for updating the mirrorlists
- lynis # for security checking 
- ollama + local ai model # for ai summary
- bash # script interpreter
- arch-audit # for arch audit
- ufw # for checking the status of the firewall
- systemd # for daemons and reboot
- rkhunter # for rootkit checking
- notifications with notify-send # for user interaction (such as asking the user if the computer should reboot)
- curl # for checking if the internet is working (optional)


# Phase 1: Upgrade & Reboot
This script is there to perform system upgrades and reboot the system after they are done. 

Main Logfile: `/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS/upgrade.log`
Note: The dirname YYYY-mm-dd_HH-MM-SS is named by the time the script STARTED.
Inside the logfile, the timestamps are just after it actually happened.
Inside logfile structure:
`YYYY-mm-dd_HH-MM-SS - LOGLEVEL: message` 

The logs of the tools (reflector, pacman, systemd) are written in their own logfiles
(`/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS/tool.log` )


Deployment path:
`/usr/local/sbin/upgrade`

What it does:
1. Check if root is running it
2. Check if the internet works
3. run reflector to get the latest mirrorlists and perform the upgrade faster
4. upgrade the system
5. if the upgrade finished without errors, ask user via read  to reboot now and then reboot, if not, the script exits with exit code 0 and on the next reboot the security checks will be performed.

# Phase 2: security check
This script is there to run security tools, write security logs which will be analyzed by local ai.
It will be executed by the root user because the security tools need root privileges.

Main Logfile: `/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS/security-check.log`
Note: The dirname YYYY-mm-dd_HH-MM-SS is named by the time the script STARTED.
Inside the logfile, the timestamps are just after it actually happened.
Inside logfile structure:
`YYYY-mm-dd_HH-MM-SS - LOGLEVEL: message` 

The logs of the tools (lynis, rkhunter, arch-audit, systemd, ...) are written in their own logfiles
(`/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS/tool.log` )
Deployment path:
`/usr/local/sbin/security-check`

Daemon path:
`/etc/systemd/system/security-upgrader.service`

The ai summary is stored at `~/Documents/system-security-upgrader/summary-YYYY-MM-DD.md`

What it does:
1. Run security tools (lynis, rkhunter, archaudit) and write the stdout and stderr into a logfile for each tool
2. Feed the output of these security tools into local ai to generate a summary

# Installation
## quick installation
1. `cd` into the project dir
2. run  the following:
```bash
chmod +x install.sh
sudo ./install.sh
```

## manual installation
1. Copy scripts to /usr/local/sbin/ 
2. Set owner as root and permissions to 755 to the scripts 
3. Copy `security-upgrader.service` to  `/etc/systemd/system/security-upgrader.service` to set up the daemon
4. Reload the daemons with `sudo systemctl daemon-reload`
```bash
# cd into the project dir
# copy scripts
sudo cp upgrade.sh /usr/local/sbin/upgrade
sudo cp security-check.sh /usr/local/sbin/security-check

# set permissions
sudo chmod +x /usr/local/sbin/upgrade
sudo chmod +x /usr/local/sbin/security-check
# change owner to root for the scripts
sudo chown root:root /usr/local/sbin/upgrade
sudo chown root:root /usr/local/sbin/security-check

# set up daemon
sudo cp security-upgrader.service /etc/systemd/system/security-upgrader.service

# reload daemons
sudo systemctl daemon-reload 
```
# Usage
```bash
sudo upgrade
```
This will execute the upgrade script which will cause the reboot. After the reboot, the second script is executed automatically.

How to inspect logs:
```bash
cat /var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_upgrade/* # logs from the upgrade script
cat /var/log/system.security-upgrader/YYYY-mm-dd_HH-MM-SS_security-check/* # logs from the security check script
journalctl -u security-upgrader.service
```

# Logging
Main Logfile: `/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_script/script.log`
Note: The dirname YYYY-mm-dd_HH-MM-SS is named by the time the script STARTED.
Inside the logfile, the timestamps are just after it actually happened.
Inside logfile structure:
`YYYY-mm-dd_HH-MM-SS - LOGLEVEL: message` 

The logs of the tools (reflector, pacman, systemd, ...) are written in their own logfiles
(`/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS/tool.log` )

# Troubleshooting
## Common errors:
- Permission denied: use sudo for upgrade script and check the file permissions that should be 755.
- Command not found: check `$PATH` and shebang in the scripts
- AI summary fails: check model availability, test the model manually

## Test without reboot:
1. Run upgrade script (`upgrade`)
2. When the read prompt appears, type `n`.
3. Run `sudo security-check` in the terminal to perform the security checks.

# Future improvements
- email notifications
- dry-run mode
- add non-interactive mode
- remove orphanage packages
- check ufw status
- add systemctl --failed to security-check.sh
- add analyze journalctl/system logs to ai input to not only spot security vulnerabilities but also find errors
- check if the internet connection works
- let the security script create a pkglist
- add notify-send to ask for reboot and other things, read prompt only as alternative
# Author Info
- username: daemonnd
- email: find at github profile

# MIT License

Copyright (c) 2012-2024 Scott Chacon and others

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 
