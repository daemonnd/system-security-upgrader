#!/bin/bash

# strict mode
set -Eeuo pipefail

# rm tmp files function
function rm_tmp_files {
    :
}

# Cleanup function
function cleanup {
    local exit_code="$?"
    echo "Script dashboard-builder.sh interrupted or failed. Cleaning up..."

    # remove tmp files
    rm_tmp_files
    # exit the script, preserving the exit code
    exit "$exit_code"
}

# trap errors
trap 'echo "Error on line $LINENO in dashboard-builder.sh: command \"$BASH_COMMAND\" exited with status $?" >&2' ERR
# trap signals
trap 'cleanup' INT TERM ERR

function check_args {
    user="${1:-}"
    if ! getent passwd "$user" | awk -F ':' ' { print $6 } ' >/dev/null; then
        echo "ERROR: It seems that the user ${user@Q} does not have a home dir."
        exit 1
    fi
}

function init {
    date_time_updated=$(date "+%Y-%m-%d %H:%M:%S")

    ai_summary_file=$(find /var/lib/system-security-upgrader/summaries/"$user"/ | sort | tail -1)
    if [[ "$ai_summary_file" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}_ai-summary\.md ]]; then
        :
    else
        echo "ERROR: $ai_summary_file does not start with the pattern for ai summaries."
        exit 1
    fi
}

function get-state-variables {
    # vars to return:
    # last_attempt_date
    # last_success_date
    # failure_count
    # last_log_path
    source /usr/local/lib/system-security-upgrader/state-lib "$1" &>/dev/null
    get_values

    detect_freshness

    validate_existence
    if [[ "$is_invalid" -eq 1 ]]; then
        return
    fi

    validate_type
    if [[ "$is_invalid" -eq 1 ]]; then
        return
    fi

    check_temporal_ordering
    if [[ "$is_invalid" -eq 1 ]]; then
        return
    fi

    check_consistency
    if [[ "$is_invalid" -eq 1 ]]; then
        return
    fi

    convert_date
    check_health_state
    return
}

function build-sys-upgrade {
    get-state-variables "sys-upgrade.state"
    echo "----System Upgrade State----"
    if [[ "$is_invalid" -eq 1 ]]; then
        echo "State file status: INVALID"
    fi

    if [[ "$is_stale" -eq 1 ]]; then
        echo "Freshness: STALE"
    else
        echo "Freshness: FRESH"
    fi
    last_attempt_date="${last_attempt_date//_/ }"
    last_success_date="${last_success_date//_/ }"
    echo "State: $state"
    echo "Sate Reason: $state_reason"
    echo "Last Attempt: ${last_attempt_date:-N/A}" # when the last run of user-maintenance was
    echo "Last Success: ${last_success_date:-N/A}" # when the last success was
    echo "Failure Count: ${failure_count:-N/A}"    # how many times user maintenance failed in a row
    echo "Last Log Path: ${last_log_path:-N/A}"    # log path of latest user maintenance run
}
function build-user-maintenance {
    get-state-variables "user-maintenance.state"
    echo "----User maintenance State ----"
    if [[ "$is_invalid" -eq 1 ]]; then
        echo "State file status: INVALID"
    fi

    if [[ "$is_stale" -eq 1 ]]; then
        echo "Freshness: STALE"
    else
        echo "Freshness: FRESH"
    fi
    last_attempt_date="${last_attempt_date//_/ }"
    last_success_date="${last_success_date//_/ }"
    echo "State: $state"
    echo "Sate Reason: $state_reason"
    echo "Last Attempt: ${last_attempt_date:-N/A}" # when the last run of user-maintenance was
    echo "Last Success: ${last_success_date:-N/A}" # when the last success was
    echo "Failure Count: ${failure_count:-N/A}"    # how many times user maintenance failed in a row
    echo "Last Log Path: ${last_log_path:-N/A}"    # log path of latest user maintenance run
}
function build-security-check {
    get-state-variables "security-check.state"
    echo "----security-check State----"
    if [[ "$is_invalid" -eq 1 ]]; then
        echo "State file status: INVALID"
    fi

    if [[ "$is_stale" -eq 1 ]]; then
        echo "Freshness: STALE"
    else
        echo "Freshness: FRESH"
    fi
    last_attempt_date="${last_attempt_date//_/ }"
    last_success_date="${last_success_date//_/ }"
    echo "State: $state"
    echo "Sate Reason: $state_reason"
    echo "Last Attempt: ${last_attempt_date:-N/A}" # when the last run of user-maintenance was
    echo "Last Success: ${last_success_date:-N/A}" # when the last success was
    echo "Failure Count: ${failure_count:-N/A}"    # how many times user maintenance failed in a row
    echo "Last Log Path: ${last_log_path:-N/A}"    # log path of latest user maintenance run
}

function build-ai-summary {
    ai_summary_date="${ai_summary_file##*/}"
    echo "AI security summary from ${ai_summary_date//_/ }:"
    cat "$ai_summary_file"
}

function main {
    # =========================
    # GLOBAL LOCK (DO NOT MOVE)
    # =========================
    exec 200>/tmp/dashboard-builder.lock
    flock -x 200
    # =========================
    check_args "$@"
    init "$@"
    local temp_file="/var/lib/system-security-upgrader/dashboard.tmp.$$"

    {
        echo "Dashboard last updated at: $date_time_updated"
        build-sys-upgrade
        build-user-maintenance
        build-security-check
        build-ai-summary
    } >"$temp_file"

    if ! mv "$temp_file" "/var/lib/system-security-upgrader/dashboard.md"; then
        rm -f "$temp_file"
        echo "FATAL: Failed to write dashboard file, the dashboard won't be updated." >&2
        exit 1
    else
        rm -f "$temp_file"
    fi
}

# call main with all args, as given
main "$@"
