# Repository Workflow

`main` is the single source of truth for this repository.

Before starting ANY coding task:

1. Verify the workspace is based on the latest available `main`.
2. Preserve everything already merged into `main`.
3. Never start new work from a stale Codex branch, old task branch, outdated snapshot, or superseded commit.
4. If GitHub access is available, fetch the latest `main` before making changes.
5. Never overwrite newer `main` files with older workspace versions.
6. Never resurrect code that has already been replaced or removed from `main`.
7. Make task-specific changes only on top of the current `main`.

If the workspace cannot access or verify the latest `main`, STOP. Do not modify files, create commits, or create a PR. Report that the workspace is stale and cannot safely continue.

This rule applies to every task in this repository.
