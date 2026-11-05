# dsh credential resolution — source-derived detail

From `@deepseek-ai/dsh-credentials-local/lib/index.js` and `dsh-home-paths`.

## Layering order (highest precedence first)

```
1. inherited process environment      (read-only, WINS)
2. $DSH_HOME/.credentials.yaml        (provider-managed, writable)
3. <invocation cwd>/.env              (read-only fallback)
4. $DSH_HOME/.env                     (read-only fallback)
```

The docs state: "The inherited environment wins because `DEEPSEEK_API_KEY=… dsh`,
a CI secret, or a container `-e` is this run's explicit intent; it cannot be
overridden by a file." So exporting `DEEPSEEK_API_KEY` into the dsh process is the
authoritative way to supply the key.

## DSH_HOME resolution (`dsh-home-paths`)

- Dir name default: `.dsh` → `~/.dsh`.
- Precedence: explicit configured path > `$DSH_HOME` env > `~/.dsh`.
- Blank/whitespace `$DSH_HOME` is treated as unset (never resolves to cwd).

## Where the user's key actually lives

- NOT in shell env (nothing exported in interactive shell).
- NOT in macOS Keychain under a `deepseek` label.
- NOT plaintext in `~/.hermes/auth.json` — that holds only `credential_pool.deepseek[0]`
  metadata + `secret_fingerprint` (Hermes redacts the real secret).
- NOT in `~/.hermes/.env.bak` (that's a template with commented-out lines).
- **YES**: `~/.hermes/.env`, line `DEEPSEEK_API_KEY=sk-…` (35 chars, starts `sk-bf3d…`).
  base_url for the deepseek provider is `https://api.deepseek.com/v1`.

## How dsh reads the key at runtime

dsh is OpenAI-compatible: it uses `OPENAI_BASE_URL` + an API key. It does NOT read
a `DEEPSEEK_API_KEY` env var directly in its own packages (no `process.env` refs in
the dsh / dsh-web-app / dsh-client-ui-model-selection bundles) — the credential
provider resolves the key from the layered sources above and feeds it to the model
client. So the lever is the environment, not a dsh flag.

## .credentials.yaml alternative (persistent, no launcher)

If you want dsh to find the key regardless of how it's launched, write
`~/.dsh/.credentials.yaml` (keyed by reference the harness expects). The web UI's
model-selection screen also writes here. Only do this if the launcher-script
approach is undesirable.
