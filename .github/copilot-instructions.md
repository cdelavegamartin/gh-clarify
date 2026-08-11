# Copilot instructions for `gh-clarify`

A [`gh` CLI extension](https://cli.github.com/manual/gh_extension) written
entirely in Bash. There is no build step — the checked-out repo *is* the
artifact users install, so a broken file on `main` is a broken install.

[`CONTRIBUTING.md`](../CONTRIBUTING.md) is the detailed reference (layout,
tooling versions, adding a subcommand, release process). This file is the
short version plus the things that are easy to get wrong.

## Always do this

- Run `script/lint` and `script/test` before proposing a change. CI runs
  these exact scripts, so green locally means green in CI. Don't hand-roll
  `shellcheck`/`shfmt`/`bats` invocations — the flags live in `script/lint`
  so local and CI can't drift.
- Keep `shellcheck -S warning` clean. Fix the finding; don't lower the
  severity or scatter `# shellcheck disable=` to silence it. A disable
  comment needs a one-line reason above it.
- Add or update bats coverage for any behavior change.

## Tests must stay offline and deterministic

The suite never touches the network, never needs a token, and never mutates
real GitHub state.

- `test/stubs/gh` is a fake `gh` placed first on `PATH`. If you add a call it
  doesn't recognize, **extend the stub** — never let a test reach real
  GitHub, even read-only.
- Match on distinctive substrings (a GraphQL operation name, a `-f`/`-F`
  variable name, a subcommand), never whole-query equality, so reformatting
  a query doesn't break the suite.
- `git` is deliberately *not* stubbed: `cmds/ask.sh` shells out to it, so its
  tests build a real throwaway repo in the test's tmpdir. Follow that pattern
  when you need real git behavior.

## Conventions that bite

- **Help text is generated from the file header.** Each script's `-h|--help`
  reprints its own `# Usage:` comment block via a shared `sed` idiom. Write
  flag documentation once, in the header — never as a separate string, or the
  two will disagree.
- **New subcommands must be registered** in the `subcommands` list in the
  root `gh-clarify` dispatcher. `test/dispatcher.bats` asserts that list
  matches `cmds/*.sh`, so skipping this fails the suite.
- **`gh api graphql` argument forms**: `-f name=value` sends a raw string
  (use it for ids, titles, bodies); list variables like `[ID!]!` need the
  repeated-array form `-F 'labelIds[]=<id>'` — `-f labelIds=<id>` sends a
  plain string and the mutation is rejected.
- **`.github-workflow-template/` is for *other* repos**, not this one. It's
  deliberately not under `.github/workflows/` so it doesn't run here. This
  repo's own CI is `.github/workflows/ci.yml`.
- **Don't bump `VERSION` or push tags** as part of a feature change.
  Releasing is a maintainer action; see CONTRIBUTING's "Releasing".

## Commits

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/),
small and single-purpose — one logical change per commit, never a lint fix
plus a feature plus a doc update bundled together. Purely formatting changes
(whitespace, wrapping, `shfmt` output) use `style:`. Branches mirror the
type: `feat/<slug>`, `fix/<slug>`, `docs/<slug>`, `test/<slug>`,
`ci/<slug>`, `chore/<slug>`. Open pull requests against `main`.

## Filing clarification questions here

This repo has Discussions enabled and dogfoods its own workflow: if something
in the code is genuinely unclear, file a clarification discussion with
`gh clarify ask` rather than guessing or leaving a `TODO`.
