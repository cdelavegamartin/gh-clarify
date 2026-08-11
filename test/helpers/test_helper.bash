#!/usr/bin/env bash
# Shared setup + assertions for the bats suite. Deliberately self-contained:
# no bats-support/bats-assert dependency, so `bats test/` works with nothing
# but bats-core installed, both locally and in CI.
#
# `status` and `output` are set by bats' own `run` helper in the calling test,
# so shellcheck can't see where they're assigned.
# shellcheck disable=SC2154

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
export REPO_ROOT

# setup_clarify_env -- puts the fake `gh` first on PATH, points the stub at a
# per-test log, and clears every stub knob so tests can't leak into each other.
setup_clarify_env() {
    PATH="${REPO_ROOT}/test/stubs:${PATH}"
    export PATH
    GH_STUB_LOG="${BATS_TEST_TMPDIR}/gh-calls.log"
    export GH_STUB_LOG
    : >"${GH_STUB_LOG}"

    local var
    while read -r var; do
        unset "${var}"
    done < <(compgen -v | grep '^GH_STUB_' | grep -v '^GH_STUB_LOG$' || true)
}

# make_git_fixture_repo [dir] -- creates a real throwaway git repo in the test's
# tmpdir and echoes its path. A real repo (rather than a `git` stub) keeps the
# tests just as deterministic while exercising the actual `git rev-parse` /
# `git show HEAD:<path>` behavior ask.sh depends on, including how git treats
# paths with spaces and `#` in them.
make_git_fixture_repo() {
    local dir="${1:-${BATS_TEST_TMPDIR}/repo}"
    mkdir -p "${dir}/src" "${dir}/docs"
    cat >"${dir}/src/app.py" <<'PY'
def one():
    return 1


def two():
    return 2


def three():
    return 3
PY
    printf 'notes line 1\nnotes line 2\n' >"${dir}/docs/release notes.md"
    printf 'hash line 1\nhash line 2\n' >"${dir}/docs/c#sharp.md"

    git -C "${dir}" init -q -b main
    git -C "${dir}" config user.email "test@example.com"
    git -C "${dir}" config user.name "Test User"
    git -C "${dir}" config commit.gpgsign false
    git -C "${dir}" add -A
    git -C "${dir}" \
        -c "user.name=Test User" -c "user.email=test@example.com" \
        commit -q -m "fixture"
    echo "${dir}"
}

# gh_calls -- prints every recorded `gh` invocation (one collapsed line each).
gh_calls() {
    cat "${GH_STUB_LOG}"
}

# gh_call_count -- number of recorded `gh` invocations.
gh_call_count() {
    if [[ -s "${GH_STUB_LOG}" ]]; then
        wc -l <"${GH_STUB_LOG}" | tr -d ' '
    else
        echo 0
    fi
}

# assert_gh_called_with <substring>... -- passes if a single recorded `gh`
# invocation contains all of the given substrings. Substring matching (against
# the whitespace-collapsed argv) is what keeps these assertions robust to
# harmless GraphQL query reformatting.
assert_gh_called_with() {
    local line
    while IFS= read -r line; do
        local needle matched=true
        for needle in "$@"; do
            if [[ "${line}" != *"${needle}"* ]]; then
                matched=false
                break
            fi
        done
        if [[ "${matched}" == "true" ]]; then
            return 0
        fi
    done <"${GH_STUB_LOG}"
    printf 'expected a gh call containing all of:\n' >&2
    printf '  %s\n' "$@" >&2
    printf 'recorded gh calls:\n' >&2
    sed 's/^/  /' "${GH_STUB_LOG}" >&2
    return 1
}

# refute_gh_called_with <substring>... -- inverse of assert_gh_called_with.
refute_gh_called_with() {
    if assert_gh_called_with "$@" 2>/dev/null; then
        printf 'expected no gh call containing all of:\n' >&2
        printf '  %s\n' "$@" >&2
        return 1
    fi
    return 0
}

# assert_success / assert_failure -- bats-assert-style status checks on $status.
assert_success() {
    if [[ "${status}" -ne 0 ]]; then
        printf 'expected exit status 0, got %s\noutput:\n%s\n' "${status}" "${output}" >&2
        return 1
    fi
}

assert_failure() {
    if [[ "${status}" -eq 0 ]]; then
        printf 'expected a non-zero exit status\noutput:\n%s\n' "${output}" >&2
        return 1
    fi
    if [[ $# -eq 1 && "${status}" -ne "$1" ]]; then
        printf 'expected exit status %s, got %s\noutput:\n%s\n' "$1" "${status}" "${output}" >&2
        return 1
    fi
}

# assert_output_contains <substring> -- checks $output (stdout+stderr as
# captured by bats `run`).
assert_output_contains() {
    if [[ "${output}" != *"$1"* ]]; then
        printf 'expected output to contain:\n  %s\nactual output:\n%s\n' "$1" "${output}" >&2
        return 1
    fi
}

refute_output_contains() {
    if [[ "${output}" == *"$1"* ]]; then
        printf 'expected output NOT to contain:\n  %s\nactual output:\n%s\n' "$1" "${output}" >&2
        return 1
    fi
}

assert_equal() {
    if [[ "$1" != "$2" ]]; then
        printf 'expected: %s\nactual:   %s\n' "$2" "$1" >&2
        return 1
    fi
}
