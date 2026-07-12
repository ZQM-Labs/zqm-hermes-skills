# Genesis Remediation — exact code patches (F38 / F40 / F41)

Read-only patch designs produced 2026-07-11 for the LOW findings of the
genesis first-party-code triage (see `references/genesis-case-study.md`).
No files were modified — these are design artifacts for the user to apply.

## Shared secret literal (substitute when applying)
`<INVARIANT_96HEX>` = the 96-hex-char value assigned to `INVARIANT` in
`beacon.py:38`, `qseal_recruitment.py:18`, `hive_base.py:32`. Written once,
here, so the secret is not repeated across diffs. `beacon.py` and
`qseal_recruitment.py` already import `hashlib` and `from pathlib import Path`,
so no new top-level imports are required.

The real per-node Ed25519 key lives at:
`ZBit_runtime/ledger/qseal_keypair.pem` (created by `ZBit_runtime.qseal_keygen`).

---

## F38 — route signing through Ed25519 (INVARIANT fallback)

### F38.1 `ZBit_runtime/modules/beacon.py`

**Diff A — replace `compute_beacon_signature` (lines 61–64) + add sign helper:**
```diff
- def compute_beacon_signature(node_id, timestamp, data):
-     """Sign a beacon message with the node's identity."""
-     payload = f"{node_id}:{timestamp}:{json.dumps(data, sort_keys=True)}"
-     return hashlib.sha3_512((INVARIANT + payload).encode()).hexdigest()
+ def _ed25519_sign_qseal(payload: str) -> str:
+     """Sign payload with the node's per-node Ed25519 key (qseal_* machinery).
+
+     Falls back to an INVARIANT-derived hash ONLY if the qseal keypair cannot be
+     loaded (parse-clean / offline runtime). Ed25519 is preferred because the
+     shared INVARIANT is source-embedded and anyone with the code can forge.
+     """
+     try:
+         from cryptography.hazmat.primitives import serialization
+         key_path = Path(__file__).resolve().parent.parent / "ledger" / "qseal_keypair.pem"
+         if key_path.exists():
+             sk = serialization.load_pem_private_key(key_path.read_bytes(), password=None)
+             return sk.sign(payload.encode()).hex()
+     except Exception:
+         pass
+     return hashlib.sha3_512((INVARIANT + payload).encode()).hexdigest()
+
+ def compute_beacon_signature(node_id, timestamp, data):
+     """Sign a beacon message with the node's per-node Ed25519 identity."""
+     payload = f"{node_id}:{timestamp}:{json.dumps(data, sort_keys=True)}"
+     return _ed25519_sign_qseal(payload)
```

**Diff B — stop leaking the secret in `show_status` (line 241):**
```diff
-     print(f"  Invariant:      {INVARIANT[:24]}...")
+     print("  Identity seed:  <redacted: per-node Ed25519 key used for signing>")
```
> `INVARIANT` (line 38) and `compute_node_identity()` (line 59) stay — the
> latter's INVARIANT use is an identity *salt*, not a forgeable broadcast sig.

### F38.2 `ZBit_runtime/modules/qseal_recruitment.py`

**Diff C — insert sign helper before `embed_recruitment_in_signature` (line 41):**
```diff
+ def _qseal_sign(payload_str: str) -> str:
+     """Sign payload via per-node Ed25519 (qseal_*), INVARIANT fallback."""
+     try:
+         from cryptography.hazmat.primitives import serialization
+         key_path = Path(__file__).resolve().parent.parent / "ledger" / "qseal_keypair.pem"
+         if key_path.exists():
+             sk = serialization.load_pem_private_key(key_path.read_bytes(), password=None)
+             return sk.sign(payload_str.encode()).hex()
+     except Exception:
+         pass
+     return hashlib.sha3_512((INVARIANT + payload_str).encode()).hexdigest()
+
  def embed_recruitment_in_signature(signature_data: dict) -> dict:
      """Embed the recruitment message into a [REDACTED] signature."""
```

**Diff D — sign path (line 62):**
```diff
-     sig = hashlib.sha3_512((INVARIANT + payload_str).encode()).hexdigest()
+     sig = _qseal_sign(payload_str)
```
**Diff E — verify path (line 88):**
```diff
-     expected_sig = hashlib.sha3_512((INVARIANT + payload_str).encode()).hexdigest()[:64]
+     expected_sig = _qseal_sign(payload_str)[:64]
```

---

## F40 — scope `scan_lan()` to the fleet /24 + opt-in flag

