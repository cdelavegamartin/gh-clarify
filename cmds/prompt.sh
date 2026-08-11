#!/usr/bin/env bash
# Prints the scheduled-review prompt body from ../workflow-prompt.md, so
# CI (or the Copilot app's save_workflow) can feed it straight to a headless
# `copilot -p "$(gh clarify prompt)"` invocation without vendoring or
# re-deriving the prompt text anywhere else.
#
# Usage: gh clarify prompt [-h|--help]
set -euo pipefail

script_name="$(basename "$0")"
cmd_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prompt_file="${cmd_dir}/../workflow-prompt.md"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '/^# Usage:/,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
    exit 0
fi

[[ -f "${prompt_file}" ]] || {
    echo "${script_name}: prompt file not found: ${prompt_file}" >&2
    exit 1
}

# The prompt body is everything after the "## Prompt body" heading in
# workflow-prompt.md, replicating the same extraction the GitHub Actions
# template used to do inline: strip the heading line itself, keep the rest
# (including the surrounding intro paragraph and ```` fence markers, exactly
# as `copilot -p` has always received them).
awk '/^## Prompt body$/,0' "${prompt_file}" | tail -n +2
