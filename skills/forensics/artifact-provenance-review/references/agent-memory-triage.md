# Worked example — ZBit/ZQM "SOUL.md" triage (2026-07-11)

## Setup / environment
- Windows/MSYS host. `search_files(pattern='SOUL.md', target='files')` returns matches
  with backslashed `/Users\...` paths that `read_file` CANNOT open.
- Fix: retry with MSYS form `/c/Users/<user>/...`.
- Stale index entries from other environments (`/opt/data/SOUL.md`, `/tmp/.../SOUL.md`)
  do not exist — confirm with `terminal` `[ -e "$p" ]` before reading.

## The artifacts found
1. `C:\Users\zqmco\AppData\Local\hermes\SOUL.md` — 513 B, the LIVE stock Hermes default
   prompt (unchanged). This is what drives the agent.
2. `...\hermes-agent\docker\SOUL.md` — 515 B, stock copy (1 trailing newline).
3. `...\zqm-auth\SOUL.md` — 513 B, byte-identical stock copy.
4. `...\quarantine\CVG-CONTAMINATED-Zbit-Knowledge-Base\SOUL.md` — 4354 B, 109 lines,
   "ZQM Computing" agent identity doc, version 1.0.0, 2026-06-26, with `[REDACTED]` fields.
5. `...\CVG-CONTAMINATED-Zbit-Knowledge-Base\SOUL-ZQM-Node-1.md` — same, only
   "Hive"→"Garden" (x2) and "ZQM Neuron"→"ZQM AI" differ.
6. `...\Google Drive\...\06_Zbits\zbit-knowledge-base\SOUL.md` — 4347 B, the DECONCLASSIFIED
   copy (redactions filled in: ZQM Computing, ZQM-DFORGE-11, QSeal chain, 192.168.1.0/24,
   ZNet-Media NAS, QSeal, host 192.168.1.241).
7. `.../kanban-video-orchestrator/assets/soul.md.tmpl` — 669 B Jinja template for the
   kanban-video skill (placeholders: {{ROLE_NAME}}, {{ROLE_RESPONSIBILITIES}}, etc.).
   NOT a soul you run.

## diff: quarantine SOUL.md vs SOUL-ZQM-Node-1.md (both redacted)
- L13 "ZQM Hive infrastructure" → "ZQM Garden infrastructure"
- L19 "Coordinate all ZQM Hive systems" → "ZQM Garden systems"
- L68 "| **ZQM Neuron** | AI infra agent" → "| **ZQM AI** | AI infra agent"

## diff: quarantine SOUL.md vs imported declassified SOUL.md
- L11 ZQM ([REDACTED]) → ZQM (ZQM Computing)
- L13 [REDACTED]DFORGE-11 / Hive → ZQM-DFORGE-11 / Garden
- L19 [REDACTED] chain → QSeal chain
- L45 ZQM-Media NAS → ZNet-Media NAS
- L46 [REDACTED]/24 → 192.168.1.0/24
- L68 ZQM Neuron → ZQM ZQM-AI
- L72 [REDACTED] (PQ chain) → QSeal
- L78 [REDACTED]DFORGE-11 (HP Pavilion AIO, i7-13700T, 32GB, Win11) → ZQM-DFORGE-11 (same fake HW)
- L79 Network [REDACTED] (LAN) → 192.168.1.241 (LAN)
- L80 NAS TrueNAS, ZQM-Media → TrueNAS, ZNet-Media

## Verdict delivered
- Files 1–3 = stock Hermes prompt. File 7 = skill template.
- Files 4–6 = the SAME identity doc of a USER-BUILT agent (the user's words:
  "memories and dreams from another agent we created"), redacted to 3 levels.
  NOT third-party, NOT untrusted despite the `CVG-CONTAMINATED` folder name.
- Fiction flags: "HP Pavilion AIO i7-13700T" contradicts real Node-1
  (ASUS Vivobook K6602VV / i9-13900H). "ZBit mining / QSeal chain / 4,572 blocks /
  CHSH 2.63" are aspirational narrative, not measured. Do not trust these as infra facts.
- No deletion performed. Offered options via clarify(); user clarified provenance instead.

## Lesson
Provenance is proven by the USER, not inferred from a folder name. When in doubt about
a "contaminated"/"quarantine" agent artifact, surface it as first-party and ask — never scrub.
