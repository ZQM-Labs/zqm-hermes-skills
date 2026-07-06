---
name: localhost-management
description: Use when managing localhost services, ports, tunnels, or local web debugging workflows. Includes checking which service is on a port, freeing it, launching simple localhost servers, and port-forwarding on Linux, macOS, and Windows.
version: 1.1.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [localhost, ports, dev-server, proxy, tunneling, windows]
    related_skills: [systematic-debugging, dogfood]
---

# Localhost Management

## Overview

Localhost workflows fail fast when a known port is already taken, when the browser hits a different rule than the server, or when Windows rules differ from Unix. This skill gives deterministic recipes for inspecting ports, killing conflicting listeners, launching lightweight local servers, and handling localhost proxies/tunnels.

## When to Use

- User asks what is running on `127.0.0.1`, `localhost`, or a specific port like 3000/5173/8080.
- User wants to free a port or stop a conflicting local dev server.
- User asks to open something locally for quick testing or file sharing.
- User uses terms like `node .`, `npm run dev`, `python -m http.server`, `uvicorn`, `vite`, `tunnel`, `ngrok`, `localtunnel`, or `warp`.
- User is debugging `ERR_CONNECTION_REFUSED`, `EADDRINUSE`, proxy confusion, or browser/vs-server mismatches on localhost.

Do **not** use for:
- Remote server management over SSH.
- Deep networking outside localhost (DNS beyond `hosts`, VLANs, WAN).
- Production deployment secrets or cloud ingress configuration.

## Core Recipes

### 1. Inspect listeners on Linux/macOS

```
ss -ltnp | grep ':PORT'   # preferred
lsof -nP -iTCP:PORT -sTCP:LISTEN
kill PID
```

### 2. Inspect listeners on Windows

Use Git Bash / MSYS style in the Hermes terminal:

```
netstat -ano | grep ':[PORT]'
taskkill //F //PID <PID>
```

Or from PowerShell/cmd:

```
netstat -ano | findstr :PORT
taskkill /F /PID <PID>
```

Common helpers that often own 5173/3000/8080/8000:
- `node`, `npm`, `npx`
- `python`, `uvicorn`, `gunicorn`
- `pnpm`, `yarn`, `vite`, `next`, `react-scripts`

### 3. Launch quick local servers

Straight server:
```
python -m http.server 8000
python3 -m http.server 8000
node -e "require('http').createServer((q,r)=>r.end('ok')).listen(8000,'127.0.0.1')"
```

Framework servers:
- Vite: `npx vite --host`
- Next.js: `npm run dev` then open `http://localhost:3000`
- Streamlit dashboards: `streamlit run app.py`
- FastAPI: `uvicorn app:app --reload --host 127.0.0.1 --port 8000`

### 4. Free a stuck port fast

```
# linux/macos
fuser -k PORT/tcp
# windows in gitbash
netstat -ano | grep ':[PORT]' | awk '{print $5}' | xargs -r taskkill //F //PID
```

Fallback if the above is noisy: reboot. Record what owned the port first so you can stop it properly.

### 5. Simple tunnel/remote-access options

Prefer trust-first tools; gate public exposure behind review.

- `ngrok http 8080` — widely trusted, inspectable URL, free tier useful.
- `cloudflared tunnel --url http://localhost:8080` — Cloudflare ingress.
- `lt --port 8080` / `npx localtunnel --port 8080` — quick, ephemeral, less auditable.
- Tailscale Funnel / HTTPS only if the user already runs Tailscale.

If the user is on Windows and `ngrok`, `cloudflared`, or `lt` is missing:
1. Suggest `winget install`.
2. Otherwise provide direct HTTPS download and check unzip step.
3. Suggest adding the install dir to PATH or use its absolute path.

### 6. Windows-specific checks

- If `http://localhost` and `http://127.0.0.1` differ, check `hosts` and proxy/WARP.
- Git-bash `localhost` usually works; `node` DNS may behave the same as on Linux, but corporate VPN and Winsock can bind unexpectedly.
- WSL2: apps in WSL listen separately from Windows at `127.0.0.1`; view with `netstat -ano` on the Windows side.
- If browser show a local proxy/WARP interstitial page rather than the app, check system proxy config and disable it for `localhost|127.0.0.1`.

### 7. DNS/localhost rules
- `/etc/hosts` or `C:\Windows\System32\drivers\etc\hosts`.
- Canonical local aliases: `127.0.0.1`, `localhost`, `::1`.
- Don’t point custom domains to `127.0.0.1` while tunnel tools are running; expose only what you intend.

## Common Pitfalls

1. Port freed, server not restarted. Always restart the server after freeing.
2. IPv6 listener but ping IPv4. Inspect `::1` as well as `127.0.0.1`.
3. Wrong port in browser. CLI output shows one port, browser uses another.
4. Corporate proxy/WARP strips localhost responses. Test `http://127.0.0.1:PORT` directly.
5. Multiple package managers spawn multiple servers. Check for `node`, `pnpm`, `vite`, and `next` simultaneously.

## Workflow Discipline

- Identify the conflicting process first, then kill only that process.
- If a command claims it could not bind, the previous server may still be starting up; wait a few seconds or inspect ports again.
- For web apps that open the browser automatically, disable auto-open if the goal is plain terminal behavior confirmation.
- When tunneling, prefer time-bounded, non-public tooling unless the user explicitly asks.

## Verification Checklist

- [ ] `127.0.0.1:PORT` returns the expected response in terminal and browser.
- [ ] `ERR_CONNECTION_REFUSED` or `EADDRINUSE` is resolved.
- [ ] No unintended extra localhost server processes remain after a kill.
- [ ] Tunnel URL was provided only after checking exposure risks.
- [ ] On Windows, no corporate proxy/WARP interference remains.
