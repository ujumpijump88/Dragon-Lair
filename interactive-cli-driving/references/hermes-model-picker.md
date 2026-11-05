# `hermes model` — interactive provider/model picker transcript

Verified 2026-08 on this machine. Same driving pattern as `hermes setup --portal` (background PTY + process submit), but a different wizard shape: it has TWO nested menus — first pick a provider (37 options), then pick a model within that provider.

## Flow overview
1. Shows current state header: `Current model:` + `Active provider:`.
2. **Provider menu** — 37 numbered entries, default 1 = Nous Portal. `Choice [default 1]:`
3. If a Nous-style provider is chosen, a **curated model menu** follows (same shape as setup wizard's model picker).
4. Writes `model.provider` + `model.default` to config, exits 0.

## Exact driver sequence
```bash
# 1. Pre-state (optional, shows what will change):
hermes config get model        # provider / default / base_url

# 2. Launch:
terminal(command="hermes model", background=true, pty=true)

# 3. Poll -> provider menu. Verify which provider is (●) active, ask the
#    user what they want (keep / switch / custom), then:
process(action="submit", data="1")   # e.g. 1 = Nous Portal (default)

# 4. Poll -> curated model menu appears (4 free models + custom + skip):
process(action="submit", data="2")   # e.g. 2 = poolside/laguna-s-2.1:free

# 5. Wizard prints "Default model set to: <model> (via Nous Portal)" and exits 0.

# 6. Post-check:
hermes config get model        # confirm provider/default actually changed
hermes portal info             # still logged in, provider line correct
```

## Expected prompts (verbatim)
```
  Current model:    tencent/hy3:free
  Active provider:  Nous Portal

  Select provider:
  Select by number, Enter to confirm.

  (●)  1. Nous Portal (Everything your agent needs, 300+ models with bundled tool use)  <- currently active
  (○)  2. Fireworks AI ...
  ... 37. Leave unchanged

  Choice [default 1]:

Showing 4 curated models — use "Enter custom model name" for others.

  Select default model:
  Select by number, Enter to confirm.

  (●)  1. tencent/hy3:free                        free     free     free  <- currently in use
  (○)  2. poolside/laguna-s-2.1:free              free     free     free
  (○)  3. stepfun/step-3.7-flash:free             free     free     free
  (○)  4. poolside/laguna-xs-2.1:free             free     free     free
  (○)  5. Enter custom model name
  (○)  6. Skip (keep current)

  Choice [default 1]: 2

Default model set to: poolside/laguna-s-2.1:free (via Nous Portal)
```

## Notes & pitfalls
- Option 5 "Enter custom model name" exists for non-curated / paid Nous models — needs a follow-up text submit.
- Option 37 "Leave unchanged" is the polite exit; the (●) marker shows the active provider.
- **Model changes apply to NEW sessions only** — the running session keeps its launch-time model. Always tell the user this explicitly (it was the main user-facing caveat this session).
- The 4 curated free models seen here match the setup wizard's list; `hermes model --refresh` wipes the picker cache and refetches live `/v1/models` lists.
- Post-check with `hermes config get model` is the reliable truth (output shape: `provider:`, `default:`, `base_url:`).
