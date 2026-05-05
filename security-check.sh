#!/bin/bash

# strict mode
set -euo pipefail

# trap errors
trap 'echo "Error on line $LINENO: command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

function check_args {
    :
}

function init {
    # checking if the root user is actually running the script
    if [[ "$EUID" -ne 0 ]]; then
        echo "Permission Error: This script needs root privileges or sudo." # logging does not work at this point
        exit 1
    fi

    # check if the trigger file exists
    if [[ ! -r /var/lib/system-security-upgrader/pending-check ]]; then
        echo "Trigger file at '/var/lib/system-security-upgrader/pending-check' does not exist, therefore this script can't be executed properly."
        exit 1
    fi
    # check if the content of the triggerfile is valid
    user="$(cat /var/lib/system-security-upgrader/pending-check)"
    if [[ -z "$user" ]]; then
        echo "FATAL: User is not in security checks triggerfile, aborting"
        exit 1
    fi
    if [[ -d "/home/${user}" ]]; then
        echo "Trigger file contains a valid username where the user have a home dir: ${user@Q}"
    else
        echo "Invalid username in security-upgrader.service trigger file: '/var/lib/system-security-upgrader/pending-check': $(cat /var/lib/system-security-upgrader/pending-check)"
        exit 1
    fi

    # DEBUG
    echo "DEBUG: User: $user"

    # initialize variables
    export overall_failure=0 # flag to indicate if any of the checks failed
    export STATE_FILE="/var/lib/system-security-upgrader/security-check.state"
    export STATE_DIR="/var/lib/system-security-upgrader/"
    logpattern=$(date "+%Y-%m-%d_%H-%M-%S")
    export LOG_DIR="/var/log/system-security-upgrader/${logpattern}_security-check/"

    echo "INFO: Log dir: $LOG_DIR"

    # source files
    # state manager
    source /usr/local/lib/system-security-upgrader/state-manager
    # failure evaluator
    source /usr/local/lib/system-security-upgrader/failure-evaluator
    # create logfile path pattern

    # create logdir path

    # create neccessary dirs
    mkdir -p /var/log/system-security-upgrader/
    mkdir "/var/log/system-security-upgrader/${logpattern}_security-check"
    mkdir -p "/var/lib/system-security-upgrader/summaries"
    mkdir -p "/var/lib/system-security-upgrader/summaries/${user}"
    chown "$user":"$user" "/var/lib/system-security-upgrader/summaries/"
    chown "$user":"$user" "/var/lib/system-security-upgrader/summaries/${user}"
    chmod 755 "/var/log/system-security-upgrader/${logpattern}_security-check"
    chmod 755 /var/log/system-security-upgrader/
    find /var/log/system-security-upgrader/"${logpattern}_security-check" -type f -exec chmod 755 {} +

    echo "Executing security checks script as root..."
}
function run_cmd {
    local description="$1"
    shift
    local logfile="$1"
    shift
    local timeout_seconds="$1"
    shift

    echo "${description}..."
    if timeout "$timeout_seconds" "$@" &>>"$logfile" 2>&1; then
        echo "${description}... Done"
        return 0
    else
        local exit_code="$?"
        if [[ "$description" =~ "rkhunter" && "$exit_code" -eq 1 ]]; then
            return 0 # warnings are not considered as failure for rkhunter
        else
            return "${exit_code}"
        fi
    fi
}
function end_script {
    echo "All the security checks have been performed. It took $SECONDS seconds."
    rm -f /var/lib/system-security-upgrader/pending-check # remove file that triggers the security check
    echo "The condition path for the security check to run has been removed, so the script won't run again until the next trigger file is created by the upgrade script."

    # change the owner of the logfiles to the $user
    chown "$user":"$user" "$LOG_DIR"*
    chown "$user":"$user" "$LOG_DIR"
    # creating the trigger file for the ai summarization daemon
    cat <<EOF >/var/lib/system-security-upgrader/pending-ai-summary
$user
$LOG_DIR
$logpattern
EOF
    # change the user to the owner of the trigger file to avoid permission errors
    chown "$user":"$user" /var/lib/system-security-upgrader/pending-ai-summary
    chmod 755 /var/lib/system-security-upgrader/
    chmod 755 /var/lib/system-security-upgrader/pending-ai-summary

    # DEBUG
}
function main {
    init "$@"

    # run lynis
    set +e
    run_cmd "Using lynis to audit the system" "${LOG_DIR}lynis.log" 1000 lynis audit system --quiet --no-colors --cron-job --log-file "${LOG_DIR}lynis.log"
    lynis_exit_code="$?"
    set -e
    local lynis_evaluation
    lynis_evaluation="$(evaluate_failure "$lynis_exit_code" "${LOG_DIR}lynis.log")"
    local lynis_level="${lynis_evaluation%%|*}"
    local lynis_reason="${lynis_evaluation##*|}"
    echo "INFO: Auditing with lynis: level=$lynis_level, reason=$lynis_reason"
    if [[ "$lynis_level" -eq 3 ]]; then
        echo "FATAL: Error while auting with lynis: $lynis_reason"
        local state_info
        state_info="$(gather_state_info)"
        last_attempt=$(awk -F '|' ' { print $1 } ' <<<"$state_info")
        last_success=$(awk -F '|' ' { print $2 } ' <<<"$state_info")
        failure_count=$(awk -F '|' ' { print $3 } ' <<<"$state_info")
        last_log_path=$(awk -F '|' ' { print $4 } ' <<<"$state_info")
        update_state "$last_attempt" "$last_success" "$failure_count" "$last_log_path"
        exit 1
    elif [[ "$lynis_level" -eq 2 ]]; then
        overall_failure=1
        echo "ERROR: Error while auting with lynis: $lynis_reason"
    fi
    echo "INFO: Finished auditing with lynis."

    # update rkhunter
    local rkhunter_update_logfile="${LOG_DIR}rkhunter_update.log"
    set +e
    run_cmd "Updating rkhunter database" "$rkhunter_update_logfile" 300 rkhunter --update --logfile "$rkhunter_update_logfile"
    set -e
    local rkhunter_update_exit_code="$?"
    rkhunter_update_evaluation="$(evaluate_failure "$rkhunter_update_exit_code" "$rkhunter_update_logfile")"
    local rkhunter_update_level="${rkhunter_update_evaluation%%|*}"
    local rkhunter_update_reason="${rkhunter_update_evaluation##*|}"
    echo "INFO: Updating rkhunter database: level=$rkhunter_update_level, reason=$rkhunter_update_reason"
    if [[ "$rkhunter_update_level" -eq 3 ]]; then
        echo "FATAL: Error while updating rkhunter database: $rkhunter_update_reason"
        state_info="$(gather_state_info)"
        last_attempt=$(awk -F '|' ' { print $1 } ' <<<"$state_info")
        last_success=$(awk -F '|' ' { print $2 } ' <<<"$state_info")
        failure_count=$(awk -F '|' ' { print $3 } ' <<<"$state_info")
        last_log_path=$(awk -F '|' ' { print $4 } ' <<<"$state_info")
        update_state "$last_attempt" "$last_success" "$failure_count" "$last_log_path"
        exit 1
    elif [[ "$rkhunter_update_level" -eq 2 ]]; then
        overall_failure=1
        echo "ERROR: Error while updating rkhunter database: $rkhunter_update_reason"
    fi
    echo "INFO: Finished updating rkhunter database."

    # update rkhunter's file prosperties
    local rkhunter_propupd_logfile="${LOG_DIR}rkhunter_propupd.log"
    set +e
    run_cmd "Updating rkhunter file prosperties" "$rkhunter_propupd_logfile" 300 rkhunter --propupd --logfile "$rkhunter_propupd_logfile"
    local rkhunter_propupd_exit_code="$?"
    set -e
    rkhunter_propupd_evaluation="$(evaluate_failure "$rkhunter_propupd_exit_code" "$rkhunter_propupd_logfile")"
    local rkhunter_propupd_level="${rkhunter_propupd_evaluation%%|*}"
    local rkhunter_propupd_reason="${rkhunter_propupd_evaluation##*|}"
    echo "INFO: Updating rkhunter file prosperties: level=$rkhunter_propupd_level, reason=$rkhunter_propupd_reason"
    if [[ "$rkhunter_propupd_level" -eq 3 ]]; then
        echo "FATAL: Error while updating rkhunter file prosperties: $rkhunter_propupd_reason"
        state_info="$(gather_state_info)"
        last_attempt=$(awk -F '|' ' { print $1 } ' <<<"$state_info")
        last_success=$(awk -F '|' ' { print $2 } ' <<<"$state_info")
        failure_count=$(awk -F '|' ' { print $3 } ' <<<"$state_info")
        last_log_path=$(awk -F '|' ' { print $4 } ' <<<"$state_info")
        update_state "$last_attempt" "$last_success" "$failure_count" "$last_log_path"
        exit 1
    elif [[ "$rkhunter_propupd_level" -eq 2 ]]; then
        overall_failure=1
        echo "ERROR: Error while updating rkhunter file prosperties: $rkhunter_propupd_reason"
    fi

    # run rkhunter with warnings only
    local rkhunter_logfile="${LOG_DIR}rkhunter.log"
    set +e
    run_cmd "Running rkhunter with warnings only" "$rkhunter_logfile" 1000 rkhunter --check --sk --nocolors --rwo
    local rkhunter_exit_code="$?"
    set -e
    rkhunter_evaluation="$(evaluate_failure "$rkhunter_exit_code" "$rkhunter_logfile")"
    local rkhunter_level="${rkhunter_evaluation%%|*}"
    local rkhunter_reason="${rkhunter_evaluation##*|}"
    echo "INFO: Running rkhunter with warnings only: level=$rkhunter_level, reason=$rkhunter_reason"
    if [[ "$rkhunter_level" -eq 3 ]]; then
        echo "FATAL: Error while running rkhunter with warnings only: $rkhunter_reason"
        state_info="$(gather_state_info)"
        last_attempt=$(awk -F '|' ' { print $1 } ' <<<"$state_info")
        last_success=$(awk -F '|' ' { print $2 } ' <<<"$state_info")
        failure_count=$(awk -F '|' ' { print $3 } ' <<<"$state_info")
        last_log_path=$(awk -F '|' ' { print $4 } ' <<<"$state_info")
        update_state "$last_attempt" "$last_success" "$failure_count" "$last_log_path"
        exit 1
    elif [[ "$rkhunter_level" -eq 2 ]]; then
        overall_failure=1
        echo "ERROR: Error while running rkhunter with warnings only: $rkhunter_reason"
    fi
    echo "INFO: Finished running rkhunter with warnings only."

    end_script
    local state_info
    state_info="$(gather_state_info)"
    last_attempt=$(awk -F '|' ' { print $1 } ' <<<"$state_info")
    last_success=$(awk -F '|' ' { print $2 } ' <<<"$state_info")
    failure_count=$(awk -F '|' ' { print $3 } ' <<<"$state_info")
    last_log_path=$(awk -F '|' ' { print $4 } ' <<<"$state_info")
    update_state "$last_attempt" "$last_success" "$failure_count" "$last_log_path"

    if [[ "$overall_failure" -eq 1 ]]; then
        echo "One or more errors were detected during the security checks. Please review the log files in ${LOG_DIR@Q} for more details."
        exit 1
    else
        exit 0
    fi

}

# call main with all args, as given
main "$@"
