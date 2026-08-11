#!/usr/bin/env bash
# Adds the bot-answered label to a discussion.
#
# Usage: gh clarify label-answered <discussion-number> [--repo owner/repo] [-h|--help]
set -euo pipefail

script_name="$(basename "$0")"
# shellcheck source=../lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"

repo_value=""
number=""
remaining_args=()

parse_repo_flag "${script_name}" "$@"
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

# Self-heal: ensure the "bot-answered" label exists before applying it,
# since addLabelsToLabelable fails outright on a missing label id.
read -r owner name <<< "$(resolve_owner_name "${script_name}" "${repo_value}")"
name_with_owner="${owner}/${name}"
ensure_label "${name_with_owner}" "bot-answered" "Answered by a Copilot agent" "5319E7" || true

# $label is a GraphQL variable, not a shell one; must not expand.
# shellcheck disable=SC2016
label_lookup_response=$(gh api graphql -f query='
    query($owner:String!,$name:String!,$label:String!){
        repository(owner:$owner,name:$name){ label(name:$label){ id } }
    }' -f owner="${owner}" -f name="${name}" -f label="bot-answered") \
    || die "${script_name}" "gh api graphql (label lookup) failed"
check_graphql_errors "${script_name}" "${label_lookup_response}"
label_id=$(echo "${label_lookup_response}" | jq -r '.data.repository.label.id // empty')
[[ -n "${label_id}" ]] || die "${script_name}" "label \"bot-answered\" does not exist in ${name_with_owner} and could not be created"

discussion_id=$(resolve_discussion_id "${script_name}" "${owner}" "${name}" "${number}")

# $labelableId/$labelIds are GraphQL variables, not shell ones; must not expand.
# shellcheck disable=SC2016
gh api graphql -f query='
    mutation($labelableId:ID!,$labelIds:[ID!]!){
        addLabelsToLabelable(input:{labelableId:$labelableId,labelIds:$labelIds}){ clientMutationId }
    }' -f labelableId="${discussion_id}" -F "labelIds[]=${label_id}" \
    || die "${script_name}" "gh api graphql (addLabelsToLabelable) failed"
