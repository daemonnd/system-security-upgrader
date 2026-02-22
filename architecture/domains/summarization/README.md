## What Is This Domain?

**One sentence:** Executed by a daemon trigger file, it summarizes the security logs created in phase 2 (security checks) for user convenience
**Runs as:** The user set when starting with the first phase (system upgrade), not the root user
**When:** AFTER the `security-check.sh` script is DONE and have generated all the neccessary logfiles.
**Duration:** Depends on non-uniq logsize and mainly on the ai model. When using a decent model (ollama) on decent hardware: ~20-25min.
**Input:** A valid triggerfile at `/var/lib/system-security-upgrader/pending-ai-summary` containing a valid username, logdir and timestamp, have to be owned by the user, not root, logfiles from the security tools at `/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_security-check/tool.log`
**Output:** Ai summary of the logs, at `/var/lib/system-security-upgrader/summaries/<username>/YYYY-mm-dd_HH-MM-SS_ai-summary.md`
[What file is created? Where? What's in it? Who owns it? What format? Example: "Creates markdown summary at /path/summaries/USERNAME/TIMESTAMP_summary.md (owner: USERNAME, human-readable findings)"]
**Files:** `security-summarizer.service`, `ai-summarizer.sh`

---

## The Job (Step by Step)

1. Check if the trigger/handoff file (`/var/lib/system-security-upgrader/pending-ai-summary`) exists & check its contents
2. Save the data from the trigger/handoff file to variables in the script
3. Filter the logfile of lynis down to warnings & suggestions and uniq the contents
4. Feed  the filtered content into the ai using fabric
5. Append the summary to the summaryfile.
6. Repeat for rkhunter: Filter the logfile of rkhunter down to warnings and uniq the contents, then feed the filtered content into the ai using fabric, append the summary to the summaryfile
7. Repeat for arch-audit: Filter the logfile of arch-audit down to warnings and uniq the contents, then feed the filtered content into the ai using fabric, append the summary to the summaryfile (coming soon)
8. Removing `/var/lib/system-security-upgrader/pending-ai-summary` to avoid running the ai when it is not neccessary. 

---

## Inputs & Outputs

**What it reads:**
- `/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_security-check/rkhunter.log` containing the logs created by rkhunter
- `/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_security-check/lynis.log` contains the logs created by lynis
- `/var/lib/system-security-upgrader/pending-ai-summary` The trigger/handoff file containing the username, the logdir from phase 2 (security check) and the timestamp of that logdir

**What it creates:**
- `/var/lib/system-security-upgrader/summaries/<username>/YYYY-mm-dd_HH-MM-SS_ai-summary.md` the ai summary of the security logs, owned by user
- logs recorded by journalctl

---

## What It Doesn't Do

- It doesn't send a message to the user, because there are practiacally unlimited options for doing that: email, notification, telegramm, slack, etc.. That would add too much noise into this script.

---

## Design Philosophy

**Why optional?** Because there are many users that don't have fabric and/or and api key and/or enough good hardware for ollama models. By making it optional, it avoide unneccessary errors caused when I would not be optional.
- **why filtering the logs before passing them to ai?** Especially on ollama models, then context length is not very high. By only keeping the relevant things for the ai (only warnings & no double lines), we get the same results with less content, because any ai halluciantes with too much content 

---
