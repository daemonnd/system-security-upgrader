#!/bin/bash

# strict mode
set -Eeuo pipefail

# trap errors
trap 'echo "Error on line $LINENO: command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

function init {
    # get the user & logdir
    declare -a tmp_arr
    mapfile -t tmp_arr < /var/lib/system-security-upgrader/pending-ai-summary
    user="${tmp_arr[0]}"
    logdir="${tmp_arr[1]}"
    echo "user: ${user@Q}"
    echo "logdir: ${logdir@Q}"
    # cp patterns to fabric
    cp -r /home/${user}/.config/system-security-upgrader/system_prompts/* "/home/${user}/.config/fabric/patterns/"
}
function check_args {
    echo
}

function filter {
    local logfile="$1"
    awk '
        /Warning:|Suggestion:/ {
        sub(/^.*Warning: /, "Warning: ")
        sub(/^.*Suggestion: /, "Suggestion: ")
        print
    }
    ' "$logfile" | awk '!seen[$0]++' # uniq the loglines

}
function run_ai {
    # tool: $1
    local tool="$1"
    filter "${logdir}${tool}.log"  | fabric -sp "system_security_upgrader_$1" -o "/home/${user}/Documents/${tool}.md"
}
function main {
    check_args "$@"
    init "$@"
    run_ai "lynis"

}

# call main with all args, as given
main "$@"

