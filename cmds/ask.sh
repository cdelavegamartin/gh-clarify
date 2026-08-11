#!/usr/bin/env bash
# Creates a "code-clarification" GitHub Discussion (Q&A category) pre-filled
# with a stable commit permalink and the exact code snippet, using the
# structure in ../templates/question-template.md. Invoked by the
# ask-clarification Agent Skill (../skill/ask-clarification/SKILL.md).
#
# Usage:
#   gh clarify ask --file-path <path> --start-line <n> \
#     [--end-line <n>] --title <title> --context <text> \
#     [--repo-path <path>] [-h|--help]
#
#   --file-path <path>   Path to the file, relative to the repo root (or
#                         absolute, as long as it resolves inside the repo).
#   --start-line <n>     First line of the snippet (1-based).
#   --end-line <n>       Last line of the snippet (1-based). Defaults to
#                         --start-line.
#   --title <title>      Terse, clear question title (also the discussion
#                         title).
#   --context <text>     Why you were looking at this and what's unclear.
#   --repo-path <path>   Path to the repo (default: current directory).
#
# Prints the created discussion URL (and any warning) to stdout on success.
set -euo pipefail

script_name="$(basename "$0")"
cmd_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/lib.sh
source "${cmd_dir}/../lib/lib.sh"

CLARIFICATION_LABEL="code-clarification"
QA_CATEGORY_SLUG="q-a"

