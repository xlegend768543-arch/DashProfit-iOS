---
name: standup
description: Write a standup update (yesterday, today, blockers) for this repo from the user's recent AI coding sessions, the commits they produced and open TODOs in their Callimachus index.
argument-hint: "[days to cover, default 1]"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh:*), Bash(git log:*)
---

Days to cover: $ARGUMENTS

If no number was given, cover the last working day: since Friday morning on a Monday, otherwise the last 24 hours.

## Gather

Run these in parallel from the repo (`@repo` is replaced with this repo's name):

- `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh recent -p @repo -n 25`: recent sessions in this repo, newest first
- `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh commits -n 20`: commits those sessions produced
- `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh todos -p @repo -n 15`: open TODOs
- `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh issues @repo -n 5`: recurring errors
- `git log --since="<start of window>" --no-merges --format="%h %ad %s" --date=short -n 40`: everything committed, including work done without an agent

Keep only what falls inside the window. For a session whose title doesn't say what got done, run `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh knowledge <thread-id>`, at most four times.

If any line starts with `callimachus-kit:`, cal is missing or failed: pass the message on, then write the standup from `git log` alone and say so.

## Write

Plain language for teammates: no thread ids in the bullets, and at most about 10 bullets in all.

```
**Yesterday**
- <what got done, grouped by goal rather than by session>

**Today**
- <open TODOs and unfinished work from the last sessions>

**Blockers**
- <a recurring error with no fix, or work that stopped on a failure; otherwise "None">
```

After the block, list the sources (thread ids and short shas) on one line, so the user can check any bullet.
