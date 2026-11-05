---
name: deepseek-harness
description: Run the DeepSeek Harness dsh CLI and wire its key.
version: 1
author: hermes-agent
license: mit
metadata:
  hermes:
    tags: [deepseek, dsh, harness, cli, web-ui, credentials]
    related_skills: [mlops/inference/serving-llms-vllm, software-development]
---

# DeepSeek Harness (`dsh`)

## When to Use
- User wants to launch the DeepSeek Harness web UI (`npx @deepseek-ai/dsh web`) or any `dsh` profile.
- User mentions "dsh", "DeepSeek Harness", or connecting a DeepSeek API key to the harness.
- User's dsh web UI prompts for credentials / a model key and you need to supply one.
- Do NOT use for general DeepSeek API chat (that's a provider, not this CLI).

`dsh` is the product launcher for the **DeepSeek Harness** — an agent runtime
(Cordis plugin framework, host/client split, JSON-RPC over stdio) with a web UI,
a headless mode, and a TUI. Profiles are ordered stacks of plugin-bundle patch
layers + the user's own `cordis.patch.yml` overrides.

## Quick start — launch the web UI

```sh
npx @deepseek-ai/dsh web          # alias of `--profile web`
```

- Boots at `http://127.0.0.1:3080` (prints `dsh web: http://…` on ready).
- `--host 0.0.0.0` is rejected by the CLI (no all-interfaces binding yet).
- Other profiles: `dsh --profile <name>`, `dsh --profile headless "job"`.
- Inspect config without booting: `dsh --profile web --dump-config`.

## PITFALL — first-run install is SLOW (not stalled)

`npx @deepseek-ai/dsh web` resolves a **huge** dependency tree
(gaxios, gcp-metadata, protobufjs, jws, … hundreds of transitive packages). npm
logs only `npm warn exec The following package was not found and will be installed:
@deepseek-ai/dsh@0.1.0-rc.6` and then goes quiet while fetching manifests. It can
take **5–7 minutes** on first run. Each fetch returns `200 OK` — it is working,
just slow. After the first run the package is cached under `~/.npm/_npx/...` and
subsequent boots are fast. Do NOT kill it thinking it hung.

## PITFALL — mangled npx command (`@file:` artifact)

If the user pastes something like `` npx @file:`deepseek-ai/dsh` web `` the shell
treats `@file:` as npx's "read arg from file" syntax and the backticks get passed
through literally → `file not found`. The intended command is the bare
`npx @deepseek-ai/dsh web`. Strip `@file:` and backticks.

## DSH_HOME & profile layout

- Default home: `~/.dsh` (override with `$DSH_HOME`).
- `web` profile auto-initializes on first use → `~/.dsh/profiles/web/cordis.patch.yml`.
- Home-level user overrides: `$DSH_HOME/cordis.patch.yml` (applied over every profile).
- Settings: `~/.dsh/settings.yaml`; anonymous id: `~/.dsh/.anonymous-user-id`.

## Credential resolution (how to give dsh a key)

dsh's local credential provider (`@deepseek-ai/dsh-credentials-local`) layers
sources by trust. **The inherited process environment WINS**. Full order, highest
to lowest precedence:

```
inherited process environment      (read-only, wins)
  > $DSH_HOME/.credentials.yaml    (provider-managed, writable)
  > <invocation cwd>/.env          (read-only fallback)
  > $DSH_HOME/.env                 (read-only fallback)
```

Implication: the most reliable way to give dsh a key is to **export it into the
dsh process's environment** before launching. It will beat anything in a config
file. See `references/credentials.md` for the source-derived detail.

## Wiring the DeepSeek key (recommended pattern)

The user's DeepSeek key lives in `~/.hermes/.env` as `DEEPSEEK_API_KEY` (NOT in the
shell environment, NOT in the macOS Keychain — `auth.json` only stores a
`secret_fingerprint`). To start dsh with the key available, source that line and
export it, then `exec npx …`. A known-good launcher lives at `scripts/launch_dsh.sh`.

```sh
~/Hermes/launch_dsh.sh      # injects DEEPSEEK_API_KEY from ~/.hermes/.env, then runs dsh web
```

Launching bare `npx @deepseek-ai/dsh web` (no key in env) makes the web UI prompt
for credentials on first model use. Restarting with the key injected fixes it.

## Verification

```sh
NO_PROXY=localhost,127.0.0.1 curl -sS --noproxy '*' -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:3080/
```
Expect `HTTP 200`. (Use `--noproxy '*'` because a system proxy like Clash at
`127.0.0.1:7897` will otherwise try to route localhost through the proxy and 502.)

## Support files
- `references/credentials.md` — credential layering order + DSH_HOME paths, condensed from harness source.
- `scripts/launch_dsh.sh` — known-good launcher that injects `DEEPSEEK_API_KEY` from `~/.hermes/.env` into dsh.
