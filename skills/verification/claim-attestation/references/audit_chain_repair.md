# Audit-chain repair pattern (ZQM fleet_endpoint_audit.db)

## Symptom (seen 2026-07-12)
`claim_hashes` table: all 68 rows store the SAME `chain_root` (9fb4...); 68 distinct
`prev_hash` values, 0 of which equal any stored root. Rows don't chain (F1.root !=
F10.prev). => the ledger's tamper-evidence was non-functional.

## Root cause
The pointer graph (prev_hash -> prior row's claim_hash) was INTACT and well-formed.
Only the accumulated `chain_root` field was wrong — every row carried a stale
placeholder. The original writer computed per-row claim_hash but failed to chain.

## Repair (file: repair_claim_chain.py)
1. Reconstruct TRUE chain order by walking forward: next row = the one whose
   `prev_hash` == current row's `claim_hash`. (Do NOT use `generated` — constant —
   or numeric fid — non-sequential.) Verify: exactly 1 head (prev not a claim_hash),
   no cycles, all 68 reachable.
2. Recompute chain_root[i] = sha256(chain_root[i-1] || claim_hash[i]), walking the
   real order. Leave prev_hash + claim_hash UNTOUCHED (trusted inputs).
3. DRY-RUN first (read-only, prints plan). Then `--apply`: backup to
   `claim_hashes_bak_<ts>` BEFORE any UPDATE, then rewrite chain_root only.
4. Independent re-walk from a SEPARATE read-only process to confirm contiguous.

## Caveat
If `prev_hash` pointers do NOT form a clean chain (orphans/cycles), the chain is
genuinely broken and cannot be mechanically rebuilt — escalate, don't guess.
