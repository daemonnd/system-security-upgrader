# Upgrade Domain

## What Is This Domain?

**One sentence:** Executed manually by the root user, it updates the mirrorlists, performs a full system upgrade and asks the user to reboot the system when done.

**Runs as:** root user
**When:** Manually, when user runs `sudo upgrade`, or via script mode (coming soon)
**Duration:** ~1 minute or less with good internet connection, depends on upgrade size
**Input:** 
**Output:** logfiles for each tool (`/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_upgrade/tool.log`), owned by root, logs about the `upgrade.sh` script to stdout and trigger file for the 2nd phase (security check) at `/var/lib/system-security-upgrader/pending-check` owned by root.
**Files:**`upgrade.sh`

---

## The Job (Step by Step)

1. Check if the root user is actually running the script
2. Saving the `$SUDO_USER` for later
3. Generate logdir path
4. Create dirs for logging, and triggering phase 2 (security checks)
5. Updating the mirrorlists using reflector
6. Upgrade the system
7. Ask the user if the system should reboot
8. Create trigger file for phase 2 (security checks)

---

## Inputs & Outputs

**What it reads:**
- System package database (via pacman, not a file)
- Current `/etc/pacman.d/mirrorlist` (will be replaced)

**What it creates:**
- `/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_upgrade/reflector.log` logs created by reflector while updating the mirrorlists, owned by root.
- `/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_upgrade/pacman.log` logs created by pacman while upgrading the system, owned by root.
- `STDOUT` what the script is currently doing
- new `/etc/pacman.d/mirrorlist` by reflector (no backup of the old one)
- `/var/lib/system-security-upgrader/pending-check` trigger file for phase 2 (security check, contains username), owned by root.

---

## What It Doesn't Do

- It does not check if the internet works, because it would give the script complexity that is not neccessary 

---

## Design Philosophy

- **Why reflector?** Reflector gives the user more choice to select the mirrorlists compared to other tools for ranking the mirrors.
- **Why ask before reboot?** Rebooting just after upgrade finish is not user friendly and it creates an opportunity for the user to save his work. With a script mode, the user can decide wether to reboot directly after updates or not
- **Why fail fast?** If mirrors upgrade fail, continuing is dangerous and slower. Because of this, the script stops immediately and lets the user see the error


---
