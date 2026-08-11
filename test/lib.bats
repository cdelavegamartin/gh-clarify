#!/usr/bin/env bats
# Unit tests for the helpers in lib/lib.sh. Each helper is exercised in a
# subshell that sources lib.sh, so `die`'s `exit 1` doesn't take the test
# runner with it.

load helpers/test_helper

setup() {
    setup_clarify_env
}

# run_lib <shell-code> -- sources lib.sh and runs <shell-code> in a bash -c
# subshell. script_name is fixed so error-message assertions stay stable.
run_lib() {
    run bash -c "source '${REPO_ROOT}/lib/lib.sh'; script_name=test-script; $1"
}

@test "die prints '<script>: <message>' to stderr and exits 1" {
    run_lib 'die "${script_name}" "something broke"'
    assert_failure 1
    assert_output_contains "test-script: something broke"
}

@test "check_graphql_errors is a no-op on a clean response" {
    run_lib 'check_graphql_errors "${script_name}" "{\"data\":{\"ok\":true}}"; echo survived'
    assert_success
    assert_output_contains "survived"
}

@test "check_graphql_errors dies and joins every error message" {
    run_lib 'check_graphql_errors "${script_name}" "{\"errors\":[{\"message\":\"first\"},{\"message\":\"second\"}]}"; echo survived'
    assert_failure 1
    assert_output_contains "test-script: GraphQL error: first; second"
    refute_output_contains "survived"
}

@test "parse_repo_flag extracts --repo and passes everything else through" {
    run_lib 'repo_value=""; remaining_args=()
        parse_repo_flag "${script_name}" --repo acme/widgets 12 --verbose
        echo "repo=${repo_value}"
        echo "rest=${remaining_args[*]}"'
    assert_success
    assert_output_contains "repo=acme/widgets"
    assert_output_contains "rest=12 --verbose"
}

@test "parse_repo_flag leaves repo_value empty when --repo is absent" {
    run_lib 'repo_value=""; remaining_args=()
        parse_repo_flag "${script_name}" 12
        echo "repo=[${repo_value}]"
        echo "rest=${remaining_args[*]}"'
    assert_success
    assert_output_contains "repo=[]"
    assert_output_contains "rest=12"
}

@test "parse_repo_flag dies when --repo has no value" {
    run_lib 'repo_value=""; remaining_args=(); parse_repo_flag "${script_name}" --repo'
    assert_failure 1
    assert_output_contains "test-script: --repo requires a value"
}

@test "parse_repo_and_limit_flags extracts both flags in any order" {
    run_lib 'repo_value=""; limit=5; remaining_args=()
        parse_repo_and_limit_flags "${script_name}" --limit 3 7 --repo acme/widgets
        echo "repo=${repo_value} limit=${limit} rest=${remaining_args[*]}"'
    assert_success
    assert_output_contains "repo=acme/widgets limit=3 rest=7"
}

@test "parse_repo_and_limit_flags keeps the default limit when --limit is absent" {
    run_lib 'repo_value=""; limit=5; remaining_args=()
        parse_repo_and_limit_flags "${script_name}" --repo acme/widgets
        echo "limit=${limit}"'
    assert_success
    assert_output_contains "limit=5"
}

@test "parse_repo_and_limit_flags dies when --limit has no value" {
    run_lib 'repo_value=""; limit=5; remaining_args=(); parse_repo_and_limit_flags "${script_name}" --limit'
    assert_failure 1
    assert_output_contains "test-script: --limit requires a value"
}

@test "resolve_owner_name splits nameWithOwner into owner and name" {
    run_lib 'resolve_owner_name "${script_name}" ""'
    assert_success
    assert_output_contains "acme widgets"
    assert_gh_called_with "repo view" "--json nameWithOwner"
}

@test "resolve_owner_name passes --repo positionally to gh repo view" {
    run_lib 'resolve_owner_name "${script_name}" "other/repo"'
    assert_success
    assert_gh_called_with "repo view other/repo" "--json nameWithOwner"
}

@test "resolve_owner_name dies when gh repo view fails" {
    export GH_STUB_EXIT_repo_view=1
    run_lib 'resolve_owner_name "${script_name}" ""'
    assert_failure 1
    assert_output_contains "test-script: gh repo view failed"
}

@test "resolve_discussion_id returns the node id for a discussion number" {
    run_lib 'resolve_discussion_id "${script_name}" acme widgets 12'
    assert_success
    assert_output_contains "D_stubdiscussion"
    assert_gh_called_with "discussion(number:" "-f owner=acme" "-f name=widgets" "-F number=12"
}

@test "resolve_discussion_id dies when the discussion does not exist" {
    export GH_STUB_RESPONSE_discussionId='{"data":{"repository":{"discussion":null}}}'
    run_lib 'resolve_discussion_id "${script_name}" acme widgets 999'
    assert_failure 1
    assert_output_contains "no discussion found with number 999 in acme/widgets"
}

@test "resolve_discussion_id dies on a GraphQL error response" {
    export GH_STUB_RESPONSE_discussionId='{"errors":[{"message":"Could not resolve to a Repository"}]}'
    run_lib 'resolve_discussion_id "${script_name}" acme widgets 12'
    assert_failure 1
    assert_output_contains "GraphQL error: Could not resolve to a Repository"
}

@test "resolve_discussion_id dies when the gh call itself fails" {
    export GH_STUB_EXIT_discussionId=1
    run_lib 'resolve_discussion_id "${script_name}" acme widgets 12'
    assert_failure 1
    assert_output_contains "gh api graphql (repository.discussion lookup) failed"
}

@test "url_encode_path leaves a plain path untouched" {
    run_lib 'url_encode_path "src/app.py"'
    assert_success
    assert_equal "${output}" "src/app.py"
}

@test "url_encode_path percent-encodes spaces but keeps the separators" {
    run_lib 'url_encode_path "docs/release notes.md"'
    assert_success
    assert_equal "${output}" "docs/release%20notes.md"
}

@test "url_encode_path percent-encodes a '#' so it can't truncate the URL" {
    run_lib 'url_encode_path "docs/c#sharp.md"'
    assert_success
    assert_equal "${output}" "docs/c%23sharp.md"
}

@test "ensure_label creates a missing label" {
    run_lib 'rc=0; ensure_label acme/widgets code-clarification "desc" 0E8A16 || rc=$?; echo "rc=${rc}"'
    assert_success
    assert_output_contains "rc=0"
    assert_gh_called_with "label create code-clarification" "--repo acme/widgets" "-c 0E8A16"
}

@test "ensure_label treats an already-existing label as success and stays quiet" {
    export GH_STUB_LABEL_CREATE=exists
    run_lib 'rc=0; ensure_label acme/widgets code-clarification "desc" 0E8A16 || rc=$?; echo "rc=${rc}"'
    assert_success
    assert_output_contains "rc=0"
    refute_output_contains "warning:"
}

@test "ensure_label warns and returns 1 on a real failure" {
    export GH_STUB_LABEL_CREATE=fail
    run_lib 'rc=0; ensure_label acme/widgets code-clarification "desc" 0E8A16 || rc=$?; echo "rc=${rc}"'
    assert_success
    assert_output_contains "warning: could not create label \"code-clarification\" in acme/widgets"
    assert_output_contains "rc=1"
}
