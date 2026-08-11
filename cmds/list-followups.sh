#!/usr/bin/env bash
# Lists bot-answered code-clarification GitHub Discussions that may need a
# follow-up answer, as JSON. Only lists candidates — does NOT judge whether
# the last comment is actually a human asking for more detail; that
# judgment call is left to the calling prompt/agent.
#
# Usage: gh clarify list-followups [--limit N] [--repo owner/repo] [-h|--help]
#   --limit N          Maximum number of discussions to fetch (default: 5).
#   --repo owner/repo   Target repo (default: current repo, via gh).
#
# There is no `gh discussion list` (see ../README.md#discussions-are-graphql-only
# and list-new.sh), so this goes through `gh api graphql`'s
# `search(type: DISCUSSION)` with a `label:` qualifier.
set -euo pipefail

script_name="$(basename "$0")"
# shellcheck source=../lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"

limit=5
repo_value=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            sed -n '/^# Usage:/,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --limit)
            [[ $# -ge 2 ]] || die "${script_name}" "--limit requires a value"
            limit="$2"
            shift 2
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

read -r owner name <<< "$(resolve_owner_name "${script_name}" "${repo_value}")"

# $searchQuery is a GraphQL variable, not a shell one; must not expand.
# shellcheck disable=SC2016
response=$(gh api graphql -f query='
    query($searchQuery:String!,$limit:Int!){
        search(query:$searchQuery, type: DISCUSSION, first:$limit){
            nodes{ ... on Discussion { number title url } }
        }
    }' -f searchQuery="repo:${owner}/${name} label:bot-answered" -F limit="${limit}") \
    || die "${script_name}" "gh api graphql (discussion search) failed"
check_graphql_errors "${script_name}" "${response}"

echo "${response}" | jq '.data.search.nodes'
