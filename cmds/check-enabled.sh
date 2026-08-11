#!/usr/bin/env bash
# Checks whether GitHub Discussions is enabled for a repository.
#
# Usage: gh clarify check-enabled [--repo owner/repo] [--require] [--verbose] [-h|--help]
#   --repo owner/repo   Target repo (default: current repo, via gh).
#   --require            Exit non-zero with a stderr message if Discussions
#                         is disabled, instead of just printing true/false.
#                         Intended for use as a fail-fast step in a
#                         GitHub Actions workflow.
#   --verbose             Print diagnostic info (resolved repo, command run)
#                         to stderr. Useful when troubleshooting `gh` auth
#                         or repo-resolution issues.
#
# Note: unlike `gh discussion list/view/edit` (used by the other scripts in
# this directory), `gh repo view` takes the repo as a *positional* argument,
# not a `--repo` flag. This script accepts `--repo owner/repo` for a
# consistent CLI across the workflow, then passes it positionally to
# `gh repo view`.
set -euo pipefail

script_name="$(basename "$0")"
# shellcheck source=../lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"

repo=()
require=false
verbose=false
remaining_args=()
repo_value=""

parse_repo_flag "${script_name}" "$@"
set -- "${remaining_args[@]}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help)
            sed -n '/^# Usage:/,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --require)
            require=true
            shift
            ;;
        --verbose)
            verbose=true
            shift
            ;;
        *)
            die "${script_name}" "unknown argument: $1"
            ;;
    esac
done

[[ -n "${repo_value}" ]] && repo=("${repo_value}")

if [[ "${verbose}" == "true" ]]; then
    echo "${script_name}: repo arg: ${repo[*]:-<none, gh will resolve from cwd>}" >&2
    echo "${script_name}: require: ${require}" >&2
    echo "${script_name}: running: gh repo view ${repo[*]:-} --json hasDiscussionsEnabled,nameWithOwner" >&2
fi

response=$(gh repo view --json hasDiscussionsEnabled,nameWithOwner "${repo[@]}") \
    || die "${script_name}" "gh repo view failed"

enabled=$(echo "${response}" | jq -r '.hasDiscussionsEnabled')
name_with_owner=$(echo "${response}" | jq -r '.nameWithOwner')

if [[ "${verbose}" == "true" ]]; then
    echo "${script_name}: resolved repo: ${name_with_owner}" >&2
    echo "${script_name}: hasDiscussionsEnabled: ${enabled}" >&2
fi

if [[ "${require}" == "true" && "${enabled}" != "true" ]]; then
    die "${script_name}" "GitHub Discussions is disabled for repository ${name_with_owner}. Ask a maintainer to enable it under Settings → General → Features → Discussions."
fi

echo "${enabled}"