repo_path="."
file_path=""
start_line=""
end_line=""
title=""
context=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help)
            sed -n '/^# Usage:/,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --repo-path)
            [[ $# -ge 2 ]] || die "${script_name}" "--repo-path requires a value"
            repo_path="$2"
            shift 2
            ;;
        --file-path)
            [[ $# -ge 2 ]] || die "${script_name}" "--file-path requires a value"
            file_path="$2"
            shift 2
            ;;
        --start-line)
            [[ $# -ge 2 ]] || die "${script_name}" "--start-line requires a value"
            start_line="$2"
            shift 2
            ;;
        --end-line)
            [[ $# -ge 2 ]] || die "${script_name}" "--end-line requires a value"
            end_line="$2"
            shift 2
            ;;
        --title)
            [[ $# -ge 2 ]] || die "${script_name}" "--title requires a value"
            title="$2"
            shift 2
            ;;
        --context)
            [[ $# -ge 2 ]] || die "${script_name}" "--context requires a value"
            context="$2"
            shift 2
            ;;
        *)
            die "${script_name}" "unknown argument: $1"
            ;;
    esac
done

[[ -n "${file_path}" ]] || die "${script_name}" "--file-path is required"
[[ -n "${start_line}" ]] || die "${script_name}" "--start-line is required"
[[ -n "${title}" ]] || die "${script_name}" "--title is required"
[[ -n "${context}" ]] || die "${script_name}" "--context is required"
end_line="${end_line:-${start_line}}"

# Validate line numbers strictly: both must be positive integers, and
# end_line must not precede start_line. This also guards the sed -n
# "${start_line},${end_line}p" call below against non-numeric/injected input.
[[ "${start_line}" =~ ^[1-9][0-9]*$ ]] || die "${script_name}" "--start-line must be a positive integer, got: ${start_line}"
[[ "${end_line}" =~ ^[1-9][0-9]*$ ]] || die "${script_name}" "--end-line must be a positive integer, got: ${end_line}"
((end_line >= start_line)) || die "${script_name}" "--end-line (${end_line}) must be >= --start-line (${start_line})"

# Discussions-disabled guard. check-enabled.sh has no --repo-path flag (it
# always uses the gh context of cwd), so run it from repo_path instead.
has_discussions=$(cd "${repo_path}" && "${cmd_dir}/check-enabled.sh") \
    || die "${script_name}" "could not check whether Discussions is enabled"
if [[ "${has_discussions}" != "true" ]]; then
    echo "GitHub Discussions is disabled for this repository, so no discussion was created. Ask a maintainer to enable it under Settings → General → Features → Discussions, or if it's staying disabled, note that in this repo's own .github/copilot-instructions.md (see ../README.md#handling-disabled-discussions)."
    exit 0
fi

repo_root=$(cd "${repo_path}" && git rev-parse --show-toplevel) \
    || die "${script_name}" "git rev-parse --show-toplevel failed"
sha=$(cd "${repo_path}" && git rev-parse HEAD) \
    || die "${script_name}" "git rev-parse HEAD failed"
name_with_owner=$(cd "${repo_path}" && gh repo view --json nameWithOwner -q .nameWithOwner) \
    || die "${script_name}" "gh repo view failed"

# Resolve file_path relative to repo_root, rejecting anything that escapes it.
if [[ "${file_path}" == /* ]]; then
    absolute_file_path="${file_path}"
else
    absolute_file_path="${repo_root%/}/${file_path}"
fi
absolute_file_path="$(cd "$(dirname "${absolute_file_path}")" 2>/dev/null && pwd)/$(basename "${absolute_file_path}")" \
    || die "${script_name}" "could not resolve --file-path: ${file_path}"

case "${absolute_file_path}" in
    "${repo_root}"/*)
        rel_path="${absolute_file_path#"${repo_root}"/}"
        ;;
    *)
        die "${script_name}" "--file-path must point to a file inside the repository root (${repo_root})."
        ;;
esac
# Normalize to POSIX separators (equivalent to JS's
# relPathRaw.split(path.sep).join("/")), so blob URLs and `git show` work
# even when a Windows shell yields backslash-separated paths.
rel_path="${rel_path//\\//}"

snippet=$(cd "${repo_path}" && git show "HEAD:${rel_path}" 2>/dev/null | sed -n "${start_line},${end_line}p") \
    || snippet="(could not read file content at HEAD — attach it manually)"
if [[ -z "${snippet}" ]]; then
    snippet="(could not read file content at HEAD — attach it manually)"
fi

if [[ "${start_line}" == "${end_line}" ]]; then
    line_fragment="L${start_line}"
else
    line_fragment="L${start_line}-L${end_line}"
fi
encoded_rel_path=$(url_encode_path "${rel_path}")
permalink="https://github.com/${name_with_owner}/blob/${sha}/${encoded_rel_path}#${line_fragment}"
short_sha="${sha:0:7}"
language="${rel_path##*.}"
if [[ "${language}" == "${rel_path}" ]]; then
    language=""
fi

body=$(
    cat <<BODY
## Question

${title}

## Location

- **File:** \`${rel_path}\`
- **Line(s):** \`${start_line}\`-\`${end_line}\` (as of commit \`${short_sha}\`)
- **Permalink:** ${permalink}

## Code snippet

\`\`\`${language}
${snippet}
\`\`\`

## Context

${context}
BODY
)

owner="${name_with_owner%%/*}"
repo_name="${name_with_owner#*/}"

# $owner/$name/$label are GraphQL variables, not shell ones; must not expand.
# shellcheck disable=SC2016
lookup_response=$(gh api graphql -f query='
    query($owner:String!,$name:String!,$label:String!){
        repository(owner:$owner,name:$name){
            id
            discussionCategories(first:25){ nodes{ id name slug } }
            label(name:$label){ id }
        }
    }' -f owner="${owner}" -f name="${repo_name}" -f label="${CLARIFICATION_LABEL}") \
    || die "${script_name}" "gh api graphql (repository lookup) failed"
check_graphql_errors "${script_name}" "${lookup_response}"

repository_id=$(echo "${lookup_response}" | jq -r '.data.repository.id')
label_id=$(echo "${lookup_response}" | jq -r '.data.repository.label.id // empty')
category_id=$(echo "${lookup_response}" | jq -r --arg slug "${QA_CATEGORY_SLUG}" \
    '.data.repository.discussionCategories.nodes[] | select(.slug == $slug) | .id' | head -n1)
if [[ -z "${category_id}" ]]; then
    category_id=$(echo "${lookup_response}" | jq -r \
        '.data.repository.discussionCategories.nodes[] | select(.name | ascii_downcase == "q&a") | .id' | head -n1)
fi
if [[ -z "${category_id}" ]]; then
    echo "No \"Q&A\" discussion category exists in ${name_with_owner}, so no discussion was created. Ask a maintainer to add one under Settings → General → Features → Discussions → Categories (see ../README.md#one-time-setup-in-a-target-repo)."
    exit 0
fi

# $repoId/$categoryId/$title/$body are GraphQL variables, not shell ones; must not expand.
# shellcheck disable=SC2016
create_response=$(gh api graphql -f query='
    mutation($repoId:ID!,$categoryId:ID!,$title:String!,$body:String!){
        createDiscussion(input:{repositoryId:$repoId,categoryId:$categoryId,title:$title,body:$body}){
            discussion{ id url }
        }
    }' -f repoId="${repository_id}" -f categoryId="${category_id}" -f title="${title}" -f body="${body}") \
    || die "${script_name}" "gh api graphql (createDiscussion) failed"
check_graphql_errors "${script_name}" "${create_response}"

discussion_id=$(echo "${create_response}" | jq -r '.data.createDiscussion.discussion.id')
discussion_url=$(echo "${create_response}" | jq -r '.data.createDiscussion.discussion.url')

# Labelling is best-effort: the discussion itself is the payload, so a
# missing label or a failed label-apply must not fail the whole script.
label_note=""
if [[ -z "${label_id}" ]]; then
    if ensure_label "${name_with_owner}" "${CLARIFICATION_LABEL}" "Clarification question for Copilot agents" "0E8A16"; then
        # $owner/$name/$label are GraphQL variables, not shell ones; must not expand.
        # shellcheck disable=SC2016
        relookup_response=$(gh api graphql -f query='
            query($owner:String!,$name:String!,$label:String!){
                repository(owner:$owner,name:$name){ label(name:$label){ id } }
            }' -f owner="${owner}" -f name="${repo_name}" -f label="${CLARIFICATION_LABEL}") \
            && label_id=$(echo "${relookup_response}" | jq -r '.data.repository.label.id // empty')
    fi
fi
if [[ -z "${label_id}" ]]; then
    label_note=" (label \"${CLARIFICATION_LABEL}\" doesn't exist in this repo and could not be created automatically — create it with \`gh label create ${CLARIFICATION_LABEL} -d \"Clarification question for Copilot agents\" -c \"0E8A16\"\`)"
    echo "warning: ${script_name}: ${label_note}" >&2
else
    # $labelableId/$labelIds are GraphQL variables, not shell ones; must not expand.
    # shellcheck disable=SC2016
    label_response=$(gh api graphql -f query='
        mutation($labelableId:ID!,$labelIds:[ID!]!){
            addLabelsToLabelable(input:{labelableId:$labelableId,labelIds:$labelIds}){ clientMutationId }
        }' -f labelableId="${discussion_id}" -F "labelIds[]=${label_id}" 2>&1) \
        && label_error="" \
        || label_error="command failed"
    if [[ -z "${label_error}" ]]; then
        label_errors=$(echo "${label_response}" | jq -r '.errors // [] | map(.message) | join("; ")' 2>/dev/null || echo "")
        if [[ -n "${label_errors}" ]]; then
            label_error="${label_errors}"
        fi
    fi
    if [[ -n "${label_error}" ]]; then
        label_note=" (could not apply the \"${CLARIFICATION_LABEL}\" label: ${label_error})"
        echo "warning: ${script_name}: ${label_note}" >&2
    fi
fi

echo "Created clarification discussion: ${discussion_url}${label_note}"
