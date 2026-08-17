---
name: ask-clarification
description: 'File a code-clarification GitHub Discussion when something in the code is unclear (why a snippet works, why it is necessary, why we use approach X instead of Y). Creates a Q&A discussion with the "code-clarification" label, including a permalink pinned to the current commit and a verbatim code snippet so the question stays answerable even if the lines move later.'
argument-hint: '<question> [in <file> <start>[:<end>]]'
---

# ask-clarification

File a code-clarification GitHub Discussion about a confusing code snippet.

## When to invoke

Use this skill when:
- You encounter code whose purpose or implementation is unclear (why it works, why it's necessary, why approach X is used instead of Y)
- You're reviewing or merging code and something doesn't make sense
- You want to document a question for the whole team instead of just leaving an inline comment/TODO

**Do not guess or leave it unresolved** — file a discussion so the answer is visible and searchable for everyone.

## Usage

```
/ask-clarification <question> [in <file> <start>[:<end>]]
```

**Examples:**
```
/ask-clarification why do we use X instead of Y here?
/ask-clarification why do we call advance() instead of the model directly in src/utils.ts 200:230
```

### Parsing the location

- **With explicit location** (`in <file> <start>[:<end>]`): parse it directly from the command.
- **Without explicit location**: infer the file and line range from the conversation context:
  - A file just discussed, viewed, or edited in recent turns
  - A file attachment
  - A selection the user made
  - Only ask the user to specify the file/line if you cannot confidently determine them from context.

### Strip the trailing `?` if present

The question may end with `?` — strip it when extracting the question text (the `gh clarify ask` command and GraphQL mutation don't need it).

## How it works

1. **Parse** the question and optional location from the command arguments.
2. **Infer missing location** from conversation context if not provided inline (file recently discussed/attached, etc.).
3. **Prerequisite**: the `gh-clarify` extension must be installed (`gh extension install cdelavegamartin/gh-clarify`) so `gh clarify` is available on `PATH`. If `gh clarify --help` fails, stop and tell the user to install it first.
4. **Call the command**: `gh clarify ask --file-path <path> --start-line <n> [--end-line <n>] --title <title> --context <text>` (see [Arguments](#arguments) below).
5. **Report the result** back to the user:
   - If successful: show the discussion URL
   - If Discussions is disabled: relay the message exactly as the command prints it (tell the user to enable Discussions or note it in the repo's `.github/copilot-instructions.md`)
   - If the Q&A category is missing: relay the message exactly (tell the user to create one)
   - If the command fails for another reason: show the error message

## Arguments

Pass the following flags to `gh clarify ask`:

- `--file-path <path>` — path to the file, relative to the repo root (or absolute, as long as it resolves inside the repo)
- `--start-line <n>` — first line of the snippet (1-based)
- `--end-line <n>` — last line of the snippet (1-based); defaults to `--start-line` if omitted
- `--title <title>` — terse, clear question title (also the discussion title)
- `--context <text>` — why you were looking at this and what's unclear (include relevant background from the conversation)
- `--repo-path <path>` — optional; path to the repo (defaults to the current working directory)

### Boundary checks and guards (already in `gh clarify ask`)

The command already implements:
- **Repo boundary check**: `--file-path` must resolve to a file inside the repo root (rejects `..` escapes)
- **Discussions-disabled guard**: checks `gh repo view --json hasDiscussionsEnabled` first and exits with a message if `false`
- **Q&A category check**: ensures a Q&A discussion category exists before trying to create the discussion
- **Permalink generation**: builds a stable `https://github.com/<owner>/<repo>/blob/<sha>/<path>#L<start>-L<end>` URL
- **Label best-effort application**: tries to apply the `code-clarification` label if it exists; warns if it doesn't, but doesn't fail the whole operation

You do **not** need to reimplement any of this logic — just call the command and relay its output.

## Behavior guarantees

- **Slash command**: registered as `/ask-clarification` (native command with autocomplete in hosts that support it)
- **Location parsing**: supports `in <file> <start>[:<end>]` with `-` or `:` as the separator
- **Location inference**: when not given inline, infers from conversation context (recently discussed/attached files)
- **Discussions guard**: never creates anything if Discussions is disabled; tells the user to enable it or document the exception
- **Q&A category guard**: never creates anything if the Q&A category is missing; tells the user to create one
- **Permalink stability**: uses the current commit SHA, not a branch name
- **Code snippet**: reads the file content at HEAD and includes the exact lines
- **Label best-effort**: applies `code-clarification` label if it exists, warns if not, but doesn't fail
- **Session cwd awareness**: resolves the target repo from the calling session's working directory via `--repo-path` (defaults to cwd), not from the installed Skill directory

`gh clarify ask` handles the repository and GitHub operations, so this Skill's
job is to parse the command, infer missing context, and invoke the extension
with the right flags.
