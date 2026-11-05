# Nous Portal one-shot setup — `hermes setup --portal` transcript

Verified 2026-08 on this machine. End-to-end driver for the Nous Portal onboarding wizard.

## Flow overview
1. OAuth **device-code** login: prints URL + `user_code`, opens browser, polls for approval.
2. Curated model picker (number menu, default 1 = `tencent/hy3:free`).
3. Tool Gateway free-tool toggles (all 5 pre-checked; bare Enter confirms).

## Exact driver sequence
```bash
# 1. Pre-check (both needed):
hermes portal info      # shows "Auth: not logged in" before
hermes auth list        # no 'nous' credential before

# 2. Launch wizard in background PTY:
terminal(command="hermes setup --portal", background=true, pty=true)
# -> session_id, then:

# 3. Poll to read the device code:
process(action="poll", session_id=...)
# Output: "1. Open: https://portal.nousresearch.com/manage-subscription?user_code=XXXX-XXXX
#          2. If prompted, enter code: XXXX-XXXX  (Opened browser for verification)
#          Waiting for approval (polling every 1s)..."

# 4. RELAY the URL + code to the user, ask them to authorize NOW.
#    Poll until "Login successful!" appears.

# 5. Model picker appears:
#    Choice [default 1]:  ->  process(action="submit", data="1")

# 6. Tool toggles appear (all [✓] by default):
#    Toggle # (or Enter to confirm):  ->  process(action="submit", data="")   # bare Enter

# 7. Wizard exits 0 with "✓ Portal setup complete."

# 8. Post-check:
hermes portal info      # "Auth: ✓ logged in", "Model: ✓ using Nous as inference provider"
hermes auth list        # 'nous (1 credentials): #1 device_code oauth'
```

## Expected prompts (verbatim)
```
Login successful!
  Auth state: /Users/<user>/.hermes/auth.json

Showing 4 curated models — use "Enter custom model name" for others.

  Select default model:
  Select by number, Enter to confirm.

  (●)  1. tencent/hy3:free                        free     free     free
  (○)  2. poolside/laguna-s-2.1:free              free     free     free
  (○)  3. stepfun/step-3.7-flash:free             free     free     free
  (○)  4. poolside/laguna-xs-2.1:free             free     free     free
  (○)  5. Enter custom model name
  (○)  6. Skip (keep current)

  Choice [default 1]: 1

Default model set to: tencent/hy3:free
  Config updated: ~/.hermes/config.yaml (model.provider=nous)

  Your free Nous tool pool — pick the tools to enable:
  Toggle by number, Enter to confirm.

  [✓]  1. Web search & extract (Firecrawl)
  [✓]  2. Image generation (FAL)
  [✓]  3. Text-to-speech (OpenAI TTS)
  [✓]  4. Speech-to-text (OpenAI Whisper)
  [✓]  5. Browser automation (Browser Use)

  Toggle # (or Enter to confirm):
✓ Portal setup complete.
    Run `hermes portal info` to inspect routing.
```

## Pitfall: device-code expiry
- First attempt sat ~63 min waiting for user approval → failed with
  `Login failed: invalid_grant: Invalid device code` → `Login cancelled or failed.`
- Device codes are only valid for **minutes**. On expiry, kill/restart the
  wizard to mint a fresh code and have the user authorize right away.
- `hermes portal info` after a failed run still shows `not logged in` — the
  failure leaves no partial state.

## Notes
- `hermes portal` (no subcommand) is the human-readable alias for
  `hermes setup --portal` (per `hermes portal --help`).
- Current session keeps its launch-time model; new sessions pick up the
  new default (`model.provider=nous`, model `tencent/hy3:free`).
- Switch back anytime: `hermes model` / `hermes auth reset nous`.
