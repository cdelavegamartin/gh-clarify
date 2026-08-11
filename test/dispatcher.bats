#!/usr/bin/env bats
# Tests for the root `gh-clarify` dispatcher: usage, version, and how it
# routes (or refuses) subcommands.

load helpers/test_helper

setup() {
    setup_clarify_env
}

@test "no arguments prints usage and the subcommand list" {
    run "${REPO_ROOT}/gh-clarify"
    assert_success
    assert_output_contains "Usage: gh clarify <subcommand>"
    assert_output_contains "Subcommands:"
    assert_output_contains "ask"
    assert_output_contains "list-followups"
    assert_output_contains "prompt"
}

@test "--help and -h both print usage and exit 0" {
    run "${REPO_ROOT}/gh-clarify" --help
    assert_success
    assert_output_contains "Subcommands:"

    run "${REPO_ROOT}/gh-clarify" -h
    assert_success
    assert_output_contains "Subcommands:"
}

@test "usage lists every subcommand that has a script in cmds/" {
    run "${REPO_ROOT}/gh-clarify" --help
    assert_success
    local script
    for script in "${REPO_ROOT}"/cmds/*.sh; do
        local name
        name="$(basename "${script}" .sh)"
        assert_output_contains "  ${name}"
    done
}

@test "--version prints the VERSION file contents" {
    run "${REPO_ROOT}/gh-clarify" --version
    assert_success
    assert_output_contains "gh-clarify $(cat "${REPO_ROOT}/VERSION")"
}

@test "an unknown subcommand exits non-zero and prints usage" {
    run "${REPO_ROOT}/gh-clarify" not-a-subcommand
    assert_failure 1
    assert_output_contains "gh-clarify: unknown subcommand: not-a-subcommand"
    assert_output_contains "Subcommands:"
}

@test "a known subcommand is dispatched to its script in cmds/" {
    run "${REPO_ROOT}/gh-clarify" check-enabled
    assert_success
    assert_equal "${output}" "true"
    assert_gh_called_with "repo view" "--json hasDiscussionsEnabled,nameWithOwner"
}

@test "arguments after the subcommand are forwarded verbatim" {
    run "${REPO_ROOT}/gh-clarify" check-enabled --repo other/repo
    assert_success
    assert_gh_called_with "repo view" "other/repo"
}
