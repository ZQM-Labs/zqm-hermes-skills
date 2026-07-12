# Indexer Rebuild Protocol

## Lockfile inspection

Before any `build_index(rebuild=True)` run on this host:

\`\`\`
find <INDEX_DIR> -maxdepth 1 -name '*lock*' -o -name '*WRITELOCK*'
ls -la <INDEX_DIR>/MAIN_WRITELOCK
\`\`\`

If `MAIN_WRITELOCK` exists and is 0 bytes, that is a stale Whoosh lock.

## Process ownership check

Check active Python processes and port listeners on the indexer port. If no legitimate writer is active, remove the lock and rerun.

## Windows taskkill syntax pitfall

On this Windows host, `taskkill //F` fails with "Invalid argument/option". Use `taskkill /F /PID <pid>` instead.

## Background rebuild pattern

Long rebuilds should use `terminal(background=true, notify_on_complete=true)` so the session does not time out. After starting, monitor with `process(action="poll", session_id=...)`.

## Rebuild verification

After rebuild completes:
1. `/api/config` should show updated `root_paths`
2. `/api/search` should return scoped results instead of AlexZ noise
3. Auth endpoints should return `authenticated:true` when bearer token is provided
