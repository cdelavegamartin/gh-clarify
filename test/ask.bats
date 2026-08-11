#!/usr/bin/env bats
# Tests for cmds/ask.sh, the only subcommand that reads the working tree. It
# runs against a real throwaway git repo (see make_git_fixture_repo) so the
# git plumbing it relies on -- repo-root resolution, `git show HEAD:<path>`,
# the commit sha in the permalink -- is exercised for real while staying
# deterministic and offline.

load helpers/test_helper

setup() {
    setup_clarify_env
    ASK="${REPO_ROOT}/cmds/ask.sh"
    FIXTURE_REPO="$(make_git_fixture_repo)"
    FIXTURE_SHA="$(git -C "${FIXTURE_REPO}" rev-parse HEAD)"
}

# ask <extra-args...> -- runs ask.sh against the fixture repo with the
# required flags filled in.
ask() {
    run "${ASK}" --repo-path "${FIXTURE_REPO}" \
        --title "Why does one() return 1?" \
        --context "Reading this while tracing a caller." \
        "$@"
}

# --- happy path --------------------------------------------------------------

@test "ask creates a discussion in the Q&A category and prints its URL" {
    ask --file-path src/app.py --start-line 1 --end-line 2
    assert_success
    assert_output_contains "Created clarification discussion: https://github.com/acme/widgets/discussions/42"
    assert_gh_called_with "discussionCategories" "-f owner=acme" "-f name=widgets" "-f label=code-clarification"
    assert_gh_called_with "createDiscussion" "-f repoId=R_stubrepo" "-f categoryId=DIC_qa"
}

@test "ask sends the title, the snippet and the context in the discussion body" {
    ask --file-path src/app.py --start-line 1 --end-line 2
    assert_success
    assert_gh_called_with "createDiscussion" \
        "-f title=Why does one() return 1?" \
        "def one(): return 1" \
        "Reading this while tracing a caller." \
        '```py'
}

@test "ask labels the new discussion with code-clarification" {
    ask --file-path src/app.py --start-line 1
    assert_success
    assert_gh_called_with "addLabelsToLabelable" \
        "-f labelableId=D_stubdiscussion" \
        "-F labelIds[]=LA_clarification"
}

# --- permalink construction --------------------------------------------------

@test "ask builds a single-line permalink fragment when there is no --end-line" {
    ask --file-path src/app.py --start-line 5
    assert_success
    assert_gh_called_with "createDiscussion" \
        "https://github.com/acme/widgets/blob/${FIXTURE_SHA}/src/app.py#L5"
    refute_gh_called_with "src/app.py#L5-L"
}

@test "ask builds a range permalink fragment for a multi-line snippet" {
    ask --file-path src/app.py --start-line 1 --end-line 5
    assert_success
    assert_gh_called_with "createDiscussion" \
        "https://github.com/acme/widgets/blob/${FIXTURE_SHA}/src/app.py#L1-L5"
}

@test "ask collapses --end-line equal to --start-line to a single-line fragment" {
    ask --file-path src/app.py --start-line 5 --end-line 5
    assert_success
    assert_gh_called_with "createDiscussion" "src/app.py#L5 "
}

@test "ask percent-encodes a space in the permalink but not in the File: line" {
    ask --file-path "docs/release notes.md" --start-line 1
    assert_success
    assert_gh_called_with "createDiscussion" \
        "blob/${FIXTURE_SHA}/docs/release%20notes.md#L1" \
        '**File:** `docs/release notes.md`'
}

@test "ask percent-encodes a '#' so it can't truncate the permalink" {
    ask --file-path "docs/c#sharp.md" --start-line 2
    assert_success
    assert_gh_called_with "createDiscussion" "blob/${FIXTURE_SHA}/docs/c%23sharp.md#L2"
}

@test "ask accepts an absolute --file-path inside the repo" {
    ask --file-path "${FIXTURE_REPO}/src/app.py" --start-line 1
    assert_success
    assert_gh_called_with "createDiscussion" "blob/${FIXTURE_SHA}/src/app.py#L1"
}

# --- snippet extraction ------------------------------------------------------

