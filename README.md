# gh-clarify

A [`gh` CLI extension](https://cli.github.com/manual/gh_extension) that
implements a lightweight "I don't understand why this snippet works / is
necessary" Q&A workflow using **GitHub Discussions** — so the answer is
visible to the whole team, doesn't pollute commit history, and can be
answered asynchronously by an agent.

## How it works

1. **Ask**: when something in the code is unclear, `gh clarify ask` opens a
   GitHub Discussion in the **Q&A** category, labeled `code-clarification`,
   using [`templates/question-template.md`](templates/question-template.md).
   It captures the file path, line range, a permalink to the exact commit,
   and a verbatim code snippet — so the question stays answerable even
   after the referenced lines move or get refactored.
2. **Answer**: a small, scheduled agent (see
   [`workflow-prompt.md`](workflow-prompt.md)) reviews unanswered
   `code-clarification` discussions in batches, off-peak, using the
   cheapest available models (`claude-haiku-4.5` or `gpt-5.6-luna`). It
   posts an answer using
   [`templates/answer-template.md`](templates/answer-template.md), including
   a confidence rating, clearly marked with a 🤖 prefix, tagged with the
   `bot-answered` label, and marked as the discussion's accepted answer via
   GitHub's native Q&A "answered" state.
3. **Follow-up**: replying on the thread (e.g. "explain more") gets a deeper
   answer with a minimal working example on the next scheduled run, posted
   from [`templates/followup-template.md`](templates/followup-template.md)
   and including its own confidence rating.

## Install

```bash
gh extension install cdelavegamartin/gh-clarify
```

This makes every subcommand below available as `gh clarify <subcommand>`.
Run `gh clarify --help` for the full subcommand list, or
`gh clarify <subcommand> --help` for a subcommand's own usage.
`gh clarify --version` prints the installed extension version.

## One-time setup in a target repo

1. **Enable Discussions**: repo Settings → General → Features →
   Discussions. Agents should never flip this on unilaterally — see
   [Handling disabled Discussions](#handling-disabled-discussions) below.
2. **Create the two labels** used by this workflow, `code-clarification` and
   `bot-answered`:
   ```bash
   gh clarify setup-labels [--repo owner/repo]
   ```
   It's idempotent (safe to re-run) and defaults to the current directory's
   repo if `--repo` is omitted. This step is optional in practice: `ask` and
   `label-answered` both self-heal by creating their label on the fly the
   first time it's missing, falling back to a warning only if that creation
   also fails (e.g. insufficient permissions).
3. **Confirm the Q&A category exists** (it's created by default when
   Discussions is enabled; rename/create one if a maintainer removed it).
4. **Set up the automated reviewer workflow** using one of these approaches:
   - **GitHub Actions** (recommended, portable): copy
     [`.github-workflow-template/code-clarifications.yml`](.github-workflow-template/code-clarifications.yml)
     to `.github/workflows/code-clarifications.yml` in your target repo:
     ```bash
     mkdir -p .github/workflows
     curl -fsSL https://raw.githubusercontent.com/cdelavegamartin/gh-clarify/main/.github-workflow-template/code-clarifications.yml \
       -o .github/workflows/code-clarifications.yml
     ```
     Review the inline comments, verify the schedule (`cron` expression),
     and keep its explicit `contents: read` and `discussions: write`
     permissions. The workflow installs `gh-clarify` itself and uses the
     built-in `GITHUB_TOKEN` by default, so no repository secret is
     normally needed; see the file's comments if your organization requires
     a separate `COPILOT_CLI_TOKEN` secret.
   - **Copilot app `save_workflow`** (alternative, for app users): use the
     Copilot app's `save_workflow` tool with the parameters and prompt in
     [`workflow-prompt.md`](workflow-prompt.md) — **as a cloud/GitHub-hosted
     workflow**, not a local one tied to a single machine/session. See
     `workflow-prompt.md` for how to verify this after saving.
5. **(Optional) Install the `ask-clarification` Skill** to have an agent
   fill in the question template (permalink, snippet, current commit)
   instead of doing it by hand:
   ```bash
   gh skill install cdelavegamartin/gh-clarify ask-clarification
   ```
   This installs [`skill/ask-clarification`](skill/ask-clarification) and
   registers a reliable `/ask-clarification` trigger (see [Asking via the
   `/ask-clarification` command](#asking-via-the-ask-clarification-command)
   below). Verified against `gh skill install --help` (gh v2.96.0): it
   supports installing directly from a remote repository
   (`gh skill install owner/repo skill-name`), not just `--from-local`.

## Asking via the `/ask-clarification` command

Once the `ask-clarification` skill is installed, trigger it with a slash
command instead of relying on the agent to infer intent from prose:

```
/ask-clarification why do we use X instead of Y here?
/ask-clarification why do we use X instead of Y in path/to/file.py 200:230
```

- With a trailing `in <file> <start>[:<end>]`, the file/line range is parsed
  directly.
- Without it, the agent infers the file/line from whatever's already in the
  conversation (a file just discussed, a selection, an attachment) and asks
  you only if it can't confidently determine them.

The skill registers `/ask-clarification` as a native slash command that agents
discover from the `SKILL.md` description and argument-hint. Hosts that render
slash command completion (e.g. the Copilot CLI TUI with experimental mode
enabled) offer it in autocomplete; in other hosts, agents match it via
natural-language intent from the description.

Or invoke the extension directly without the skill:

```bash
gh clarify ask --file-path path/to/file.py --start-line 200 --end-line 230 \
  --title "Why X instead of Y here?" \
  --context "Reviewing this during a merge and the approach is unclear."
```

**Checking what's loaded**: run `/env` in an interactive Copilot CLI session
to list loaded instructions, MCP servers, skills, agents, hooks, plugins,
LSPs, and extensions — use it to confirm `ask-clarification` is picked up
after installing or editing the skill.

## Handling disabled Discussions

Before creating a discussion or registering the reviewer workflow, always
check first:

```bash
gh clarify check-enabled --verbose
```

- **`true`** → proceed normally.
- **`false`**, and the user wants to use this workflow → tell them
  Discussions needs to be enabled (repo Settings → General → Features →
  Discussions) and stop; don't flip the setting via the API yourself even
  if you technically have permission — it's a repo-wide, human-visible
  setting change a maintainer should make deliberately.
- **`false`**, and the user (as a maintainer) explicitly says Discussions
  will stay disabled for this repo → don't ask again. Add a short note to
  *that repo's own* `.github/copilot-instructions.md` (not this personal
  config), e.g.:
  ```markdown
  - **Code-clarification-via-Discussions workflow is not available here**:
    GitHub Discussions is disabled for this repo. Don't suggest filing
    `code-clarification` discussions; use inline comments/TODOs instead.
  ```

## Why a skill for asking, and a workflow for answering (not an MCP server)

- **Asking** is bursty, interactive, and needs local context (current file,
  line, commit, git remote) — a good fit for an **Agent Skill** invoked
  ad hoc during a normal session. See
  [`skill/ask-clarification`](skill/ask-clarification).
- **Answering** is a single repeatable, schedulable task with no need for
  interactive back-and-forth — a good fit for the app's native **scheduled
  Workflow** feature (`save_workflow`/`run_workflow`), which already gives
  us async execution, batching via the prompt, model selection, and
  off-peak scheduling for free. **The answering workflow deliberately does
  NOT become its own Skill** because: (a) there's no natural user-facing
  slash command trigger (it runs on a schedule, not ad hoc); (b) it's
  already deliverable via `save_workflow` in the Copilot app, or via a
  GitHub Actions workflow that feeds the prompt text from
  `gh clarify prompt` directly to a headless Copilot CLI invocation.
- An **MCP server** would add another moving part (a long-running process,
  auth/config to maintain) without buying anything `gh` + `gh api graphql`
  don't already provide — discussion CRUD, labels, and marking an answer
  are all reachable with the GitHub CLI that's already authenticated in
  every session. Revisit MCP only if this grows to need cross-repo state
  (e.g. a shared index of open questions) that `gh` searches can't express.

## GitHub Discussions CLI and GraphQL usage

The subcommands use the preview `gh discussion`/`gh repo view` commands for
listing, viewing, and labeling discussions where possible, falling back to
`gh api graphql` where the CLI doesn't expose the required response or
mutation: `createDiscussion`, `addDiscussionComment`,
`markDiscussionCommentAsAnswer`, and `addLabelsToLabelable`.

Two `gh api graphql` gotchas worth remembering when editing these calls:

- `-f name=value` sends the variable as a **raw string** (no `@file`
  expansion, no type coercion) — use it for ids, titles and bodies.
- List variables such as `[ID!]!` need the repeated-array form
  `-F 'labelIds[]=<id>'`; `-f labelIds=<id>` sends a plain string and the
  mutation is rejected.

## Subcommands

| Subcommand | Description |
| --- | --- |
| `ask` | File a code-clarification Q&A discussion for a snippet |
| `list-new` | List unanswered code-clarification discussions as JSON |
| `list-followups` | List bot-answered discussions that may need a follow-up |
| `post-answer` | Post an answer/follow-up comment on a discussion |
| `mark-answered` | Mark a comment as the discussion's accepted answer |
| `label-answered` | Add the `bot-answered` label to a discussion |
| `show-thread` | Show a discussion's full comment thread as JSON |
| `setup-labels` | Idempotently create the `code-clarification`/`bot-answered` labels |
| `check-enabled` | Check whether GitHub Discussions is enabled for a repo |
| `prompt` | Print the scheduled-review prompt body (for CI/`save_workflow`) |

## Repository layout

```
gh-clarify                       root dispatcher (gh clarify <subcommand>)
lib/lib.sh                        shared helpers
cmds/*.sh                         one script per subcommand
templates/*.md                    question/answer/follow-up templates
workflow-prompt.md                source of truth for `gh clarify prompt`
.github-workflow-template/        template to copy into a target repo's .github/workflows/
skill/ask-clarification/          Agent Skill for /ask-clarification
```

## Development

Shellcheck/shfmt/bats tooling and a `CONTRIBUTING.md` guide are being added
in a follow-up PR (see the project's PR history for progress).
