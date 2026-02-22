# 📌 System Security Upgrader — Architecture Documentation

### The Real-World Problem
Having a secure up-to-date system is very important in the time of Hackers. But manually upgrading the system and checking the security of the system can be very painful:
- it takes time
- it can be complex when using a lot of security checking tools
- when it is complex, it can easily happen to forget steps
- when having multiple servers, it becomes even more difficult: more time consumption
That's why this project has been developped: Automating this workflow, and summarizing the security Warnings/Suggestions for more convienience for people that don't want to do it or don't have the time for doing it.
That is a workflow great for automation with bash, because it is repetitive and takes a lot of time to run several security tools. With this project:
- After upgrades & reboot, the security tools run in the background
- everything gets logged & full control because daemons handle the execution phases
- After the security checks are done, the ai summarizes the downfiltered security logs using specialized system prompts for more user convenience (optional)

### Who It's Built For
- **Primary**: DevOps engineers managing 10+ Arch Systems
- **Secondary**: Power user with 1-2 personal systems
- **Future**: Ubuntu/Debian users (once support is added)


### Why It Exists (The Philosophy)
- To automate upgrading the system & security checks, then summarizing it
- strict mode: If something fails, the rest won't continue
- everything is logged for debugging when an error occurs (check debugging part in project README.md)
- having permanent security records of the system
- It relies heavily on systemd, without systemd the scripts have to be executed manualy
- It does not deliver the ai summary to the user

---

## Navigation by Role

### I want to understand **why decisions were made**:
Discover all the relevant decisions here:
`architechture/decisions/`

### I want to understand **how this tool works**
Check the `README.md` files of each domain: # TODO
`architecture/domains/`
	`upgrade/README.md`
	`security_audit/README.md`
	`summarization/README.md`
	`state_management/`
		`README.md`
		`ARCHITECTURE.md`

### I want to **debug an error**
1. Check out `architecture/domains/upgrade/ARCHITECURE.md` # TODO
**Think about this scenario:**

> "Phase 2 ran, but Phase 3 never started. Where do I look first?"

Where **should** someone look? (HANDOFF_FILES.md? SYSTEMD.md? CONSTRAINTS.md?)
### I want to **debug when something breaks**:
1. Check `domains/state_management/HANDOFF_FILES.md` (what state should exist?)
2. Check `domains/state_management/SYSTEMD.md` (did the daemon trigger?)
3. Check relevant domain's `ARCHITECTURE.md` (phase-specific control flow)
Check out the `CONSTRAINTS.md` files for each domain:
`architecture/domains/`
	`uprade/CONSTRAINTS.md`
	`security_audit/CONSTRAINTS.md
	`state_management/HANDOFF_FILES.md
	`summarization/CONSTRAINTS.md`
	`state_management/`
		`CONSTRAINTS.md`
		`HANDOFF_FILES.md`


---

## Project Status

| Feature            | Status                                             |
| ------------------ | -------------------------------------------------- |
| Upgrade the system | stable/done                                        |
| Run security tools | 2 out of 3 stable/done, one not implemented at all |
| Daemons            | stable/done                                        |
| Handoff files      | stable/done                                        |
| Ai summarization   | unstable/not tested enough                         |


---

## Quick Facts

| Decision                               | why?                                                                                            |
| -------------------------------------- | ----------------------------------------------------------------------------------------------- |
| systemd instead of cron                | more control needed for when to run phase 2 & 3, more stable, many systems use systemd          |
| 3 phases (upgrade, security check, ai) | upgrade & security have to be sepeated (reboot), ai is optional                                 |
| handoff files                          | survive reboot, data flow between phases, ConditionPathExist files (daemon -> phase triggering) |
