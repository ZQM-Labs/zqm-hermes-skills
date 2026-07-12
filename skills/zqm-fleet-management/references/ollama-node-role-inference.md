# Inferring a node's INTENDED fleet role from local manifests

## Why this is a separate class from inventory / audit
Live probes (port scan, `/api/tags`) tell you OBSERVED state — port open/closed,
model count. They CANNOT tell you INTENT: whether a LAN-unreachable node is a
**crashed service (fault)** or a **deliberate island (by-design)**. When a fleet
node's service is dark from the LAN, read the fleet's OWN config BEFORE reporting
"down." This converts the open "transiently down vs localhost-bound?" ambiguity
into a resolved design fact.

## The manifests that encode intent (ZQM fleet)
1. **`Desktop/ollama-fleet/litellm_config.yaml`** — the LB fabric's `model_list`.
   Every `api_base: http://<ip>:11434` entry IS a fleet endpoint. A node
   ABSENT here = NOT wired into the fabric. Grep the `api_base` hosts and count
   per host to see who is in the pool.
2. **`Desktop/Ollama_Fleet_Chaining_Plan.md`** — the "NODE-N DECISION" section
   states the explicit intent: (a) LEAVE PRIVATE / don't add to fleet (default
   island) vs (b) JOIN THE FLEET (set OLLAMA_HOST=0.0.0.0 + add to LiteLLM).
   This is the design decision, in writing.
3. **`.openclaw/openclaw.json`** (`models.providers.ollama.baseUrl`) — what the
   control plane's own agent treats as its Ollama endpoint. If it is only
   `http://127.0.0.1:11434`, the control plane does NOT consume the node as a
   remote endpoint. (Confirm in `agents/main/.../catalog.json` too.)
4. **`Desktop/Ollama_Network_Inventory.md`** — the verified census row for the
   node: its stated Ollama bind (LAN vs LOCALHOST-ONLY) and risk classification
   (localhost-bound nodes are explicitly "excluded from LAN risk").

## Decision logic
- **Present in `litellm_config.yaml` + chaining plan treats it as a fleet
  endpoint** → an OBSERVED dark state is a FAULT (service down / bind slipped).
  Report "down, investigate," and re-probe from the node's own console.
- **Absent from `litellm_config.yaml` + chaining plan says "leave private
  (default)" + inventory says LOCALHOST-ONLY** → OBSERVED dark state is BY
  DESIGN. The `:11434` timeout is the EXPECTED posture, NOT a crash. Report
  "intentional island; not a fault. Promote only via deliberate
  OLLAMA_HOST=0.0.0.0 + firewall allow + LiteLLM add."
- **Live probe is still REQUIRED** to confirm reality matches intent (manifests
  can go stale). A localhost-only node that ALSO fails from its own console is a
  genuine fault — but a LAN-side HTTP 000 alone is consistent with intended
  config, so never call it "down" on LAN evidence alone.

## Worked example (2026-07-11, Node-3 / 192.168.1.46)
- **Probe (from control plane 192.168.1.218):** `curl http://192.168.1.46:11434`
  → HTTP 000 / timeout (LAN-unreachable, re-probe confirmed).
  `curl http://192.168.1.218:11434` → HTTP 200 (0.001s) — proves N1's Ollama
  binds 0.0.0.0 and the LAN path works, so N3's 000 is a host-side bind posture,
  not a network fault.
- **`litellm_config.yaml`:** `api_base` hosts = .218×3, .21×10, .215×56 — ZERO
  references to .46. N3 excluded from the fabric by design.
- **`Ollama_Fleet_Chaining_Plan.md` §NODE-3 DECISION:** default = (a) LEAVE
  PRIVATE = don't add to fleet.
- **`.openclaw/openclaw.json`:** ollama `baseUrl` = only `127.0.0.1:11434`
  (also `agents/main/.../catalog.json`). Control plane does not treat N3 as an endpoint.
- **`Ollama_Network_Inventory.md`:** row for .46 = "LOCALHOST-ONLY (127.0.0.1)".
- **CONCLUSION:** N3's intended role = private/single-user island (localhost-only
  127.0.0.1), NOT a load-balanced fleet endpoint. The `:11434` timeout is
  CONSISTENT WITH intended config — not a crashed service. Promoting it requires
  a deliberate `OLLAMA_HOST=0.0.0.0` + firewall allow + LiteLLM add (none done).
- **CONFIDENCE:** HIGH for "not in fabric by current config." Only UNVERIFIED:
  what models actually sit on N3 (needs `ollama list` on Node-3 itself or WinRM
  with Node-3 creds).

## Output format (swarm leaf / blackboard)
Report in this order so the decision-relevant payload is front-and-center:
1. **PROBE** — live curl/port result (re-verified, not from memory).
2. **MANIFEST EVIDENCE** — which files, and what each says about intent.
3. **INFERENCE** — the role (island vs fleet endpoint) + whether the observed
   dark state is fault vs by-design.
4. **CONFIDENCE + UNVERIFIED** — what remains open and how to close it.
Keep the "by design vs fault" distinction explicit — it is the whole point.
