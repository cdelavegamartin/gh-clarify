#!/usr/bin/env bash
# Idempotently creates the two labels used by the code-clarification
# workflow ("code-clarification", "bot-answered") in a repo. Safe to run
# repeatedly; existing labels are left untouched.
#
# Usage: gh clarify setup-labels [--repo owner/repo] [-h|--help]
set -euo pipefail

script_name="$(basename "$0")"
cmd_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/lib.sh
source "${cmd_dir}/../lib/lib.sh"

repo_value=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            sed -n '/^# Usage:/,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --repo)
            [[ $# -ge 2 ]] || die "${script_name}" "--repo requires a value"
            repo_value="$2"
            shift 2
            ;;
        *)
            die "${script_name}" "unknown argument: $1"
            ;;
    esac
done

# gh repo view takes the repo as a positional argument, not --repo.
repo=$(gh repo view ${repo_value:+"${repo_value}"} --json nameWithOwner -q .nameWithOwner) \
    || die "${script_name}" "gh repo view failed"

overall=0

if ensure_label "${repo}" "code-clarification" "Clarification question for Copilot agents" "0E8A16"; then
    echo "code-clarification: ok"
else
    overall=1
fi

if ensure_label "${repo}" "bot-answered" "Answered by a Copilot agent" "5319E7"; then
    echo "bot-answered: ok"
else
    overall=1
fi

exit "${overall}"
