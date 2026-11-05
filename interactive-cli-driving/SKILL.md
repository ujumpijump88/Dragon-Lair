---
name: interactive-cli-driving
description: "Use when a CLI command is interactive (wizard/OAuth)."
version: 1.0.0
---

# Interactive CLI Driving

Run interactive terminal CLIs (setup wizards, logins, OAuth device-code flows) on the user's behalf, end-to-end. This user often pastes commands like `hermes setup --portal` or `gh auth login` into chat expecting them to be executed and completed, not just explained.

## When to use
- User pastes a command that turns out to be an interactive wizard (`hermes setup ...`, `gh auth login`, package-manager prompts, anything printing `Choice:` / `Enter to confirm`).
- OAuth device-code flows that print a URL + `user_code` and open a browser.

## Procedure
1. **Inspect first**: run `hermes setup --help`-style help to learn flags and whether it's one-shot or interactive. Check pre-state with a status command (`hermes portal info`, `hermes auth list`) before starting.
2. **Launch**: `terminal(command=..., background=true, pty=true)`. PTY mode is required for prompt_toolkit/rich-style menus.
3. **Poll** (`process action=poll`) to see what it's waiting for. Output arrives in chunks — poll again after a beat.
4. **OAuth device-code step**: relay the printed URL + `user_code` to the user and ask them to authorize **immediately** (browser usually auto-opens). Do not proceed silently.
5. **Drive menus**: `process(action='submit', data='1')` types the value and presses Enter; `process(action='submit', data='')` sends a bare Enter (confirm default / accept toggled list). Between steps use `process(action='wait', timeout=...)` or poll until the next prompt appears.
6. **Verify**: after the wizard exits, run the status command (`hermes portal info`, `hermes auth list`, `hermes config get model.provider`) and report the actual end state — never just "done".

## Pitfalls
- **OAuth device codes expire fast (minutes).** A wizard left waiting long fails with `invalid_grant: Invalid device code`. Restart the command to mint a fresh code and have the user authorize promptly. Never let it sit for an hour (this happened: 63-minute wait → expired code → full retry).
- **The wizard's success banner and exit code can LIE.** On the failed first run, `hermes setup --portal` printed `Login failed: invalid_grant...` then still exited 0 with "✓ Portal setup complete." The final banner is decoration — the ONLY truth is the post-check status command (`hermes portal info`, `hermes auth list`). Always run it before reporting success.
- `background=true` without `notify_on_complete` runs silently — fine for wizards (they wait on the user), but you must poll/wait yourself.
- Some CLIs resist scripted input even via PTY (historically `gh auth login`). If `submit` doesn't advance the prompt after a couple tries, hand off: guide the user to run it in their own terminal panel, then verify the result afterward.
- Don't tight-loop poll — use `wait` with a timeout between steps.

## Worked examples
- `references/nous-portal-setup.md` — full `hermes setup --portal` transcript with expected prompts and the exact submit sequence.
- `references/hermes-model-picker.md` — full `hermes model` picker flow (provider menu → curated model list → config write), verified 2026-08.

## Verification checklist
- `hermes portal info` shows `✓ logged in` + correct provider
- `hermes auth list` shows the new credential entry
- Wizard's own "Config updated: ..." line, cross-checked with `hermes config get ...`
