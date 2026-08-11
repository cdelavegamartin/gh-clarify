#!/usr/bin/env bash
# Marks a comment as the accepted answer on a discussion (only valid on
# Q&A category discussions) via GraphQL.
#
# Usage: gh clarify mark-answered <comment-id> [-h|--help]
set -euo pipefail

script_name="$(basename "$0")"
# shellcheck source=../lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '/^# Usage:/,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
    exit 0
fi

comment_id="${1:-}"
[[ -n "${comment_id}" ]] || die "${script_name}" "usage: ${script_name} <comment-id>"

# $commentId is a GraphQL variable, not a shell one; must not expand.
# shellcheck disable=SC2016
response=$(gh api graphql -f query='
  mutation($commentId: ID!) {
    markDiscussionCommentAsAnswer(input: {id: $commentId}) {
      discussion { id }
    }
  }' -f commentId="${comment_id}") \
    || die "${script_name}" "gh api graphql (markDiscussionCommentAsAnswer) failed"

check_graphql_errors "${script_name}" "${response}"

echo "${response}"
