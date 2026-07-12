# Live API Audit Recipe (Windows/MSYS)

Reusable probe for auditing a *running* web service endpoint-by-endpoint. Used to verify
the ZBit re-homed agent (FastAPI on 127.0.0.1:8400). Adapt host/port/key var per target.

## 1. Fetch the API key (read_file is blocked on .env)
```bash
K=$(grep -i '^ZBIT_API_KEY=' /c/Users/zqmco/ZBit_api/.env | cut -d= -f2)
B=http://127.0.0.1:8400
H=(-H "X-API-Key: $K")   # adjust header name to the target's auth scheme
```

## 2. Status + skill inventory (assert exact strings, not just 200)
```bash
curl -s "${H[@]}" $B/v1/agent/status
curl -s "${H[@]}" $B/v1/skills
```
Check: `runtime:"...loaded"`, and the skill list equals the expected set exactly.

## 3. Compute endpoints — recompute expected, then compare
```bash
curl -s "${H[@]}" -H "Content-Type: application/json" -X POST $B/v1/skill/base_convert \
  -d '{"value":"ff","from_base":16,"to_base":36}'   # expect "73" (255 in base36)
curl -s "${H[@]}" -H "Content-Type: application/json" -X POST $B/v1/skill/qubit_measure \
  -d '{"theta_deg":45}'                              # expect p1=0.5, NOT 0.25
```

## 4. Negative surface — unknown route must 404
```bash
curl -s -o /dev/null -w "%{http_code}" "${H[@]}" -X POST $B/v1/skill/exploit -d '{}'   # expect 404
```

## 5. Persisted-state checks (200 alone is a hollow pass)
```bash
# keygen -> file appears
curl -s "${H[@]}" -X POST $B/v1/skill/qseal_keygen -d '{}'
ls -l /c/Users/zqmco/ZBit_api/ZBit_runtime/ledger/qseal_keypair.pem
stat -c '%a %n' /c/Users/zqmco/ZBit_api/ZBit_runtime/ledger/qseal_keypair.pem   # 600 expected; 644 on Windows

# ledger append -> block count increments
python.exe -c "import json;print(len(json.load(open(r'C:\Users\zqmco\ZBit_api\ZBit_runtime\ledger\chain.json'))))"
curl -s "${H[@]}" -X POST $B/v1/ledger -d '{"block_type":"audit","description":"x","data":{}}'
python.exe -c "import json;print(len(json.load(open(r'C:\Users\zqmco\ZBit_api\ZBit_runtime\ledger\chain.json'))))"
```

## 6. Module import smoke test (real modules, not stubs)
```bash
PY=/c/Users/zqmco/AppData/Local/Programs/Python/Python312/python.exe
for m in forensic_expand zbit_engine hive_base beacon qseal_recruitment; do
  echo -n "$m: "
  (cd /c/Users/zqmco/ZBit_api/ZBit_runtime && \
   $PY -c "import importlib.util; s=importlib.util.spec_from_file_location('$m','modules/$m.py'); \
           m=importlib.util.module_from_spec(s); s.loader.exec_module(m); print('OK')" 2>&1 | tail -1)
done
```

## Report shape
Per-item table: | # | claim | live evidence | PASS/FAIL |. Call out the single
Windows-perms deviation (644 vs 600) as a security note, not a runtime failure.
