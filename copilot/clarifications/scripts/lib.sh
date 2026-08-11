#!/usr/bin/env bash
# Shared helpers sourced by the other scripts in this directory. Not meant to
# be executed directly.
#
# Usage (from another script in this directory):
#   # shellcheck source=lib.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
set -euo pipefail

# die <script-name> <message...>
# Prints "<script-name>: <message>" to stderr and exits 1.
die() {
    local script_name="$1"
    shift
    echo "${script_name}: $*" >&2
    exit 1
}

# check_graphql_errors <script-name> <json-response>
# Fails loudly if the GraphQL response has a top-level "errors" array.
check_graphql_errors() {
    local script_name="$1"
    local response="$2"
    local errors
    errors=$(echo "${response}" | jq -r '.errors // [] | map(.message) | join("; ")')
    if [[ -n "${errors}" ]]; then
        die "${script_name}" "GraphQL error: ${errors}"
    fi
}

# resolve_owner_name <script-name> <repo_value-or-empty>
# Prints "<owner> <name>" (space-separated) for repo_value (an "owner/repo"
# string), or the current directory's repo if repo_value is empty. Dies via
# the shared die() helper on failure.
resolve_owner_name() {
    local script_name="$1" repo_value="$2" name_with_owner
    name_with_owner=$(gh repo view ${repo_value:+"${repo_value}"} --json nameWithOwner -q .nameWithOwner) \
        || die "${script_name}" "gh repo view failed"
    echo "${name_with_owner%%/*} ${name_with_owner#*/}"
}

# resolve_discussion_id <script-name> <owner> <name> <number>
# Looks up a discussion's GraphQL node id by its (repo-scoped) number via
# `gh api graphql` -- there is no `gh discussion view` to do this for us.
resolve_discussion_id() {
    local script_name="$1" owner="$2" name="$3" number="$4" response id
    # $owner/$name/$number are GraphQL variables, not shell ones; must not expand.
    # shellcheck disable=SC2016
    response=$(gh api graphql -f query='
        query($owner:String!,$name:String!,$number:Int!){
            repository(owner:$owner,name:$name){ discussion(number:$number){ id } }
        }' -f owner="${owner}" -f name="${name}" -F number="${number}") \
        || die "${script_name}" "gh api graphql (repository.discussion lookup) failed"
    check_graphql_errors "${script_name}" "${response}"
    id=$(echo "${response}" | jq -r '.data.repository.discussion.id // empty')
    [[ -n "${id}" ]] || die "${script_name}" "no discussion found with number ${number} in ${owner}/${name}"
    echo "${id}"
}

# url_encode_path <path>
# Percent-encodes each "/"-separated segment of <path> (via jq's @uri) and
# rejoins them with "/", so the result is safe to embed in a GitHub blob URL
# while still using "/" as the path separator. Needed because GitHub blob
# URLs are broken (not just cosmetically off) by literal spaces and other
# reserved characters in the path -- unlike the "File:" display value, the
# permalink is a real URL and must be encoded.
url_encode_path() {
    local path="$1"
    jq -Rr 'split("/") | map(@uri) | join("/")' <<<"${path}"
}

# ensure_label <owner/repo> <label> <description> <color>
# Idempotently creates a label if it doesn't already exist in the repo.
# Best-effort: prints a warning and returns 1 on failure instead of dying,
# so callers (which are labelling as a side effect, not the main payload)
# can decide whether that should be fatal.
ensure_label() {
    local repo="$1" label="$2" description="$3" color="$4"
    local output
    if output=$(gh label create "${label}" --repo "${repo}" -d "${description}" -c "${color}" 2>&1); then
        return 0
    fi
    if [[ "${output}" == *"already exists"* ]]; then
        return 0
    fi
    echo "warning: could not create label \"${label}\" in ${repo}: ${output}" >&2
    return 1
}
