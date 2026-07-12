# Ollama adaptive model resolution

## Problem
Local code paths often hardcode a preferred model name. When that model is absent, generation can fail silently, hang, or time out without indicating the real cause is a missing catalog entry.

## Preferred pattern
1. Discover installed models once from `POST http://127.0.0.1:11434/api/tags` with a short timeout.
2. Cache the result for the process lifetime.
3. Resolve by preference order:
   - explicit env override, if set and present
   - site default
   - first installed model
   - fallback to the preferred name only as a last resort for diagnostics
4. Use the resolved model for every actual generate request.

## Why this is better than hardcoded fallbacks
- Removes the hidden dependency on a single model name.
- Makes runtime behavior match local inventory automatically.
- Makes troubleshooting explicit: if every installed model is unavailable, resolution is still predictable.

## Reuse hints
Apply this to:
- council deliberation engines
- service backends that call `/api/generate` directly
- any ad-hoc verification that needs actual generation on a changing host

## Caveats
- Model discovery is I/O; cache aggressively.
- Large-model generation can still time out on limited-RAM Windows hosts; use the model-fit guidance in `council-runtime-model-fit.md` for size/context tuning.