@test "ask reads the snippet from HEAD, not the working tree" {
    printf 'uncommitted junk\n' >"${FIXTURE_REPO}/src/app.py"
    ask --file-path src/app.py --start-line 1
    assert_success
    assert_gh_called_with "createDiscussion" "def one():"
    refute_gh_called_with "uncommitted junk"
}

@test "ask falls back to a placeholder when the file isn't in HEAD" {
    printf 'brand new\n' >"${FIXTURE_REPO}/src/untracked.py"
    ask --file-path src/untracked.py --start-line 1
    assert_success
    assert_gh_called_with "createDiscussion" "could not read file content at HEAD"
}

@test "ask falls back to a placeholder when the line range is past the end of the file" {
    ask --file-path src/app.py --start-line 900 --end-line 901
    assert_success
    assert_gh_called_with "createDiscussion" "could not read file content at HEAD"
}

# --- repo-boundary check -----------------------------------------------------

@test "ask rejects a --file-path that escapes the repo root" {
    ask --file-path ../outside.txt --start-line 1
    assert_failure 1
    assert_output_contains "--file-path must point to a file inside the repository root"
    refute_gh_called_with "createDiscussion"
}

@test "ask rejects an absolute --file-path outside the repo root" {
    ask --file-path /etc/hosts --start-line 1
    assert_failure 1
    assert_output_contains "--file-path must point to a file inside the repository root"
    refute_gh_called_with "createDiscussion"
}

@test "ask rejects a traversal path that lands back outside via .." {
    ask --file-path "src/../../outside.txt" --start-line 1
    assert_failure 1
    assert_output_contains "--file-path must point to a file inside the repository root"
}

# --- early exits -------------------------------------------------------------

@test "ask exits 0 without creating anything when Discussions is disabled" {
    export GH_STUB_REPO_JSON='{"nameWithOwner":"acme/widgets","hasDiscussionsEnabled":false}'
    ask --file-path src/app.py --start-line 1
    assert_success
    assert_output_contains "GitHub Discussions is disabled for this repository, so no discussion was created."
    refute_gh_called_with "createDiscussion"
}

@test "ask exits 0 without creating anything when there is no Q&A category" {
    export GH_STUB_RESPONSE_repoLookup='{"data":{"repository":{"id":"R_stubrepo","discussionCategories":{"nodes":[{"id":"DIC_general","name":"General","slug":"general"}]},"label":{"id":"LA_clarification"}}}}'
    ask --file-path src/app.py --start-line 1
    assert_success
    assert_output_contains 'No "Q&A" discussion category exists in acme/widgets, so no discussion was created.'
    refute_gh_called_with "createDiscussion"
}

@test "ask falls back to matching the Q&A category by name when the slug differs" {
    export GH_STUB_RESPONSE_repoLookup='{"data":{"repository":{"id":"R_stubrepo","discussionCategories":{"nodes":[{"id":"DIC_qa","name":"Q&A","slug":"questions-and-answers"}]},"label":{"id":"LA_clarification"}}}}'
    ask --file-path src/app.py --start-line 1
    assert_success
    assert_gh_called_with "createDiscussion" "-f categoryId=DIC_qa"
}

# --- best-effort labelling ---------------------------------------------------

@test "ask creates the missing code-clarification label, then applies it" {
    export GH_STUB_RESPONSE_repoLookup='{"data":{"repository":{"id":"R_stubrepo","discussionCategories":{"nodes":[{"id":"DIC_qa","name":"Q&A","slug":"q-a"}]},"label":null}}}'
    export GH_STUB_RESPONSE_labelLookup='{"data":{"repository":{"label":{"id":"LA_created"}}}}'
    ask --file-path src/app.py --start-line 1
    assert_success
    assert_gh_called_with "label create code-clarification" "--repo acme/widgets"
    assert_gh_called_with "addLabelsToLabelable" "-F labelIds[]=LA_created"
}

@test "ask still succeeds when the label cannot be created" {
    export GH_STUB_RESPONSE_repoLookup='{"data":{"repository":{"id":"R_stubrepo","discussionCategories":{"nodes":[{"id":"DIC_qa","name":"Q&A","slug":"q-a"}]},"label":null}}}'
    export GH_STUB_LABEL_CREATE=fail
    ask --file-path src/app.py --start-line 1
    assert_success
    assert_output_contains "Created clarification discussion: https://github.com/acme/widgets/discussions/42"
    assert_output_contains 'label "code-clarification" doesn'"'"'t exist in this repo and could not be created automatically'
}

