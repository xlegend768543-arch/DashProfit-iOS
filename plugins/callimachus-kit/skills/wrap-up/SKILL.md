---
name: wrap-up
description: At the end of a session, save what it settled into this repo's Callimachus memory (decisions with their reasons, gotchas) and close the TODOs it finished, after the user picks which to keep.
argument-hint: "[anything to make sure is saved]"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh:*)
---

Also make sure to cover: $ARGUMENTS

## 1. Draft

Go back over this conversation and draft:

- **Decisions:** choices made, each with the reason ("Use X for Y because Z").
- **Gotchas:** surprising facts that cost time, each with how to avoid it next time.
- **Finished TODOs:** tracked work this session completed.

Keep only facts that are durable and specific to this repo. Leave out anything obvious from reading the code, one-off details, and anything secret (keys, tokens, passwords, personal data). Write each one so it makes sense to someone with no memory of this session.

## 2. Check against memory

`@repo` is replaced with this repo's name. Run these in parallel:

- `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh memory -n 50`: this repo's saved decisions and gotchas, with their ids. Give it no project argument; it defaults to the current repo.
- For each decision: `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh check "<decision>" -p @repo`, which also finds decisions worded differently once the semantic index exists.
- `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh todos -p @repo -n 30`, to find the ids of the TODOs that got finished.

Drop any draft that repeats a fact already saved. If a decision reverses a live one, note that fact's id, to pass as `--replaces`.

If any line starts with `callimachus-kit:`, cal is missing or failed: pass the message on and stop.

## 3. Ask

Show one numbered list: each decision and gotcha with its exact wording (mark any that would replace an older decision, quoting the old one), then the TODOs to close. Ask which to save: all, none, or by number. **Write nothing until the user answers.**

## 4. Save

For what they picked:

- `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh remember decision "<text>" --because "<reason>"`, adding `--replaces <id>` when it reverses an older decision
- `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh remember gotcha "<text>"`
- `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh done <todo-id>`

Then report what was saved in a line or two. Mention once that `cal memory publish` writes saved facts into the repo's `.callimachus/memory/` folder for teammates. Don't run it unless asked.
