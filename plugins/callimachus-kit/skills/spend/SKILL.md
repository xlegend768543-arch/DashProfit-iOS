---
name: spend
description: Show what AI coding agents have cost on this repo, from the token usage in the user's Callimachus index: the total, the trend by day, the priciest sessions with where their spend went, and the priciest commits.
argument-hint: "[days, default 30]"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh:*)
---

Days: $ARGUMENTS

Use 30 if no number was given. Call it DAYS.

## Gather

Run these in parallel (`@repo` is replaced with this repo's name):

- `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh cost @repo --since DAYS`: total by model
- `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh cost @repo --by day --since DAYS`
- `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh cost @repo --by thread --since DAYS -n 5`: priciest sessions, with notes on where the spend went
- `${CLAUDE_PLUGIN_ROOT}/scripts/cal.sh cost @repo --by commit --since DAYS -n 5`: priciest commits

If any line starts with `callimachus-kit:`, cal is missing or failed: pass the message on and stop.

## Report

- **Total:** the amount over DAYS days, and the share for each model.
- **Trend:** one or two lines, such as the busiest days and whether spend is going up or down. No 30-row table.
- **Priciest sessions:** up to 5, each with its title, cost and cal's note on where the spend went (cache reads, long sessions, subagents, a tool failing over and over).
- **Priciest commits:** up to 5, each with its short sha, subject and cost.
- **One thing to try:** a single concrete suggestion drawn from those notes, if one stands out.

Close with: figures are estimates at API list prices, so on a subscription they show what the same usage would cost at those prices, not what was billed. Name any models cal lists as unpriced.
