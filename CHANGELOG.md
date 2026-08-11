# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0/).

Releases are tagged `v<version>` on `main`, since `gh extension install` and
`gh extension upgrade` resolve versions from git tags. The `VERSION` file
(read by `gh clarify --version`) is bumped in the same change as the entry
below, so the tag and the reported version always agree. See
[CONTRIBUTING.md](CONTRIBUTING.md#releasing) for the full procedure.

## [Unreleased]

## [0.1.0]

Initial standalone release: the code-clarification Q&A workflow, previously
carried as loose scripts and personal config, extracted into an installable
`gh` CLI extension.

### Added

- `gh` extension layout — a root `gh-clarify` dispatcher that routes
  `gh clarify <subcommand>` to `cmds/<subcommand>.sh`, with `--help`
  (listing every subcommand) and `--version` (read from `VERSION`).
- Ten subcommands: `ask`, `list-new`, `list-followups`, `post-answer`,
  `mark-answered`, `label-answered`, `show-thread`, `setup-labels`,
  `check-enabled`, and `prompt`. Each has its own `--help`, and the ones
  that talk to GitHub accept `--repo owner/repo`.
- `lib/lib.sh`, shared helpers for error handling, flag parsing, repo and
  discussion resolution, URL encoding, and idempotent label creation.
- Question, answer, and follow-up markdown templates under `templates/`,
  plus `workflow-prompt.md` as the single source of truth for the
  scheduled-review prompt that `gh clarify prompt` prints.
- The `ask-clarification` Agent Skill (`skill/ask-clarification/`),
  registering an `/ask-clarification` slash command that fills in the
  question template — file, line range, commit permalink, and snippet —
  from session context.
- A GitHub Actions template
  (`.github-workflow-template/code-clarifications.yml`) for target repos to
  copy in, running the scheduled reviewer against their own discussions.
- A fully offline, deterministic bats test suite (110 tests) built on a
  fake `gh` stub, and `script/lint`/`script/test` runners.
- CI (`.github/workflows/ci.yml`) running shellcheck + shfmt, the bats
  suite, and a `gh extension install .` smoke test.

[Unreleased]: https://github.com/cdelavegamartin/gh-clarify/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/cdelavegamartin/gh-clarify/releases/tag/v0.1.0
