# Probe integrity + honesty guards (lead re-verify layer)

Hard-won during ZQM fleet audits. These are about NOT recording false findings —
the lead's job is to catch tooling artifacts before they enter the ledger.

## 1. Never probe a raw (non-HTTP) port with httpx/curl
Symptom seen: a "pulse" check reported N2 Redis :6379 had gone DOWN (timeout) —
a FALSE drift alarm. Cause: the probe sent an HTTP GET to a raw Redis socket;
Redis never answers HTTP, so it "times out" even though the port is wide open.

Rule: match the probe protocol to the port.
- Redis / raw TCP services -> use python sockets with the native wire command:
  ```python
  import socket
  def redis_ping(ip, port=6379, t=5):
      s=socket.socket(); s.settimeout(t); s.connect((ip,port))
      s.sendall(b"PING\r\n"); r=s.recv(64); s.close()
      return r.decode(errors="replace").strip()   # "+PONG" == unauth CRITICAL
  ```
- HTTP APIs (Ollama /api/tags, LiteLLM /v1/...) -> httpx/curl is fine.
- Bare reachability only -> a plain `socket.connect()` TCP-open test is protocol-agnostic
  and safe for ANY port; use it when you just need up/down, not auth state.

When a "pulse" flags drift on ONE item while neighbours on the same host are fine,
suspect the probe before believing the drift. Re-test with the correct protocol,
THEN update the ledger. Log the false alarm + root cause as a swarm_log entry.

## 2. netstat parsing (recurring MSYS/PowerShell trap)
- `subprocess.run(['powershell','-Command',"cmd /c 'netstat...' | Select-String"])`
  SILENTLY swallows cmd.exe stdout (0 rows). RELIABLE form: bare terminal redirect
  `powershell.exe -NoProfile -Command "cmd.exe /c 'netstat -ano -p TCP' | Select-String 'LISTENING'" > /c/Users/<u>/AppData/Local/Temp/net.txt 2>&1`
  THEN parse the file in a separate python step.
- Parse regex: `TCP\s+([\d.]+):(\d+)\s+[\d.]+:\d+\s+LISTENING\s+(\d+)` -> (addr, port, pid).
  Do NOT use `\S+` for the 2nd column — it fails on the spaced `0.0.0.0:0` local-address
  form and yields 0 matches. This bug once produced a false "5 claims CONTRADICTED" scare
  that was pure regex, not drift. If a parse yields 0 listeners, hexdump the file bytes
  first — the data is almost always there.

## 3. Honesty guard: never write fabricated vectors into a dead RAG
When asked to "vectorize memory into the <X> system", verify the embedding backend
is LIVE before ingesting. Failure mode seen: `ZQM-AI-Council/rag/` `LocalAIEmbeddings`
silently returns a 384-dim ZERO vector when its endpoint is down (Ollama :11434 returns
404 on /api/embed; no LocalAI process). Ingesting then populates the store with
all-zero vectors — every doc scores 0.0, retrieval is meaningless = fabrication.

Correct move when the backend is dead:
1. Build the corpus anyway (chunk the memory/ledger into the target's DocumentLoader
   schema, persist to data/documents/), create the missing data dirs.
2. Write a ready-to-run ingest script using the target's OWN embeddings/retriever classes.
3. Verify it imports + loads the corpus + FAILS SAFE on the dead endpoint (retrieve
   returns 0 hits, no crash) — that proves the code, not the vectors.
4. Report status = NOT_VECTORIZED with the concrete blocker + the one command that
   finishes it once a backend is live. Do NOT claim "vectorized".

Also note: many "RAG/vector" systems in this fleet are IN-MEMORY only (cosine-sim over
Python lists) — there is no SQL/SQLite/Chroma/FAISS sink despite the ask calling it a
"sql vectorization system". State that plainly rather than inventing a persistence layer.
