# Callimachus Kit

Six everyday Claude Code commands built on [Callimachus](https://github.com/BetaBots-LLC/callimachus),
the local index of your AI coding sessions. Callimachus's own plugin gives Claude search, memory and
the session hooks. This kit adds ready-made workflows on top.

| Command | What it does | Claude may run it on its own |
|---|---|---|
| `/callimachus-kit:why <file>[:<line>]` | Why this code is the way it is: the commit, the session that wrote it, and the decisions behind it | yes |
| `/callimachus-kit:preflight <task>` | Before starting: has this been done before, what's already decided, known traps, overlapping TODOs | yes |
| `/callimachus-kit:seen-this <error>` | Has this error come up before, and how was it fixed | yes |
| `/callimachus-kit:standup [days]` | Yesterday / today / blockers, from your sessions, commits and TODOs | no |
| `/callimachus-kit:wrap-up` | End of session: save its decisions and gotchas to memory and close finished TODOs, after you pick which | no |
| `/callimachus-kit:spend [days]` | What agents cost on this repo: total, trend, priciest sessions and commits | no |

The first three are also triggered by what you ask ("why is this here?", "have I seen this
error?"). The last three run only when you type them.

## What it needs

- **The Callimachus `cal` CLI**, version 0.12 or later. Install the
  [desktop app](https://github.com/BetaBots-LLC/callimachus/releases/latest) and click
  **Settings > Agents > Install the cal CLI**, or, without the app:

  ```bash
  npx callimachus-mcp --install-cal
  cal index
  ```

- **Optional, for better matching:** `cal embed` (a one-time model download of about 128 MB). Without it,
  `preflight`, `seen-this` and `wrap-up` fall back to keyword search.
- **Optional, for decisions and gotchas from past sessions:** turn on memory in the app's
  **Settings > AI engine**. Without it you still get sessions, commits, errors, TODOs, spend and
  anything you save with `wrap-up`.

The kit works with or without Callimachus's own plugin. It never changes your files. `wrap-up` writes only
to Callimachus's index, and only after you confirm.

## Install

```bash
claude plugin marketplace add xlegend768543-arch/DashProfit-iOS
```

Then, inside Claude Code:

```text
/plugin install callimachus-kit@dashprofit-plugins
```

To try it from a local checkout without installing: `claude --plugin-dir ./plugins/callimachus-kit`.

## How it works

Every skill runs `scripts/cal.sh`, a small wrapper around `cal` that:

- finds `cal` at `$CALLIMACHUS_CAL`, `~/.local/bin/cal` or on `PATH`, and skips the system calendar
  (also named `cal`);
- replaces the argument `@repo` with the current repo's name (a linked worktree uses its main checkout's name);
- always exits 0, and prints a line starting with `callimachus-kit:` when `cal` is missing or fails,
  so the skill can explain what's wrong instead of stopping.

Each skill's `allowed-tools` lets it run only that wrapper (plus `git log`/`git blame` where noted)
without asking.

## Tests

```bash
bash plugins/callimachus-kit/tests/cal-wrapper.test.sh
claude plugin validate ./plugins/callimachus-kit
```
