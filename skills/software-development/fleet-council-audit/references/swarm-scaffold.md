# Swarm scaffold for fleet-council-audit
# Use when the audit needs cross-checked / dependent work, not just parallel slices.

## 1. Init blackboard (lead runs first, via terminal)
run_id=$(date +%Y%m%d_%H%M%S)
mkdir -p "C:/Users/zqmco/swarm/$run_id"
cat > "C:/Users/zqmco/swarm/$run_id/blackboard.md" <<'EOF'
# SWARM BLACKBOARD — run <run_id>

## GOAL
<one-line: what the swarm must converge on>

## KNOWN FACTS (seed)
- Control plane: 192.168.1.218 (ZQM-NODE-1)
- Fleet nodes: .21 .46 .215  (NAS .173)
- Prior claim to test: Nodes 1/2/4 LAN-expose Ollama; Node-3 localhost-bound

## ROUND 1 FINDINGS
(leaves append here)

## OPEN QUESTIONS / CONTRADICTIONS
(leaves append; lead closes between rounds)

## ROUND 2..N FINDINGS
(append)

## CONVERGENCE
- UNRESOLVED: <list anything that could not be verified>
EOF

## 2. Dispatch round 1 (the original 3-leaf fan-out)
# delegate_task(tasks=[SecuritySvc, FleetCensus, StorageNet])
# Each leaf context MUST include:
#   "Shared blackboard: C:\Users\zqmco\swarm\<run_id>\blackboard.md
#    READ it first. APPEND your slice under 'ROUND 1 FINDINGS' with a
#    '### <your-slice>' heading. List any contradiction in 'OPEN QUESTIONS'."
# Leaves write via write_file (append) — do NOT rely on conversation sharing.

## 3. Lead reads blackboard, decides round 2
# read_file("C:/Users/zqmco/swarm/<run_id>/blackboard.md")
# Collect every line under OPEN QUESTIONS. For each contradiction, spawn a
# focused round-2 leaf that RE-PROBES ONLY that node/claim (cheaper, targeted).
# Example round-2 task:
#   "Re-probe 192.168.1.46:11434 from control plane. Prior round claimed it
#    times out. Confirm with 3x curl --max-time 5 and a TCP port scan. Append
#    to blackboard ROUND 2 FINDINGS. Close or re-state the OPEN QUESTION."

## 4. Convergence test (lead, before final report)
# - All OPEN QUESTIONS either resolved or marked UNVERIFIABLE.
# - Headlines independently re-verified by lead (see SKILL.md re-verify gate).
# - Max ~4 rounds; stop and report unresolved rather than loop forever.

## 5. Final report cites the blackboard path so the run is reproducible/auditable.