@test "ask still succeeds when applying the label fails" {
    export GH_STUB_RESPONSE_addLabelsToLabelable='{"errors":[{"message":"Label is not applicable"}]}'
    ask --file-path src/app.py --start-line 1
    assert_success
    assert_output_contains "Created clarification discussion:"
    assert_output_contains 'could not apply the "code-clarification" label: Label is not applicable'
}

# --- flag validation ---------------------------------------------------------

@test "ask --help prints usage and touches nothing" {
    run "${ASK}" --help
    assert_success
    assert_output_contains "gh clarify ask --file-path <path>"
    assert_equal "$(gh_call_count)" "0"
}

@test "ask requires --file-path" {
    run "${ASK}" --repo-path "${FIXTURE_REPO}" --start-line 1 --title t --context c
    assert_failure 1
    assert_output_contains "ask.sh: --file-path is required"
}

@test "ask requires --start-line" {
    run "${ASK}" --repo-path "${FIXTURE_REPO}" --file-path src/app.py --title t --context c
    assert_failure 1
    assert_output_contains "ask.sh: --start-line is required"
}

@test "ask requires --title" {
    run "${ASK}" --repo-path "${FIXTURE_REPO}" --file-path src/app.py --start-line 1 --context c
    assert_failure 1
    assert_output_contains "ask.sh: --title is required"
}

@test "ask requires --context" {
    run "${ASK}" --repo-path "${FIXTURE_REPO}" --file-path src/app.py --start-line 1 --title t
    assert_failure 1
    assert_output_contains "ask.sh: --context is required"
}

@test "ask rejects a flag that is missing its value" {
    run "${ASK}" --file-path
    assert_failure 1
    assert_output_contains "ask.sh: --file-path requires a value"

    run "${ASK}" --start-line
    assert_failure 1
    assert_output_contains "ask.sh: --start-line requires a value"

    run "${ASK}" --title
    assert_failure 1
    assert_output_contains "ask.sh: --title requires a value"
}

@test "ask rejects an unknown argument" {
    run "${ASK}" --bogus value
    assert_failure 1
    assert_output_contains "ask.sh: unknown argument: --bogus"
}

@test "ask rejects a non-numeric --start-line" {
    ask --file-path src/app.py --start-line "1; rm -rf /"
    assert_failure 1
    assert_output_contains "--start-line must be a positive integer, got: 1; rm -rf /"
    assert_equal "$(gh_call_count)" "0"
}

@test "ask rejects a zero or negative --start-line" {
    ask --file-path src/app.py --start-line 0
    assert_failure 1
    assert_output_contains "--start-line must be a positive integer, got: 0"

    ask --file-path src/app.py --start-line -3
    assert_failure 1
    assert_output_contains "--start-line must be a positive integer, got: -3"
}

@test "ask rejects a non-numeric --end-line" {
    ask --file-path src/app.py --start-line 1 --end-line abc
    assert_failure 1
    assert_output_contains "--end-line must be a positive integer, got: abc"
}

@test "ask rejects a reversed line range" {
    ask --file-path src/app.py --start-line 9 --end-line 2
    assert_failure 1
    assert_output_contains "--end-line (2) must be >= --start-line (9)"
    assert_equal "$(gh_call_count)" "0"
}

# --- failure propagation -----------------------------------------------------

@test "ask dies when the repository lookup fails" {
    export GH_STUB_EXIT_repoLookup=1
    ask --file-path src/app.py --start-line 1
    assert_failure 1
    assert_output_contains "gh api graphql (repository lookup) failed"
}

@test "ask dies on a GraphQL error from createDiscussion" {
    export GH_STUB_RESPONSE_createDiscussion='{"errors":[{"message":"Discussions are disabled"}]}'
    ask --file-path src/app.py --start-line 1
    assert_failure 1
    assert_output_contains "GraphQL error: Discussions are disabled"
}
