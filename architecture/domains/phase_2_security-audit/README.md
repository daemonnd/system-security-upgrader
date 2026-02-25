# Security Audit Domain

## What Is This Domain?

**One sentence:** Executed by a trigger file after reboot, it performs security checks in the background by running security tools that are logged in specific logdirs for that.
**Runs as:** root, because security tools need deep system access and the logdirs are owned by root.
**When:** Automatically after a successful system upgrade AND reboot AND daemon `security-upgrader.service` is enabled
**Duration:** Depends on how many packages installed and the number of tools. With lynis & rkhunter: ~70-80 seconds
**Input:** A valid triggerfile at `/var/lib/system-security-upgrader/pending-check` containing a valid username that has a home dir.
**Output:** logfiles for each tool at `/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_security-check/tool.log` owned by the user from phase 1 (updating the system), logs about `security-check.sh` to stdout and a trigger/handoff file for the 3rd phase (ai summarization) containing the username from befor, the logdir of `security-check.sh` and the timestamp of this logdir. It is owned by the user. The ownerships are st at the end of `security-check.sh`.
**Files:** `security-upgrader.service`, `security-check.sh`

---

## The Job (Step by Step)

1. Check if the root user is actually running the script
2. Check if the trigger/handoff file exists & check its contents
3. Create logdirs with timestamps, dirs for ai summary later, and changing the ownership of these dirs to the user.
4. Audit the system using lynis
5. Upgrade rkhunter & check for possible rootkits using rkhunter
6. Check for vulnerabilities on the system using arch-audit (coming soon)
7. Remove the trigger file `/var/lib/system-security-upgrader/pending-check` to make sure that this script won't rerun on next boot.

---

## Inputs & Outputs

**What it reads:** 
- Its trigger/handoff file at `/var/lib/system-security-upgrader/pending-check` containing the username

**What it creates:**
- `/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_security-check/rkhunter_update.log` logs created when updating rkhunter, owned by user
- `/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_security-check/rkhunter_propupd.log` logs created when updating the rkhunter file prosperties, owned by user
- `/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_security-check/rkhunter.log` logs created when running rkhunter on the system (warnings only), owned by user
- `/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_security-check/lynis.log` logs created when auditing the system with lynis, owned by user
- `STDOUT` what the script is currently doing
- `/var/lib/system-security-upgrader/pending-ai-summary` trigger/handoff file for the 3rd phase (ai summarization) containing username, logdir (`/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS/`) and timestamp of the logdir (`YYYY-mm-dd_HH-MM-SS`), owned by user
- logs recorded by journalctl
Note:
The ownership of all the output files are marked as owned by the user that will own the ai summary. But this happens at the **end** of `security-check.sh`, which means that the root user owns all the files at creation time.

---

## What It Doesn't Do

- It does not fix the security issues automatically, because this choice and action is for admins
- It does not alert the user when it is don, because this is user choice and it has still to be summarized

---

## Design Philosophy

- **Why trigger/handoff files?** The trigger/handoff files work great with daemond when using `CondtionPathExists`, the contain metadata as transition between the phases and survive reboot
- **Why removing the .../pending-check triggerfile?** Without removing it, the `security-check.sh` script would run on every boot, consuming unneccessary performance and causing the 3rd phase to summarize the logs, which can cause higher cost when using an api key for ai or consume a lot of performance for something unneccessary when using ollama.