# Code-clarification discussions workflow

A lightweight way to track "I don't understand why this snippet works /
is necessary" questions while merging or reviewing code, using **GitHub
Discussions** instead of a local notes file — so the answer is visible to
the whole team, doesn't pollute commit history, and can be answered
asynchronously by an agent.

This folder is symlinked to `$HOME/.copilot/clarifications` (see the repo
README's `### Copilot` section) so it's available from any repo/session.

## How it works

1. **Ask**: when something in the code is unclear, open a GitHub Discussion
   in the **Q&A** category, labeled `code-clarification`, using
   [`question-template.md`](./question-template.md). It captures the file
   path, line range, a permalink to the exact commit, and a verbatim code
   snippet — so the question stays answerable even after the referenced
   lines move or get refactored.
2. **Answer**: a small, scheduled agent (see [`workflow-prompt.md`](./workflow-prompt.md))
   reviews unanswered `code-clarification` discussions in batches, off-peak,
   using the cheapest available models (`claude-haiku-4.5` or
   `gpt-5.6-luna`). It posts an answer using
   [`answer-template.md`](./answer-template.md), including a confidence
   rating, clearly marked with a
   🤖 prefix, tagged with the `bot-answered` label, and marked as the
   discussion's accepted answer via GitHub's native Q&A "answered" state.
3. **Follow-up**: replying on the thread (e.g. "explain more") gets a
   deeper answer with a minimal working example on the next scheduled run,
   posted from [`followup-template.md`](./followup-template.md) and including
   its own confidence rating.

## One-time setup in a target repo

1. **Enable Discussions**: repo Settings → General → Features →
   Discussions. Agents should never flip this on unilaterally — see
   [Handling disabled Discussions](#handling-disabled-discussions) below.
2. **Create the two labels** used by this workflow, `code-clarification` and
   `bot-answered`, by running [`scripts/setup-labels.sh`](./scripts/setup-labels.sh):
   ```bash
   ./scripts/setup-labels.sh [--repo owner/repo]
   ```
   It's idempotent (safe to re-run) and defaults to the current directory's
   repo if `--repo` is omitted. Equivalent manual commands, if you'd rather
   not run the script:
   ```bash
   gh label create code-clarification -d "Clarification question for Copilot agents" -c "0E8A16"
   gh label create bot-answered -d "Answered by a Copilot agent" -c "5319E7"
   ```
   This step is optional in practice: `create-clarification-discussion.sh`
   and `label-answered.sh` both self-heal by creating their label on the fly
   the first time it's missing, falling back to a warning (with the manual
   command above) only if that creation also fails (e.g. insufficient
   permissions).
3. **Confirm the Q&A category exists** (it's created by default when
   Discussions is enabled; rename/create one if a maintainer removed it).
4. **Vendor the workflow assets** into the target repo. Run this from the
   target repo, replacing the source path if this config checkout lives
   elsewhere:
   ```bash
   mkdir -p copilot/clarifications
   cp -R $HOME/config-files/copilot/clarifications/. copilot/clarifications/
   ```
   Commit the copied files so hosted runners can access the scripts, prompt,
   and templates. `gh skill install` does not perform this step: it discovers
   and copies Agent Skills with a `SKILL.md`, while this directory contains
   the shared workflow assets.
5. **Set up the automated reviewer workflow** using one of these approaches:
   - **GitHub Actions** (recommended, portable): Copy
     [`github-actions-template/code-clarifications.yml`](./github-actions-template/code-clarifications.yml)
     to `.github/workflows/code-clarifications.yml` in your target repo
     (must be copied, not symlinked — GitHub Actions only runs workflows
     from that exact path):
     ```bash
     mkdir -p .github/workflows
     cp copilot/clarifications/github-actions-template/code-clarifications.yml .github/workflows/code-clarifications.yml
     ```
     Review the inline comments, verify the schedule
     (`cron` expression), and keep its explicit `contents: read` and
     `discussions: write` permissions. The workflow uses the built-in
     `GITHUB_TOKEN` by default, so no repository secret is normally needed;
     see the file's comments if your organization requires a separate
     `COPILOT_CLI_TOKEN` secret.
   - **Copilot app `save_workflow`** (alternative, for app users): Use the
     Copilot app's `save_workflow` tool with the parameters and prompt in
     [`workflow-prompt.md`](./workflow-prompt.md) — **as a cloud/GitHub-hosted
     workflow**, not a local one tied to a single machine/session. See
     `workflow-prompt.md` for how to verify this after saving.
6. **(Optional) Install the `ask-clarification` Skill** to have an agent fill
   in the question template (permalink, snippet, current commit) instead of
   doing it by hand:
   ```bash
   gh skill install $HOME/config-files/copilot ask-clarification --from-local --scope user
   ```
   This installs [`../skills/ask-clarification`](../skills/ask-clarification)
   and registers a reliable `/ask-clarification` trigger (see [Asking via the
   `/ask-clarification` command](#asking-via-the-ask-clarification-command)
   below).

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
slash command completion (e.g. the Copilot CLI TUI with experimental mode enabled)
offer it in autocomplete; in other hosts, agents match it via natural-language
intent from the description.

**Checking what's loaded**: run `/env` in an interactive Copilot CLI session
to list loaded instructions, MCP servers, skills, agents, hooks, plugins,
LSPs, and extensions — use it to confirm `ask-clarification` is picked up
after installing or editing the skill.

## Handling disabled Discussions

Before creating a discussion or registering the reviewer workflow, always
check first:

```bash
gh repo view --json hasDiscussionsEnabled -q .hasDiscussionsEnabled
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
  [`../skills/ask-clarification`](../skills/ask-clarification).
- **Answering** is a single repeatable, schedulable task with no need for
  interactive back-and-forth — a good fit for the app's native **scheduled
  Workflow** feature (`save_workflow`/`run_workflow`), which already gives
  us async execution, batching via the prompt, model selection, and
  off-peak scheduling for free. **The answering workflow deliberately does
  NOT become its own Skill** because: (a) there's no natural user-facing
  slash command trigger (it runs on a schedule, not ad hoc); (b) it's
  already deliverable via `save_workflow` in the Copilot app, or via a
  GitHub Actions workflow that feeds the prompt text from
  `workflow-prompt.md` directly to a headless Copilot CLI invocation.
- An **MCP server** would add another moving part (a long-running process,
  auth/config to maintain) without buying anything `gh` + `gh api graphql`
  don't already provide — discussion CRUD, labels, and marking an answer
  are all reachable with the GitHub CLI that's already authenticated in
  every session. Revisit MCP only if this grows to need cross-repo state
  (e.g. a shared index of open questions) that `gh` searches can't express.

## GitHub Discussions CLI and GraphQL usage

The helper scripts use the preview `gh discussion` commands for listing,
viewing, and labeling discussions. They use `gh api graphql` where the CLI
doesn't expose the required response or mutation: `createDiscussion`,
`addDiscussionComment`, `markDiscussionCommentAsAnswer`, and
`addLabelsToLabelable`.

Two `gh api graphql` gotchas worth remembering when editing these calls:

- `-f name=value` sends the variable as a **raw string** (no `@file`
  expansion, no type coercion) — use it for ids, titles and bodies.
- List variables such as `[ID!]!` need the repeated-array form
  `-F 'labelIds[]=<id>'`; `-f labelIds=<id>` sends a plain string and the
  mutation is rejected.
