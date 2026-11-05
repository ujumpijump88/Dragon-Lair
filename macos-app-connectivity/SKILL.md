---
name: macos-app-connectivity
description: "Fix macOS app DNS/proxy breakage after proxy/VPN changes."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos]
metadata:
  hermes:
    tags: [macos, networking, proxy, dns, troubleshooting, electron]
    related_skills: [systematic-debugging]
---

# macOS App Connectivity Troubleshooting

Use when a macOS app cannot connect, but browsers and `curl` work. Common after starting/stopping Clash, Clash Verge Rev, Surge, V2Ray, Xray, or tunnel interfaces.

## Quick Check Order

Run these from a terminal. Stop at the first positive match.

### 1. Compare the app endpoint against a working endpoint

```bash
dig +short www.anthropic.com
dig +short api.claude.ai
```

If `www.*` resolves and the app-specific subdomain does not, the problem is likely DNS/fake-IP/proxy rules for that exact host.

### 2. Check whether a proxy tool is still affecting DNS

```bash
ps aux | grep -iE 'clash|mihomo|verge|surge|v2ray|xray|sing|hysteria|trojan|ss' | grep -v grep
networksetup -getwebproxy Wi-Fi
networksetup -getsecurewebproxy Wi-Fi
networksetup -getsocksfirewallproxy Wi-Fi
networksetup -getautoproxyurl Wi-Fi
```

Also inspect for tunnel interfaces:

```bash
ifconfig | grep -E '(utun|tun|tap)'
```

### 3. Check system proxy config

```bash
scutil --proxy
```

If `HTTPEnable`/`HTTPSEnable` are off but an **Auto Proxy** URL is registered, the app may still be using PAC.

### 4. Verify the endpoint from outside the app

```bash
curl -sS -o /dev/null -w "HTTP %{http_code} | IP %{remote_ip}\n" https://<endpoint>
```

A 302/403 is often fine; a timeout or empty response is the failure mode.

## Common Fixes

### A. Hosts-file override

If the endpoint is empty in DNS but you know a working IP for the same service:

```bash
echo "<IP> <endpoint>" | sudo tee -a /etc/hosts
```

Then flush DNS:

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

### B. Disable system proxy for the app

If the app has a Network/Proxy setting, turn off **Use system proxy**. If it does not, look for a config file under `~/Library/Application Support/<App>/` and see whether proxy behavior can be overridden there.

### C. PAC / Auto Proxy cleanup

If an Auto Proxy URL exists but is not reachable:

```bash
sudo networksetup -setautoproxystate Wi-Fi off
```

### D. Restart after changes

Many Electron apps cache proxy/DNS state at launch. Quit fully, then reopen.

## CLI Tools Do Not Follow the macOS System Proxy

When the failing "app" is a CLI program (`git fetch`, package managers, installers/update commands that shell out to git), the system-proxy checks above do not apply — git and most CLI HTTP clients ignore `scutil --proxy` settings entirely. Symptoms: `curl https://host` works (curl may succeed on a slow direct route) while `git ls-remote` stalls or dies with `Operation too slow` / `Recv failure`.

Diagnose git specifically (never assume curl's result covers it):

```bash
git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 ls-remote origin HEAD   # direct
git -c http.proxy=http://127.0.0.1:7897 ls-remote origin HEAD                 # via local proxy
```

Fix: set the proxy at repo scope (survives update commands that run plain `git fetch`, and does not leak into other projects):

```bash
cd <repo> && git config http.proxy http://127.0.0.1:7897 && git config https.proxy http://127.0.0.1:7897
```

Two pitfalls:

- Verify the proxy is actually LISTENING before blaming the remote (`nc -z 127.0.0.1 7897`; `lsof -iTCP -sTCP:LISTEN | grep -iE 'clash|verge|mihomo'`). A repo pinned to a local proxy fails hard (`Failed to connect to 127.0.0.1 port 7897`) whenever the proxy app is not running — start it (`open -a "Clash Verge"`) or `git config --unset http.proxy`.
- Public GitHub mirror prefixes (ghproxy-style) are unreliable — test with curl before rewriting `url."...".insteadOf`; prefer the local proxy when one exists.
- Don't infer one destination's reachability from another. A live chat session or a model-API call (`api.deepseek.com`) succeeding says nothing about `github.com` — they are different hosts, and China-network throttling is per-domain, not per-IP. Symmetrically, an IP-reputation check (`ip-api.com/json` `proxy`/`hosting` flags) only tells you whether the egress IP looks like a datacenter/proxy; a clean flag does NOT mean the git remote is reachable. Diagnose the exact failing path (`git ls-remote origin HEAD`) instead of generalizing from the working one.

## Claude Desktop Notes

- Config: `~/Library/Application Support/Claude/claude_desktop_config.json`
- The app UI may not expose a Settings menu in some builds; proxy behavior is driven by system settings and the embedded Chromium network stack.
- Known failure mode: `api.claude.ai` can be unreachable while `www.anthropic.com` works. Hosts override to an Anthropic frontend IP is a practical workaround when public DNS fails for that exact subdomain.
