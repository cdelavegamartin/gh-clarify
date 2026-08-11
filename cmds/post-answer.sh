#!/usr/bin/env bash
# Posts an answer as a comment on a code-clarification discussion via
# GraphQL (not `gh discussion comment`, so the new comment's id is returned
# in the same call). Prints the resulting comment id to stdout on success.
#
# Usage: gh clarify post-answer <discussion-number> <body-file> [--repo owner/repo] [-h|--help]
#   --repo owner/repo   Target repo (default: current repo, via gh).
set -euo pipefail

script_name="$(basename "$0")"
# shellcheck source=../lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"

repo_value=""
number=""
body_file=""

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
            if [[ -z "${number}" ]]; then
                number="$1"
            elif [[ -z "${body_file}" ]]; then
                body_file="$1"
            else
                die "${script_name}" "unexpected argument: $1"
            fi
            shift
            ;;
    esac
done

[[ -n "${number}" && -n "${body_file}" ]] \
    || die "${script_name}" "usage: ${script_name} <discussion-number> <body-file>"
[[ -f "${body_file}" ]] || die "${script_name}" "body file not found: ${body_file}"

read -r owner name <<< "$(resolve_owner_name "${script_name}" "${repo_value}")"
discussion_id=$(resolve_discussion_id "${script_name}" "${owner}" "${name}" "${number}")

# $discussionId/$body are GraphQL variables, not shell ones; must not expand.
# shellcheck disable=SC2016
response=$(gh api graphql -f query='
  mutation($discussionId: ID!, $body: String!) {
    addDiscussionComment(input: {discussionId: $discussionId, body: $body}) {
      comment { id }
    }
  }' -f discussionId="${discussion_id}" -f body="$(cat "${body_file}")") \
    || die "${script_name}" "gh api graphql (addDiscussionComment) failed"

check_graphql_errors "${script_name}" "${response}"

comment_id=$(echo "${response}" | jq -r '.data.addDiscussionComment.comment.id')
[[ -n "${comment_id}" && "${comment_id}" != "null" ]] \
    || die "${script_name}" "no comment id returned in response: ${response}"

echo "${comment_id}"
