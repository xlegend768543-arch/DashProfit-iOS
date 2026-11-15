---
name: seen-this
description: Look up whether an error has been hit before in the user's AI coding sessions (from their local Callimachus index), and how it was fixed. Use when a build, test or command fails with an error message, or the user asks "have I seen this before?".
argument-hint: "<error message>"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh:*), Read, Grep
---

Error: $ARGUMENTS

If no error was given, use the most recent error in this conversation; if there is none, ask for it and stop.

## Steps

1. Boil the error down to its distinctive part: the error type and message. Drop paths, line numbers, addresses, timestamps and ids. Call that SIGNATURE, and its 2-4 most distinctive words KEYWORDS.
2. Run these three in parallel (`@repo` is replaced with this repo's name):
   - `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh issues @repo -n 30`: recurring errors in this repo, each with the commit that fixed it once one is linked
   - `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh search KEYWORDS -n 8`: keyword search across every agent and project
   - `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh gotchas "SIGNATURE" -p @repo -n 5`: gotchas recorded about it
3. For the one or two sessions that best match, run `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh knowledge <thread-id>` to see what was done.
4. If a fix was found, read the files it touched to check that it still fits the code as it is now.

If any line starts with `callimachus-kit:`, cal is missing or failed: pass the message on and stop.

## Answer

Start with one verdict line, whichever fits:

- "Seen N times; last fixed in `<sha>` (thread <id>, <date>)."
- "Seen before (thread <id>, <project>, <date>), but no fix was recorded."
- "Not seen before in your history."

Then, if there was a fix: what it changed, in two or three lines, and whether it still applies here. Offer to apply it; don't apply it unasked.

If a fix gets confirmed in this session and no gotcha about it exists yet, suggest saving it with `/callimachus-kit:wrap-up`.
