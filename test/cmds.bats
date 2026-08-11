#!/usr/bin/env bats
# Tests for the cmds/*.sh subcommands other than ask.sh (which has its own
# file). Each subcommand gets: --help, flag/argument validation, and a
# happy-path test that asserts both the resulting `gh` call shape and stdout.

load helpers/test_helper

setup() {
    setup_clarify_env
    CMDS="${REPO_ROOT}/cmds"
}

# --- help --------------------------------------------------------------------

@test "every subcommand's --help prints its usage and exits 0" {
    local script name
    for script in "${CMDS}"/*.sh; do
        name="$(basename "${script}")"
        run "${script}" --help
        assert_success
        assert_output_contains "Usage:"
        assert_output_contains "gh clarify ${name%.sh}"
        assert_equal "$(gh_call_count)" "0"
    done
}

@test "every subcommand's -h is equivalent to --help" {
    local script name
    for script in "${CMDS}"/*.sh; do
        name="$(basename "${script}")"
        run "${script}" -h
        assert_success
        assert_output_contains "gh clarify ${name%.sh}"
    done
}

# --- check-enabled -----------------------------------------------------------

@test "check-enabled prints true when Discussions is enabled" {
    run "${CMDS}/check-enabled.sh"
    assert_success
    assert_equal "${output}" "true"
    assert_gh_called_with "repo view" "--json hasDiscussionsEnabled,nameWithOwner"
}

@test "check-enabled prints false when Discussions is disabled" {
    export GH_STUB_REPO_JSON='{"nameWithOwner":"acme/widgets","hasDiscussionsEnabled":false}'
    run "${CMDS}/check-enabled.sh"
    assert_success
    assert_equal "${output}" "false"
}

@test "check-enabled --require exits non-zero when Discussions is disabled" {
    export GH_STUB_REPO_JSON='{"nameWithOwner":"acme/widgets","hasDiscussionsEnabled":false}'
    run "${CMDS}/check-enabled.sh" --require
    assert_failure 1
    assert_output_contains "GitHub Discussions is disabled for repository acme/widgets"
}

@test "check-enabled --require stays quiet when Discussions is enabled" {
    run "${CMDS}/check-enabled.sh" --require
    assert_success
    assert_equal "${output}" "true"
}

@test "check-enabled --verbose reports the resolved repo on stderr" {
    run "${CMDS}/check-enabled.sh" --verbose --repo acme/widgets
    assert_success
    assert_output_contains "check-enabled.sh: resolved repo: acme/widgets"
    assert_output_contains "check-enabled.sh: hasDiscussionsEnabled: true"
}

@test "check-enabled passes --repo positionally to gh repo view" {
    run "${CMDS}/check-enabled.sh" --repo other/repo
    assert_success
    assert_gh_called_with "repo view" "other/repo"
}

@test "check-enabled rejects an unknown argument" {
    run "${CMDS}/check-enabled.sh" --nope
    assert_failure 1
    assert_output_contains "check-enabled.sh: unknown argument: --nope"
}

@test "check-enabled rejects --repo without a value" {
    run "${CMDS}/check-enabled.sh" --repo
    assert_failure 1
    assert_output_contains "check-enabled.sh: --repo requires a value"
}

@test "check-enabled dies when gh repo view fails" {
    export GH_STUB_EXIT_repo_view=1
    run "${CMDS}/check-enabled.sh"
    assert_failure 1
    assert_output_contains "check-enabled.sh: gh repo view failed"
}

# --- list-new ----------------------------------------------------------------

@test "list-new searches for unanswered code-clarification discussions" {
    run "${CMDS}/list-new.sh"
    assert_success
    assert_gh_called_with "type: DISCUSSION" \
        "-f searchQuery=repo:acme/widgets label:code-clarification is:unanswered" \
        "-F limit=5"
    assert_output_contains '"number": 7'
    assert_output_contains '"title": "Why the retry loop?"'
}

@test "list-new honours --limit and --repo" {
    run "${CMDS}/list-new.sh" --limit 3 --repo other/repo
    assert_success
    assert_gh_called_with "repo view" "other/repo"
    assert_gh_called_with "type: DISCUSSION" "-F limit=3"
}

@test "list-new prints an empty JSON array when nothing matches" {
    export GH_STUB_RESPONSE_search='{"data":{"search":{"nodes":[]}}}'
    run "${CMDS}/list-new.sh"
    assert_success
    assert_equal "${output}" "[]"
}

@test "list-new rejects an unknown argument" {
    run "${CMDS}/list-new.sh" bogus
    assert_failure 1
    assert_output_contains "list-new.sh: unknown argument: bogus"
}

@test "list-new dies on a GraphQL error response" {
    export GH_STUB_RESPONSE_search='{"errors":[{"message":"rate limited"}]}'
    run "${CMDS}/list-new.sh"
    assert_failure 1
    assert_output_contains "list-new.sh: GraphQL error: rate limited"
}

@test "list-new dies when the search call fails" {
    export GH_STUB_EXIT_search=1
    run "${CMDS}/list-new.sh"
    assert_failure 1
    assert_output_contains "gh api graphql (discussion search) failed"
}

# --- list-followups ----------------------------------------------------------

@test "list-followups searches for bot-answered discussions" {
    run "${CMDS}/list-followups.sh"
    assert_success
    assert_gh_called_with "type: DISCUSSION" \
        "-f searchQuery=repo:acme/widgets label:bot-answered" \
        "-F limit=5"
    assert_output_contains '"number": 7'
}

@test "list-followups honours --limit" {
    run "${CMDS}/list-followups.sh" --limit 2
    assert_success
    assert_gh_called_with "type: DISCUSSION" "-F limit=2"
}

@test "list-followups rejects an unknown argument" {
    run "${CMDS}/list-followups.sh" --bogus
    assert_failure 1
    assert_output_contains "list-followups.sh: unknown argument: --bogus"
}

@test "list-followups rejects --limit without a value" {
    run "${CMDS}/list-followups.sh" --limit
    assert_failure 1
    assert_output_contains "list-followups.sh: --limit requires a value"
}

# --- show-thread -------------------------------------------------------------

@test "show-thread flattens the discussion, comments and replies" {
    run "${CMDS}/show-thread.sh" 7
    assert_success
    assert_gh_called_with "comments(first:" "-f owner=acme" "-f name=widgets" "-F number=7" "-F limit=30"
    assert_output_contains '"author": "copilot-bot"'
    assert_output_contains '"author": "maintainer"'
    assert_output_contains '"id": "DC_stubreply"'
}

@test "show-thread honours --limit" {
    run "${CMDS}/show-thread.sh" 7 --limit 5
    assert_success
    assert_gh_called_with "comments(first:" "-F limit=5"
}

@test "show-thread requires a discussion number" {
    run "${CMDS}/show-thread.sh"
    assert_failure 1
    assert_output_contains "usage: show-thread.sh <discussion-number>"
}

@test "show-thread rejects a second positional argument" {
    run "${CMDS}/show-thread.sh" 7 9
    assert_failure 1
    assert_output_contains "show-thread.sh: unexpected argument: 9"
}

@test "show-thread dies when the discussion does not exist" {
    export GH_STUB_RESPONSE_showThread='{"data":{"repository":{"discussion":null}}}'
    run "${CMDS}/show-thread.sh" 999
    assert_failure 1
    assert_output_contains "no discussion found with number 999 in acme/widgets"
}

# --- post-answer -------------------------------------------------------------

@test "post-answer resolves the discussion, posts the body and prints the comment id" {
    local body_file="${BATS_TEST_TMPDIR}/answer.md"
    printf 'Because the API is flaky.\n' >"${body_file}"

    run "${CMDS}/post-answer.sh" 7 "${body_file}"
    assert_success
    assert_equal "${output}" "DC_stubcomment"
    assert_gh_called_with "discussion(number:" "-F number=7"
    assert_gh_called_with "addDiscussionComment" \
        "-f discussionId=D_stubdiscussion" \
        "-f body=Because the API is flaky."
}

@test "post-answer requires both a number and a body file" {
    run "${CMDS}/post-answer.sh" 7
    assert_failure 1
    assert_output_contains "usage: post-answer.sh <discussion-number> <body-file>"
}

@test "post-answer rejects a missing body file" {
    run "${CMDS}/post-answer.sh" 7 "${BATS_TEST_TMPDIR}/nope.md"
    assert_failure 1
    assert_output_contains "post-answer.sh: body file not found:"
    assert_equal "$(gh_call_count)" "0"
}

@test "post-answer rejects a third positional argument" {
    local body_file="${BATS_TEST_TMPDIR}/answer.md"
    : >"${body_file}"
    run "${CMDS}/post-answer.sh" 7 "${body_file}" extra
    assert_failure 1
    assert_output_contains "post-answer.sh: unexpected argument: extra"
}

@test "post-answer dies when no comment id comes back" {
    local body_file="${BATS_TEST_TMPDIR}/answer.md"
    : >"${body_file}"
    export GH_STUB_RESPONSE_addDiscussionComment='{"data":{"addDiscussionComment":{"comment":{"id":null}}}}'
    run "${CMDS}/post-answer.sh" 7 "${body_file}"
    assert_failure 1
    assert_output_contains "no comment id returned in response"
}

@test "post-answer dies on a GraphQL error response" {
    local body_file="${BATS_TEST_TMPDIR}/answer.md"
    : >"${body_file}"
    export GH_STUB_RESPONSE_addDiscussionComment='{"errors":[{"message":"Discussion is locked"}]}'
    run "${CMDS}/post-answer.sh" 7 "${body_file}"
    assert_failure 1
    assert_output_contains "GraphQL error: Discussion is locked"
}

# --- mark-answered -----------------------------------------------------------

@test "mark-answered marks the given comment as the answer" {
    run "${CMDS}/mark-answered.sh" DC_stubcomment
    assert_success
    assert_gh_called_with "markDiscussionCommentAsAnswer" "-f commentId=DC_stubcomment"
    assert_output_contains "D_stubdiscussion"
}

@test "mark-answered requires a comment id" {
    run "${CMDS}/mark-answered.sh"
    assert_failure 1
    assert_output_contains "usage: mark-answered.sh <comment-id>"
    assert_equal "$(gh_call_count)" "0"
}

@test "mark-answered dies on a GraphQL error response" {
    export GH_STUB_RESPONSE_markDiscussionCommentAsAnswer='{"errors":[{"message":"Discussion is not in a Q&A category"}]}'
    run "${CMDS}/mark-answered.sh" DC_stubcomment
    assert_failure 1
    assert_output_contains "GraphQL error: Discussion is not in a Q&A category"
}

@test "mark-answered dies when the mutation call fails" {
    export GH_STUB_EXIT_markDiscussionCommentAsAnswer=1
    run "${CMDS}/mark-answered.sh" DC_stubcomment
    assert_failure 1
    assert_output_contains "gh api graphql (markDiscussionCommentAsAnswer) failed"
}

# --- label-answered ----------------------------------------------------------

@test "label-answered self-heals the label then applies it to the discussion" {
    run "${CMDS}/label-answered.sh" 7
    assert_success
    assert_gh_called_with "label create bot-answered" "--repo acme/widgets"
    assert_gh_called_with "label(name:" "-f label=bot-answered"
    assert_gh_called_with "discussion(number:" "-F number=7"
    assert_gh_called_with "addLabelsToLabelable" \
        "-f labelableId=D_stubdiscussion" \
        "-F labelIds[]=LA_botanswered"
}

@test "label-answered requires a discussion number" {
    run "${CMDS}/label-answered.sh"
    assert_failure 1
    assert_output_contains "usage: label-answered.sh <discussion-number>"
}

@test "label-answered rejects a second positional argument" {
    run "${CMDS}/label-answered.sh" 7 8
    assert_failure 1
    assert_output_contains "label-answered.sh: unexpected argument: 8"
}

@test "label-answered dies when the label is missing and cannot be created" {
    export GH_STUB_LABEL_CREATE=fail
    export GH_STUB_RESPONSE_labelLookup='{"data":{"repository":{"label":null}}}'
    run "${CMDS}/label-answered.sh" 7
    assert_failure 1
    assert_output_contains 'label "bot-answered" does not exist in acme/widgets and could not be created'
    refute_gh_called_with "addLabelsToLabelable"
}

@test "label-answered dies when applying the label fails" {
    export GH_STUB_EXIT_addLabelsToLabelable=1
    run "${CMDS}/label-answered.sh" 7
    assert_failure 1
    assert_output_contains "gh api graphql (addLabelsToLabelable) failed"
}

# --- setup-labels ------------------------------------------------------------

@test "setup-labels creates both workflow labels" {
    run "${CMDS}/setup-labels.sh"
    assert_success
    assert_gh_called_with "label create code-clarification" "--repo acme/widgets" "-c 0E8A16"
    assert_gh_called_with "label create bot-answered" "--repo acme/widgets" "-c 5319E7"
    assert_output_contains "code-clarification: ok"
    assert_output_contains "bot-answered: ok"
}

@test "setup-labels is idempotent when the labels already exist" {
    export GH_STUB_LABEL_CREATE=exists
    run "${CMDS}/setup-labels.sh"
    assert_success
    assert_output_contains "code-clarification: ok"
    assert_output_contains "bot-answered: ok"
}

@test "setup-labels exits non-zero if a label could not be created" {
    export GH_STUB_LABEL_CREATE_bot_answered=fail
    run "${CMDS}/setup-labels.sh"
    assert_failure 1
    assert_output_contains "code-clarification: ok"
    assert_output_contains 'warning: could not create label "bot-answered"'
}

@test "setup-labels rejects an unknown argument" {
    run "${CMDS}/setup-labels.sh" --bogus
    assert_failure 1
    assert_output_contains "setup-labels.sh: unknown argument: --bogus"
}

# --- prompt ------------------------------------------------------------------

@test "prompt prints the workflow prompt body without the heading" {
    run "${CMDS}/prompt.sh"
    assert_success
    refute_output_contains "## Prompt body"
    assert_output_contains "gh clarify"
    assert_equal "$(gh_call_count)" "0"
}

@test "prompt output matches the tail of workflow-prompt.md" {
    run "${CMDS}/prompt.sh"
    assert_success
    local expected
    expected="$(awk '/^## Prompt body$/,0' "${REPO_ROOT}/workflow-prompt.md" | tail -n +2)"
    assert_equal "${output}" "${expected}"
}
