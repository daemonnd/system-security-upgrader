# State Management Domain

## What Is This Domain?

**One sentence:** It provides daemons that are executed when the handoff/trigger files exist, the phases can communicate and start properly.
**Runs as:** Root (systemd daemons)
**When:** Always, triggered by systemd checking for trigger files
**Duration:** none, the daemons are always enabled
**Input:** systemd daemon infrastructure, filesystem that supports file ownerships, at lease one user with homedir, trigger file created by phase 1
**Output:** systemd services for orchestration, permission/ownership model
**Files:** `security-upgrader.service`, `security-summarizer.service`, `/var/lib/system-security-upgrader/pending-check`, `/var/lib/system-security-upgrader/pending-ai-summary`

---

## The Job (Step by Step)

[This is different. Instead of execution steps, describe the **lifecycle** of data flow. How does a trigger file move from phase to phase? What happens at each transition?]
1. Phase 1 (upgrading the system) creates a file at `/var/lib/system-security-upgrader/pending-check` with the username for phase 2.
2. The system gets rebooted
3. Only if the trigger file exists, phase 2 starts running in the background
4. Because the trigger file `pending-check` exists, the 2nd phase get executed in the background
5. After the security checks ran, `pending-check` gets removed
6. Phase 2 create at the end a new trigger file, at `/var/lib/system-security-upgrader/pending-ai-summary`, containing the username (from phase 1, for phase 3), the logdir & the timestamp of phase 2 for phase 2
7. After that, phase 2 changes the ownership of `pending-ai-summary` to the user from phase 1 and modifies the permissions of that trigger file, so that phase 3 can remove it without permission error later.
8. Only if the trigger file `/var/lib/system-security-upgrader/pending-ai-summary` exists, the 3rd phase start running in the background immediately after phase 2.
9. At the end of phase 3, the trigger file `/var/lib/system-security-upgrader/pending-ai-summary` gets removed to avoid using the ai twice for the same thing.

---

## Inputs & Outputs

**What it reads:** 
- Systemd daemon infrastructure (systemd-run, systemctl, ConditionPathExists)
- Filesystem that supports file ownership changes (ext4, btrfs, etc.)
- Valid users on system with homedir (for ownership changes and Phase 3 execution)
- Phase 1 creates first trigger file (provides data to start the chain)

**What it creates:**
- Two systemd services (`security-upgrader.service`, `security-summarizer.service`) that watch for trigger files and execute phases
- Trigger file format specification (what content phases should write)
- Permission/ownership model (how files move between root and user)

---

## What It Doesn't Do

- Does NOT execute any security tools (that's domain's job) — Why? Separation of concerns
- Does NOT decide when to trigger phases (systemd decides) — Why? Event-driven, not scripted
- Does NOT deliver summaries to user (that's user's job) — Why? Notification is user's choice

---

## Design Philosophy

- **Why trigger files, not env vars?** Trigger files survive reboot, they can be used with `ConditionPathExists` in a daemon and contain the needed data for the next phase. They can also be created & modified for testing and read for debugging
- **Why systemd, not cron?** The phases integrate with boot and order, not with scheduling.

- **Why ownership changes (root → user)?** [Explain: Phase 2 runs as root (needs access), but Phase 3 runs as user (shouldn't need root), logs should be readable by user who triggered it]