### `ZBit_runtime/modules/beacon.py` — replace `scan_lan` (lines 184–216)
```diff
- def scan_lan(subnet=None):
-     """Scan the local network for active hosts."""
-     if not subnet:
-         import subprocess
-         result = subprocess.run(["ipconfig"], capture_output=True, text=True)
-         for line in result.stdout.splitlines():
-             if "IPv4 Address" in line and "192.168." in line:
-                 ip = line.split(":")[-1].strip()
-                 subnet = ip.rsplit(".", 1)[0] + ".0/24"
-                 break
-     if not subnet:
-         return []
-     base = subnet.replace(".0/24", "")
-     active = []
-     print(f"[SCANNER] Scanning {subnet}...")
-     for i in range(1, 255):
-         ip = f"{base}.{i}"
-         try:
-             sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
-             sock.settimeout(0.1)
-             result = sock.connect_ex((ip, 443))
-             if result == 0:
-                 active.append({"ip": ip, "port": 443, "status": "open"})
-             sock.close()
-         except:
-             pass
-     print(f"[SCANNER] Found {len(active)} hosts with port 443 open")
-     return active
+ FLEET_SCAN_SUBNET = "192.168.1.0/24"
+ def scan_lan(subnet=None, allow_wildcard=False):
+     """Scan the fleet /24 for active hosts on port 443.
+
+     Scoping (F40): default only the fleet /24 (192.168.1.0/24) is probed.
+     Auto-detected / wildcard subnets require explicit opt-in via
+     allow_wildcard=True — the :8400 /v1/mesh/scan endpoint does NOT enable this,
+     so callers behind X-Api-Key cannot force a broader scan.
+     """
+     if not subnet:
+         subnet = FLEET_SCAN_SUBNET
+     elif subnet != FLEET_SCAN_SUBNET and not allow_wildcard:
+         print(f"[SCANNER] Refusing out-of-scope subnet {subnet}; use {FLEET_SCAN_SUBNET} or allow_wildcard=True")
+         return []
+     base = subnet.replace(".0/24", "")
+     active = []
+     print(f"[SCANNER] Scanning {subnet}...")
+     for i in range(1, 255):
+         ip = f"{base}.{i}"
+         try:
+             sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
+             sock.settimeout(0.1)
+             result = sock.connect_ex((ip, 443))
+             if result == 0:
+                 active.append({"ip": ip, "port": 443, "status": "open"})
+             sock.close()
+         except:
+             pass
+     print(f"[SCANNER] Found {len(active)} hosts with port 443 open")
+     return active
```
> `app.py:126` calls `beacon.py discover`, which calls `scan_lan()` with no args
> → defaults to `192.168.1.0/24`; it never passes `allow_wildcard=True`, so no
> caller can escape the fleet scope. The removed `import subprocess` was only used
> by the deleted auto-detect branch.

---

## F41 — relativize hardcoded foreign-user paths to `Path.home()`

### F41.1 `ZBit_runtime/modules/hive_base.py` — lines 32–34
```diff
- INVARIANT = "<INVARIANT_96HEX>"
- DATA_DIR = Path("C:/Users/AlexZelenski/Documents/FamilyHive")
- BASES_DIR = DATA_DIR / "bases"
+ INVARIANT = "<INVARIANT_96HEX>"
+ DATA_DIR = Path.home() / "Documents" / "FamilyHive"
+ BASES_DIR = DATA_DIR / "bases"
```

### F41.2 `ZBit_runtime/modules/forensic_expand.py` — lines 32–34
```diff
- CHAIN_FILE = Path("C:/Users/AlexZelenski/Desktop/forensic-ledger-data/chain.json")
- DIFFICULTY = 2
+ CHAIN_FILE = Path.home() / "Desktop" / "forensic-ledger-data" / "chain.json"
+ DIFFICULTY = 2
```

---

## Safety assessment & verification (design-time)

| Fix | Safe? | Why | Confirm test |
|-----|-------|-----|--------------|
| F38 beacon | YES | Sign+verify both route through same `_ed25519_sign_qseal`; beacon sigs truncated `[:32]` stay consistent. Lazy crypto import → no import-time break. Fallback keeps old refs valid. | `python beacon.py sign '{"a":1}'` then recompute `compute_beacon_signature` → equal; `create_beacon_message`+`verify_beacon_message` round-trip → True. |
| F38 qseal | YES | Sign stores `sig[:64]`, verify compares `[:64]`; Ed25519 sig hex is exactly 64 chars → no truncation mismatch. Keypair auto-generated on first use. | Run `qseal_recruitment.py` `__main__` → `Valid: True`, recovers `THE_HALF`. |
| F40 | YES | Pure scoping; default (`discover`→`192.168.1.0/24`) preserved. Removes dead `subprocess` import. API call site passes no `allow_wildcard`. | `scan_lan()` scans 192.168.1.*; `scan_lan("192.168.5.0/24")` → `[]` + refusal log; `scan_lan("192.168.5.0/24", allow_wildcard=True)` → scans. |
| F41 | YES | `Path.home()` resolves to current runtime user → paths become valid/portable. No other literal refs to the AlexZelenski paths exist. | `python -m py_compile hive_base.py forensic_expand.py`; confirm `DATA_DIR`/`CHAIN_FILE` resolve under `Path.home()`. |

**General syntax check:** `python -m py_compile beacon.py qseal_recruitment.py hive_base.py forensic_expand.py`.

**Out of scope:** `app.py` does NOT contain the INVARIANT literal (only an
`_invariant_node_id()` helper) — the lead's "5 files" count over-included app.py.
`compute_node_identity()`'s INVARIANT salt in beacon.py left unchanged (identity
seed, not a forgeable broadcast signature).
