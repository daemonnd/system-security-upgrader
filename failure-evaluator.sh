#!/bin/bash

# strict mode
set -Eeuo pipefail

# ---------------------------------------------------------------------------------
# Failure Evaluator
# ---------------------------------------------------------------------------------
# function to evaluate the failure of a command based on its exit code and logfile, and to return a severity level and a reason for the failure
evaluate_failure() {
    local exit_code="$1"
    local log_file="$2"

    if [[ "$exit_code" -eq 126 || "$exit_code" -eq 127 ]]; then
        echo "3|The command did not execute at all"
    elif [[ ! -r "$log_file" ]]; then
        echo "2|Logfile does not exist"
    elif [[ "$exit_code" -eq 124 ]]; then
        echo "2|Timout reached"
    elif [[ "$exit_code" -ne 0 ]]; then
        echo "2|Exit code of command is $exit_code, not 0"
        return
    elif [[ -f "$log_file" ]]; then
        if grep -qiE "(error:)" "$log_file" 2>/dev/null; then # does not include "failed" because reflector's warnings include "failed" as well, which are not necessarily an issue
            echo "2|Logs of tool contained keywords that are common for errors"
            return
        else
            echo "1|success"
        fi
    else
        echo "2|Unknown failure with exit code $exit_code"
    fi
}
