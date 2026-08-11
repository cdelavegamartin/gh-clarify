#!/usr/bin/env bash
# Shows a discussion's full comment thread (oldest first) as JSON, so an
# agent can judge whether the last comment is a human asking for more
# detail. Performs no judgment itself.
#
# Usage: gh clarify show-thread <discussion-number> [--limit N] [--repo owner/repo] [-h|--help]
#   --limit N          Maximum number of comments/replies to fetch (default: 30).
#   --repo owner/repo   Target repo (default: current repo, via gh).
#
# There is no `gh discussion view` (see ../README.md#discussions-are-graphql-only),
# so this goes through `gh api graphql`. GitHub's Discussion.comments
# connection returns comments oldest-first by default (no orderBy arg
# exists on it), matching the previously-assumed `--order oldest` behavior.
set -euo pipefail

script_name="$(basename "$0")"
# shellcheck source=../lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"

limit=30
repo_value=""
number=""
remaining_args=()

parse_repo_and_limit_flags "${script_name}" "$@"
set -- "${remaining_args[@]}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            sed -n '/^# Usage:/,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            if [[ -n "${number}" ]]; then
                die "${script_name}" "unexpected argument: $1"
            fi
            number="$1"
            shift
            ;;
    esac
done

[[ -n "${number}" ]] || die "${script_name}" "usage: ${script_name} <discussion-number>"

read -r owner name <<< "$(resolve_owner_name "${script_name}" "${repo_value}")"

# $owner/$name/$number/$limit are GraphQL variables, not shell ones; must not expand.
# shellcheck disable=SC2016
response=$(gh api graphql -f query='
    query($owner:String!,$name:String!,$number:Int!,$limit:Int!){
        repository(owner:$owner,name:$name){
            discussion(number:$number){
                number title url body
                comments(first:$limit){
                    nodes{
                        id body createdAt
                        author{ login }
                        replies(first:$limit){
                            nodes{ id body createdAt author{ login } }
                        }
                    }
                }
            }
        }
    }' -f owner="${owner}" -f name="${name}" -F number="${number}" -F limit="${limit}") \
    || die "${script_name}" "gh api graphql (repository.discussion lookup) failed"
check_graphql_errors "${script_name}" "${response}"

discussion=$(echo "${response}" | jq -e '.data.repository.discussion') \
    || die "${script_name}" "no discussion found with number ${number} in ${owner}/${name}"

echo "${discussion}" | jq '{
    number, title, url, body,
    comments: [.comments.nodes[] | {
        id, body, createdAt,
        author: .author.login,
        replies: [.replies.nodes[] | {id, body, createdAt, author: .author.login}]
    }]
}'
