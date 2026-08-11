# Code-clarification review workflow — reusable prompt

The portable GitHub Actions template in
`github-actions-template/code-clarifications.yml` reads the prompt body from
this file. Copilot app users can instead paste it into `save_workflow` and use
the parameters below.

When using `save_workflow`, **register a cloud/GitHub-hosted workflow, not a
local one.** The Copilot app can save a workflow that only runs while it's
open on this machine — that isn't durable and defeats the point of an
"off-peak, unattended" reviewer. When registering:

1. In the save/schedule dialog, explicitly pick the **cloud** / GitHub-hosted
   execution target (as opposed to "run on this device" or similar local
   option) if the app presents that choice.
2. After saving, verify it: ask the Copilot app to list its saved workflows
   and confirm this one shows a cloud/hosted execution location rather than
   a local device/session binding.
3. If the app only offers a local workflow for this trigger type, use the
   provided GitHub Actions template instead so the reviewer still survives
   this machine being off.

## `save_workflow` parameters

| Field              | Value                                                              |
| ------------------ | ------------------------------------------------------------------ |
| `name`             | `Code clarifications review`                                       |
| `interval`         | `daily` (or `weekly` for low-traffic repos)                        |
| `schedule_hour`    | an off-peak hour, e.g. `3`                                         |
| `mode`             | `autopilot` (must run unattended and post comments without asking) |
| `model`            | `claude-haiku-4.5` (no reasoning effort field — cheapest default)  |
| `reasoning_effort` | omit for `claude-haiku-4.5`; use `low` if using `gpt-5.6-luna`      |
| `prompt`           | the block below                                                    |

Both `claude-haiku-4.5` and `gpt-5.6-luna` are intentionally the smallest
available models — this task is repetitive, well-scoped, and doesn't need a
frontier model. Re-evaluate per-repo if answers come back too shallow.

## Prompt body

This prompt text orchestrates the deterministic helper scripts in
`copilot/clarifications/scripts/` — the agent should call those scripts
for every `gh`/GraphQL interaction and focus only on judgment work (reading
code, classifying patterns, writing answer text).

````
You are reviewing "code-clarification" Q&A discussions in this repository.
Work in small batches to keep token usage low — process at most 5 discussions
per run; anything left over will be picked up on the next scheduled run.

The helper scripts you'll call are in `copilot/clarifications/scripts/`
(relative to the repo root). All scripts print their `--help` text when
invoked with `--help` or `-h`.

0. Guard: run `copilot/clarifications/scripts/check-discussions-enabled.sh --require`.
   If it exits non-zero, stop immediately — GitHub Discussions is disabled
   for this repository.

1. New questions (no bot answer yet):
   a. List candidates by calling
      `copilot/clarifications/scripts/list-new.sh`
      (defaults to `--limit 5`; override if needed). This outputs JSON:
      an array of objects with `number`, `title`, `url`, and `body` fields.
   b. For each discussion in the list:
      i.   Read the `body` field (see question-template.md for the expected
           shape): file path, line range, commit SHA, permalink, code
           snippet, and context.
      ii.  Try to find the current location of the snippet: check the
           referenced file/line first; if it has moved or the file no longer
           exists, search the repo for the exact snippet text (or a close
           match) to relocate it. If it truly cannot be found, say so
           explicitly and answer from the snippet alone.
      iii. Read enough surrounding code/tests/docs to explain what the
           snippet does and why it is written that way. Look for related
           tests, comments, commit history (`git log -L` / `git blame`), or
           upstream library docs if the pattern comes from a dependency.
      iv.  Classify it as a common pattern, an anti-pattern, a repo-specific
           idiom, or "unclear" if you are not confident — do not guess with
           high confidence.
      v.   Write the answer using answer-template.md, filling in the model id
           you are running as and including a confidence rating
           (High/Medium/Low). Save the rendered answer body to a temporary
           file (e.g. `/tmp/answer-<discussion-number>.md`).
      vi.  Post the answer by calling
           `copilot/clarifications/scripts/post-answer.sh <discussion-number> <body-file>`
           This prints the resulting comment id to stdout on success.
           Capture that comment id for the next step.
      vii. Mark the comment as the accepted answer by calling
           `copilot/clarifications/scripts/mark-answered.sh <comment-id>`
           (using the comment id from the previous step).
      viii.Add the `bot-answered` label by calling
           `copilot/clarifications/scripts/label-answered.sh <discussion-number>`

2. Follow-up requests (already answered, but with new human replies since):
   a. List candidates by calling
      `copilot/clarifications/scripts/list-followups.sh`
      (defaults to `--limit 5`; override if needed). This outputs JSON:
      an array of objects with `number`, `title`, and `url` fields.
   b. For each discussion in the list:
      i.   Inspect the thread by calling
           `copilot/clarifications/scripts/show-discussion-thread.sh <discussion-number>`
           This outputs JSON with a `comments` array (oldest first), where
           each comment has `body`, `author.login`, and `createdAt` fields.
      ii.  Judge whether the last comment is from a human (not the bot's
           🤖-prefixed comment) and asks for more detail (e.g. "explain
           more", "can you elaborate", a clarifying follow-up question).
           This judgment call is yours — the script does not make it for you.
      iii. If yes: write a deeper answer using followup-template.md (minimal
           working example + more detailed explanation + confidence rating),
           save it to a temporary file, and post it by calling
           `copilot/clarifications/scripts/post-answer.sh <discussion-number> <body-file>`
           Do NOT call `mark-answered.sh` again for follow-ups — the
           discussion's answered state is already set from step 1.

3. Do not create, edit, or close discussions beyond what's described above.
   Do not modify repo code. This workflow only reads code and posts
   discussion comments/labels via the helper scripts.
````
