# Contributing to gh-clarify

`gh-clarify` is a [`gh` CLI extension](https://cli.github.com/manual/gh_extension)
written entirely in Bash. There's no build step: the repo you check out is
the artifact users install.

## Repository layout

```
gh-clarify                        root dispatcher (gh clarify <subcommand>)
lib/lib.sh                        shared helpers (die, flag parsing, GraphQL plumbing)
cmds/*.sh                         one script per subcommand
templates/*.md                    question/answer/follow-up templates
workflow-prompt.md                source of truth for `gh clarify prompt`
.github-workflow-template/        template to copy into a target repo's .github/workflows/
skill/ask-clarification/          Agent Skill for /ask-clarification
script/lint, script/test          local lint/test runners (CI runs these same scripts)
test/                             bats suite, fake `gh` stub and helpers
VERSION                           version reported by `gh clarify --version`
```

## Running the checks locally

```bash
script/lint          # shellcheck, then shfmt in diff mode
script/lint --fix    # rewrite files with shfmt instead of just reporting
script/test          # the whole bats suite
script/test test/ask.bats
script/test -f "permalink"
```

`.github/workflows/ci.yml` runs these exact scripts, so a green local run
means a green CI run. The scripts own the tool flags and file lists so the
two can't drift apart.

### Tooling

- **shellcheck** at `-S warning` with `-x` (so it follows `source` into
  `lib/lib.sh`). Preinstalled on GitHub's `ubuntu-latest` runners.
- **shfmt** `v3.12.0` (the version CI pins). Install with
  `go install mvdan.cc/sh/v3/cmd/shfmt@latest` or grab a
  [release binary](https://github.com/mvdan/sh/releases).
- **[bats-core](https://github.com/bats-core/bats-core)** `v1.14.0` (the
  version CI pins). Install without root:
  ```bash
  git clone --depth 1 --branch v1.14.0 \
    https://github.com/bats-core/bats-core.git /tmp/bats-core
  /tmp/bats-core/install.sh "${HOME}/.local"   # then ensure ~/.local/bin is on PATH
  ```
  `npm install -g bats` also works if you have node and root.

### The shfmt flags

`script/lint` runs shfmt with `-i 4 -ci -bn`:

- `-i 4` — 4-space indentation, matching the existing scripts.
- `-ci` — indent `case` branches, so the bodies of the argument-parsing
  `case` statements every subcommand uses line up under their patterns.
- `-bn` — keep binary operators (`&&`, `||`) at the end of a line rather
  than the start of the next, which is how the multi-line `gh api graphql`
  calls and their `|| die ...` fallbacks are already written.

`.bats` files are formatted with the same flags plus `-ln bats`.

## Adding a new subcommand

1. Create `cmds/<name>.sh`, executable (`chmod +x`), starting from the
   shape of an existing one (`cmds/label-answered.sh` is the smallest):
   ```bash
   #!/usr/bin/env bash
   # One-line description of what this does.
   #
   # Usage: gh clarify <name> <args> [--repo owner/repo] [-h|--help]
   set -euo pipefail

   script_name="$(basename "$0")"
   # shellcheck source=../lib/lib.sh
   source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"
   ```
2. Keep the `# Usage:` header convention. `-h|--help` prints it with the
   shared idiom, which echoes the comment block from `# Usage:` up to
   `set -euo pipefail`:
   ```bash
   sed -n '/^# Usage:/,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
   ```
   That means the help text and the source comment can't disagree — write
   the flag documentation once, in the header.
3. Reuse `lib/lib.sh` rather than reimplementing: `die`,
   `check_graphql_errors`, `parse_repo_flag`,
   `parse_repo_and_limit_flags`, `resolve_owner_name`,
   `resolve_discussion_id`, `url_encode_path`, `ensure_label`. Each is
   documented above its definition.
4. Register it in the `subcommands` list in the root `gh-clarify`
   dispatcher, as `<name>:<one-line description>`, in display order. This
   is not optional: `test/dispatcher.bats` has a test asserting the usage
   output lists every script in `cmds/*.sh`, so an unregistered subcommand
   fails the suite.
5. Add bats coverage in `test/cmds.bats` (or a dedicated file for anything
   substantial, as `test/ask.bats` does). Cover at least the happy path,
   `--help`, and the failure modes the script dies on.
6. Add a row to the subcommand table in `README.md`.

## Tests must stay offline and deterministic

The suite never touches the network, never needs a token, and never mutates
real GitHub state. Keep it that way:

- `test/stubs/gh` is a fake `gh` placed first on `PATH`. It dispatches on
  distinctive substrings (a GraphQL operation name, a `gh` subcommand)
  rather than whole-query equality, and records every invocation for the
  assertion helpers. Scenarios are selected with environment variables
  (`GH_STUB_RESPONSE_<key>`, `GH_STUB_EXIT_<key>`, `GH_STUB_REPO_JSON`,
  `GH_STUB_LABEL_CREATE`), documented at the top of the stub.
- If a new subcommand makes a call the stub doesn't know about, **extend
  the stub** — never let a test reach real GitHub.
- `git` is not stubbed: `cmds/ask.sh` shells out to it, so its tests build
  a real throwaway repo in the test's tmpdir. Follow that pattern if you
  need git behavior.
- `test/helpers/test_helper.bash` carries its own small assertions, so the
  suite depends on nothing beyond bats-core itself.

## Commits and branches

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/),
small and single-purpose. One logical change per commit — don't bundle a
lint fix, a feature and a doc update together.

Types in use: `feat:`, `fix:`, `docs:`, `test:`, `ci:`, `chore:`,
`refactor:`, and `style:` for changes that are purely formatting
(whitespace, wrapping, quoting, `shfmt` output) with no behavior change.

Branch names mirror the type: `feat/<slug>`, `fix/<slug>`, `docs/<slug>`,
`test/<slug>`, `ci/<slug>`, `chore/<slug>`.

Open pull requests against `main`. Run `script/lint` and `script/test`
before opening one.

## Releasing

`gh extension install` and `gh extension upgrade` resolve versions from git
tags, while `gh clarify --version` reads the `VERSION` file — so the two
must be bumped together, or an installed extension will report a version it
isn't. Versioning is [semver](https://semver.org/).

To cut a release:

1. Bump `VERSION` to the new version.
2. Add the matching entry to [`CHANGELOG.md`](CHANGELOG.md).
3. Merge that to `main`.
4. Tag the merge commit `v<version>` (e.g. `v0.2.0`) and push the tag:
   ```bash
   git tag -a v0.2.0 -m "v0.2.0"
   git push origin v0.2.0
   ```

Tagging is a maintainer action — don't push release tags as part of a
feature pull request.
