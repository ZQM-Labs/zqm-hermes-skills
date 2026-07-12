# Council Probe Notes

## ZQM-AI-Council Repo Structure
- Private repo: `ZQM-Computing/ZQM-AI-Council` on GitHub
- Default branch: `master`
- Notable files: `service.py`, `council_engine.py`, `config.py`, `requirements.txt`, `run_council.ps1`, `board_zqm_computing.json`

## Expected Routes
- `/council/topic` — POST topic
- `/council/round` — POST run round
- `/council/summarize` — POST summarize
- `/council/board` — GET board state
- `/council/last` — GET last messages
- `/agent/tool` — POST tool agent
- `/tool` — POST tool dispatch
- `/health` — GET health
- Default port: `8000`

## Auth
- When `ZQM_COUNCIL_TOKEN` is set, `/tool` and `/agent/tool` require bearer/header auth; fail closed.
- `curl -H "Authorization: Bearer <token>"` shape used in smoke tests.

## Backend Dependency
- Engine defaults to Ollama at `http://127.0.0.1:11434/api/generate`
- `/health` degrades when Ollama is missing
- Council is non-functional without a reachable model backend or configured adapter

## Negative Result Pattern
- SAC on port 9000 returns 404 for all `/council/*`, `/api/council/*`, `/health`, `/api/health`
- Do not blind-retry missing SAC council routes; invoke standalone repo code or report routing gap.