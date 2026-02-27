## Execution Flow
sudo upgrade
set up strict mode (Eeuo pipefail) and trapp ERR

### init()

check if root is running the script
	|-> if no: output error, exit the script
	|-> if yes: continue
check if the $SUDO_USER has a home dir
	|-> if no: output error, exit the script
	|-> if yes: continue and save the username
create logpattern and logdir based on the current time and date
create the logdir and its parent dir (if nonexistent)
create a dir for holding the ai summaries and trigger/handoff files

### update_mirrorlists()
generate reflector logfile path (based on logdir)
run_cmd with the description (Updating the mirrorlists) logfile and reflector command (reflector --latest 20 --country Germany,Netherlands,Belgium  --sort rate --save /etc/pacman.d/mirrorlist ):

### run_cmd()
save logfile & description as local vars
execute the command given
	|-> on failure: capture exit code, output error and exit with the same exit code than the program that failed
	|-> on success: output that the command ran is done

### upgrade_system()
generate pacman logfile path (based on logdir)
run_cmd with the description (Upgrading the system) logfile of pacman, and pacman command (pacman -Syu) 

outputting the time (how many seconds the script took)
outputting the path of the logdir to check logs

### end_script()
ask the user wether to reboot now or run phase 2 on the next reboot
	|-> if y (yes): create trigger file for phase to (pending-check) with the username as content, and reboot, therefore the script will exit with 0
	|-> if n (no): create trigger file for phase 2 (pending-check) with the username as content, output that the security tools will run on next boot, the script exits with 0
	|-> if invalid input: present options to the user (y/n) and re-prompt



---

## State Created
### Timeline:
1.  (init): Creates /var/log/system-security-upgrader/ (owner: root, does not get deleted)
2. (init): Creates /var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_upgrade/ (owner: root, does not get deleted)
3.  (init): Creates /var/lib/system-security-upgrader/ (owner: root, does not get deleted)
4.  (update_mirrorlists -> run_cmd) /var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_upgrade/reflector.log (owner: root, does not get deleted)
5.  (upgrade_system -> run_cmd) /var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_upgrade/pacman.log (owner: root, does not get deleted)
6.  (end_script) /var/lib/system-security-upgrader/pending-check (owner: root, does get deleted after the `security-check.sh` script ran)

### Final directory tree (on success):
/var/log/system-security-upgrader/YYYY-mm-dd_HH-MM-SS_upgrade/
	reflector.log
	pacman.log
/var/lib/system-security-upgrader/pending-check

---

## Function Breakdown

**What goes here:**
For each major function in your script, document:
- What it does (one sentence)
- What it checks/validates before doing anything
- What it creates/modifies
- What happens if it fails
- Exit behavior (does it continue or exit script?)

**Why it matters:** Someone debugging a specific phase needs to know: "What does this function assume is true? What does it guarantee?"

### init()
**Purpose**: Check user, prepare things for the next functions 

**Validates before executing:**
- User: is root running the scrip? if no -> exit
- SUDO_USER: Does the sudo_user have a home dir? if no -> exit

**Creates/modifies:**
- Creates a logdir
- Creates dir for trigger file later
- Creates logfiles from the tools used (reflector & pacman)

**Failure cases:**
- Invalid user running the scrip -> outputs error, exit 1
- SUDO_USER does not have a home dir -> outputs error and possible solutions, exit 1

**Exit behavior:**
- Everything succeeds, no errors -> exit 0
- Permission error (Invalid user running the script) or SUDO_USER does not have a home dir -> exit 1
- Error while running reflector or pacman -> exit exit code of the tool with the error (if reflector exits with 2, it will exit with 2 too)

**Example from unrelated project (database migration script):**
```
### migrate_schema()
**Purpose:** Apply pending SQL migrations in order

**Validates before executing:**
- Database connection is active (test with SELECT 1)
- Migration directory exists and is readable
- Database has migrations_applied table (create if missing)

**Creates/modifies:**
- Runs each .sql file in migrations/ directory
- Inserts record in migrations_applied (file_name, applied_at)
- Creates new tables/indexes/columns in database

**Failure cases:**
- SQL syntax error → transaction rolls back, log error, continue to next migration
- File not found → log error, skip file, continue
- Duplicate migration name → log error, exit 1 (fatal)

**Exit behavior:**
- All migrations succeed → exit 0
- Some succeed, some fail → exit 1 (state is inconsistent)
```

**Your task:** For each function in `upgrade.sh` (init, update_mirrorlists, upgrade_system, end_script):
- What does it validate?
- What does it create?
- What failures can happen?
- Does it exit the script or continue?

---

## Error Handling Strategy

**What goes here:**
Explain the **mechanism** for catching and handling errors. Not specific errors, but the overall pattern.

**Why it matters:** If something breaks, understanding the error-handling pattern tells you: "Is this expected? Will it retry? Will it exit?"

**Example from unrelated project (background job processor):**
```
**Mechanism:** try/except + custom retry decorator + dead-letter queue

Pattern:
1. Job pulled from queue
2. Try to execute job function
3. If success → mark job complete, remove from queue
4. If exception:
   - Catch exception type
   - If retryable (network, timeout) → increment retry count, re-queue
   - If not retryable (code error) → move to dead-letter queue, log full error
5. After 3 retries → move to dead-letter queue regardless

**Special cases:**
- Timeout exception → retry immediately (connection may recover)
- Permission error → don't retry (will always fail), move to dead-letter
- Database error → retry with exponential backoff (database may recover)
```

**Your task:** Explain how `upgrade.sh` handles errors:
- What mechanism? (set -e? trap? explicit checks with run_cmd()?)
- What happens on reflector failure?
- What happens on pacman failure?
- Are there special cases? (e.g., rkhunter exit code 1 = warning, not error)
- Can it recover or does it always exit?

---

## What Changes If...

**What goes here:**
Answer 3 realistic "what if someone extends this?" scenarios. Show:
- What code changes
- What files are affected
- What new dependencies
- What testing needed

**Why it matters:** Shows you understand the design boundaries. "If I wanted to add feature X, here's what would break."

**Example from unrelated project (API gateway):**
```
**...you add request rate limiting?**
- Add middleware function: check_rate_limit(user_id, endpoint)
- Add Redis dependency (for counting requests)
- Add config: rate_limits.yaml (limits per user/endpoint)
- Modify: request handler to call middleware before processing
- Test: exceed limit, verify 429 response

**...you switch from Redis to in-memory cache?**
- Remove: Redis client initialization
- Add: in-memory dict + TTL cleanup thread
- Modify: check_rate_limit() to use dict instead of Redis
- Risk: loses rate limits across service restart (acceptable?)

**...you want to scale to multiple servers?**
- Remove: in-memory cache (doesn't sync across servers)
- Add: Redis (or distributed cache)
- Add: network latency (cache lookups now slower)
- Test: verify limits work correctly across 3+ servers
```

**Your task:** For `upgrade.sh`, answer:
- What if you add Debian/Ubuntu support?
- What if mirrors are slow and you need faster selection?
- What if you want automatic reboot (no user prompt)?

---

## Dependencies

- bash 5.3.9+ 
- systemd & systemctl 259
- file permissions
- pacman 7.1.0+ 
- reflector
- basic gnu bash commands (date, echo, exit)

---
