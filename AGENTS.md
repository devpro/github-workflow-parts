# github-workflow-parts: agent context

GitHub workflow actions and reusable workflows.

Linux or WSL2, Docker and `bash`.

## Working rules

- **Every command runs in the foreground, and the agent waits for it.**
  No background commands, no subagents, no forks, no parallel tasks, even for a long commands.
- Headers stay: short documentation still has sections.
- Linters for YAML and Markdown are never run by an agent.
- The IstarCI daemon runs the pipeline on every commit by itself, so an agent never starts a run with `istarci run`.
  `istarci wait` waits for the run of `HEAD` and prints the log of each job that failed, and the `pre-push` hook gates a push on it.
- Commit only when asked, and never push.
  Shell scripts are `snake_case` and committed with the executable bit (`git update-index --chmod=+x`).
- Documentation is as short as possible.

## Writing style

Applies to Markdown, code comments, commit messages and prose in scripts.

- **A comment says why, not what, and the why is timeless.**
- **One thought per line.**
  Every sentence starts on its own line, and there is no maximum line length.
- **No em dash, no en dash.**
  A colon, a comma, or a full stop.
- **No second person.**
  "The working tree", not "your working tree"; `<token>`, not `<your-token>`.
