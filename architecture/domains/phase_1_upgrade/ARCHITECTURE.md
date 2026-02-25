## Execution Flow

**What goes here:**
Document the **actual step-by-step execution** of the script. Not pseudocode, but the real control flow. Include both success and failure paths. Show where functions call each other, where it exits, where it loops. This is "if I trace through the code with a debugger, what happens?"

**Why it matters:** Someone debugging needs to understand: "At what point does it fail? What state exists when it fails?"

**Example from unrelated project (Kubernetes controller):**
```
controller starts
  ↓
watch for ConfigMap changes
  ├─ If ConfigMap invalid → log error, continue watching
  ├─ If ConfigMap valid → trigger reconciliation
  └─ If watch connection lost → reconnect (exponential backoff)
  ↓
reconcile() called
  ├─ Get current state from API
  ├─ Compare desired vs actual
  ├─ If differ → apply patch
  │   ├─ If patch succeeds → update status
  │   ├─ If patch fails → retry 3x, then backoff
  │   └─ If all retries fail → mark as error, continue
  └─ If match → do nothing
```

**Your task:** Trace through `upgrade.sh` and show:
- Each function call in order
- What happens if it succeeds
- What happens if it fails (which functions skip, which exit)
- Where the user makes decisions (reboot prompt)
- What state exists at each point

---

## State Created

**What goes here:**
Show two things: (1) **Timeline** — when each file/directory is created, by which function, (2) **Final tree** — what the directory structure looks like after the script finishes.

**Why it matters:** Understanding when files are created helps with debugging. "Did this file get created? When? By which step?" If something goes wrong at step 5, what should exist at that point?

**Example from unrelated project (CI/CD pipeline):**
```
Timeline:
├─ Step 1 (checkout): Creates /workspace/repo/ (owner: ci-user)
├─ Step 2 (build): Creates /workspace/build/ (owner: ci-user)
│   └─ /workspace/build/artifacts/ (owner: ci-user)
├─ Step 3 (test): Creates /workspace/test-results/ (owner: ci-user)
│   └─ If test fails → file exists but marked FAILED
└─ Step 4 (publish): Creates /repo/releases/v1.0/ (owner: release-user)
    └─ If publish fails → directory doesn't exist yet

Final directory tree (on success):
/workspace/
├── repo/
├── build/
│   └── artifacts/
└── test-results/
/repo/
└── releases/
    └── v1.0/
```

**Your task:** Show:
- **Timeline:** Which function creates which file? In what order?
- **Final tree:** All directories + log files created by `upgrade.sh`
- **Ownership:** Who owns each file at creation? Any ownership changes?
- **Lifetime:** When is each file deleted or persists?

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

**What goes here:**
List what must exist for this domain to work. Not just packages, but also:
- System requirements (bash version, systemd available?)
- File permissions needed
- External services/tools

**Why it matters:** Someone deploying needs to know: "What do I need to install? What permissions? What will break if X isn't available?"

**Example from unrelated project (backup system):**
```
- bash 4+ (for associative arrays)
- rsync 3.1+ (for incremental backups, Arch: pacman -S rsync)
- ssh configured (public keys in ~/.ssh/authorized_keys)
- Target disk with 2x source size available (for backups)
- cron or systemd timer (for scheduling)
- Write permission to /var/backups/ (where backups stored)
```

**Your task:** List:
- Bash version needed?
- reflector (how to install on Arch?)
- pacman (built-in?)
- systemctl command (requires systemd?)
- File/directory permissions needed?

---

**When done, paste your filled ARCHITECTURE.md here.**

Then we do the same for `security_audit/` and `summarization/`.