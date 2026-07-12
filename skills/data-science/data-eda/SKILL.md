---
name: data-eda
description: Reusable pandas/Python exploratory data analysis pattern for ZQM audit
  number-crunching — load messy CSV/JSON/SQLite, profile columns, summarize with REAL
  numbers, and emit a compact finding table. Use when an audit or fleet inventory
  produces raw data that must be turned into honest statistics (counts, distributions,
  deltas) rather than hand-waved. Pairs with audit-sqlite-sink (read the audit DB,
  crunch it).
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags:
    - zqm
    - eda
    - pandas
    - data-analysis
    - audit-numbers
    - sqlite
    related_skills:
    - audit-sqlite-sink
    - fleet-council-audit
    - jupyter-live-kernel
    - verified-repo-diagnostics
    - windows-host-audit
    - zqm-ollama-fleet
    - zqm-systems-review
---
# Data EDA — honest numbers from raw audit data

## When to use
- A council/audit produced CSV/JSON/SQLite that needs summarizing with REAL stats.
- "How many nodes exposed?", "what's the VRAM distribution?", "delta vs last inventory".
- Any task where the user wants emitted NUMBERS, not prose ("reject PASS/PROMOTABLE").

## Pattern (stdlib + pandas; no magic)
1. LOAD explicitly; name the source file and row count you actually read.
   ```python
   import pandas as pd, sqlite3
   df = pd.read_csv("inventory.csv")          # or pd.read_json, or from sqlite:
   # con = sqlite3.connect("audit.db"); df = pd.read_sql("SELECT * FROM nodes", con)
   print("rows:", len(df), "cols:", list(df.columns))
   ```
2. PROFILE: dtype + null count per column. Never assume a column is clean.
   ```python
   print(df.dtypes); print(df.isna().sum())
   ```
3. SUMMARIZE with explicit aggregations the user can read:
   ```python
   print(df["models"].sum(), "total models across", df["node"].nunique(), "nodes")
   print(df.groupby("ollama_lan_exposed").size())   # exposed vs not
   print(df["size_gb"].describe())                  # VRAM/footprint spread
   ```
4. DELTA vs a prior snapshot (if you have one): merge on key, compute diff, report sign.
   ```python
   prev = pd.read_csv("prev.csv"); m = df.merge(prev, on="node", suffixes=("_now","_prev"))
   print((m["size_gb_now"] - m["size_gb_prev"]).sum(), "GB changed vs prior")
   ```
5. EMIT a compact finding table (markdown or just printed rows) — counts, not verdicts.

## Real-number discipline (user's standing rule)
- Print the actual computed value AND its plain-language meaning.
- If a column is all-null, SAY so — don't drop it silently to make the table look full.
- Cross-check a summary total against `len(df)` so you didn't filter rows by accident.

## Reusable from an audit DB
Read the `audit-sqlite-sink` DB and crunch:
```python
con = sqlite3.connect("fleet_swarm_20260711.db")
nodes = pd.read_sql("SELECT node, models, size_gb, verdict FROM nodes", con)
print(nodes["models"].sum(), "models;", nodes["size_gb"].sum().round(1), "GB")
print(nodes["verdict"].value_counts())
```

## Pitfalls
- `pd.read_csv` silently coercing a column to float (nulls) → check dtypes first.
- Summarizing before checking for duplicate rows (double-counts).
- Reporting a percentage without the n it came from.
- Using `df.describe()` as the whole answer — it's a starting point, not the finding.

## References
- audit-sqlite-sink (the DB this reads)
- jupyter-live-kernel (iterative exploration alternative)
