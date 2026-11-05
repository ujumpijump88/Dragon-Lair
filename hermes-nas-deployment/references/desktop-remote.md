# Hermes Desktop as a client of a remote backend

Use when the desktop app should drive the always-on Hermes (NAS, VPS, homelab box) instead of
running a second local copy. Covers the backend preconditions, the in-app flow, where the
connection is persisted, and how to read the failure modes.

## 1. Backend preconditions (check before touching the app)

```bash
# auth gate on + the provider the app will detect
curl -sS http://<host>:9119/api/status | python3 -c \
  'import json,sys; d=json.load(sys.stdin); print(d.get("auth_required"), d.get("auth_providers"), d.get("version"))'
# expect: True ['basic'] 0.x.y
```

- The dashboard must bind a **non-loopback** address (`0.0.0.0` or the tailnet IP); loopback means
  nothing external can reach it.
- Set `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` + `_PASSWORD` (or `_PASSWORD_HASH`).
- Set a **stable `HERMES_DASHBOARD_BASIC_AUTH_SECRET`** — without it the signing key is regenerated
  per boot, so every restart forces a fresh sign-in.
- On a Docker backend these live in the container env file; recreate the container after changing
  them, then re-check `/api/status`.

## 2. In-app flow (the supported path)

**Settings → Registered gateways → Add connection → Remote gateway** (or **Edit** on an existing
one):

1. **Name** — anything unique, e.g. `NAS · 外网`.
2. **URL** — `http://<host>:9119`. Use the LAN address at home and the tailnet address when remote;
   keep two entries and switch, because the LAN path is much faster than a relay.
3. **Sign in** — with a password provider the dialog shows a username/password form. This mints the
   session token, which is what the connection actually stores.
4. **Save**, then optionally **Make primary** (and enable *return to Sessions on the last-used
   gateway* if that should be the default at launch).

Remote hosts are configured **per profile**: each profile points at its own backend, and switching
profiles switches backends. Point every profile you use at the same URL if the whole app should be
remote.

## 3. What is persisted where

`~/Library/Application Support/Hermes/connections.json` (macOS; `userData` elsewhere):

```json
{
  "version": 2,
  "primary": "local",
  "launchMode": "primary",
  "lastUsed": "local",
  "connections": [
    {"id": "local", "kind": "local", "label": "This device"},
    {"id": "nas-lan", "kind": "remote", "label": "NAS · LAN", "url": "http://192.168.50.106:9119",
     "authMode": "token", "token": {"encoding": "safeStorage", "value": "<blob>"}}
  ]
}
```

- `kind`: `local` | `remote` | `cloud` | `ssh`.
- `authMode`: **only `token` or `oauth`** — there is no `basic`. A password-provider sign-in results in
  a token.
- `token.encoding`: `safeStorage` (encrypted via the OS keychain) or `plain` (accepted, but only the
  app should write it).
- **Do not hand-author remote entries.** A URL-only object loads and appears in the list, then fails
  at connect time with `Remote Hermes gateway is selected, but no session token is saved` — and the
  UI may not offer a sign-in prompt for it. Create connections through the app instead.

## 4. Diagnosis

| Evidence | Meaning |
|---|---|
| `~/.hermes/logs/desktop.log`: `[renderer error:main] … no session token is saved` | Entry has no minted token — create/edit via Sign in |
| `desktop.log`: `[gateway-route] published connection=<id>` | That backend is the active one right now |
| `desktop.log`: `active key=conn:<id>::<profile>` | Which connection+profile the window resolved |
| Sign-in returns 401 / `Invalid credentials` | Username or password mismatch (the backend answers identically for both) |
| Connection refused / times out | Backend bound loopback, or VPN/port blocked; re-check with the `curl /api/status` probe |
| Connected, but the chat never answers | First request on a cold relay path can take ~10 s — repeat before concluding it is broken |

## 5. Shared vs local (set expectations before the user asks)

| Item | Where it lives |
|---|---|
| Sessions, messages | the **backend's** `state.db` (per install) |
| Skills, memories, `config.yaml`, cron jobs, credentials | the **backend's** data dir |
| Window layout, reading position, scroll position | this desktop installation only |
| Desktop UI version | this installation only |

Consequences worth stating up front:

- A remote connection shows **that backend's** history only; conversations created on the other
  install do not appear, and there is no merge path for `state.db`.
- Anything installed/edited while connected to the remote lands on the remote — which is why one
  live backend is the right arrangement.
- `hermes update` and a Docker image pull each affect only the install that runs them; versions and
  bundled skills drift independently.
