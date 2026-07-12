# Ollama `POST /api/show` — Profiling Anatomy & the Null-`details` Pitfall

## Endpoint
```
POST http://<ip>:11434/api/show
Content-Type: application/json
{ "model": "<name>" }
```

## Top-level response keys
`license, modelfile, parameters, template, system, details, model_info,
tensors, capabilities, modified_at`

## The pitfall (verified 2026-07-10 on Node-4 192.168.1.215)
`details` for these GGUF imports looks like:
```json
"details": {
  "parent_model": "",
  "format": "gguf",
  "family": "qwen25vl",
  "families": ["qwen25vl"],
  "parameter_size": "8.3B",
  "quantization_level": "Q4_K_M"
}
```
`parameter_count`, `context_length`, and `architecture` are **absent / null** here.
A naive extractor that reads `details.parameter_count` prints `None`.

## Authoritative values are in `model_info`
`model_info` carries the raw GGUF metadata header. Real examples pulled live:
```
general.architecture        = "llama" | "qwen2" | "qwen3" | "qwen25vl" | "bert"
general.parameter_count     = 70600000000.0   (float; /1e9 -> "70.6B")
general.file_type           = <int quant code>   (use details.quantization_level instead)
llama.context_length        = 131072
qwen2.context_length        = 32768
qwen3.context_length        = 40960
qwen25vl.context_length     = 128000
bert.context_length         = 8192
```

## Extraction rule (use this order)
- architecture: `details.family` OR `model_info["general.architecture"]`
- params:       `model_info["general.parameter_count"]` (float, /1e9) ELSE `details.parameter_size`
- context:      `model_info[f"{arch}.context_length"]` ELSE `model_info["general.context_length"]`
- quant:        `details.quantization_level`  (reliable human string)
- format:       `details.format`  (reliable)

## Worked example (real output)
```
deepseek-r1:70b | params=70.6B | quant=Q4_K_M | ctx=131072 | arch=llama | fmt=gguf
qwq:32b         | params=32.8B | quant=Q4_K_M | ctx=40960  | arch=qwen2 | fmt=gguf
qwen2.5:72b     | params=72.7B | quant=Q4_K_M | ctx=32768  | arch=qwen2 | fmt=gguf
llama3.3:70b    | params=70.6B | quant=Q4_K_M | ctx=131072 | arch=llama | fmt=gguf
qwen3:32b       | params=32.8B | quant=Q4_K_M | ctx=40960  | arch=qwen3 | fmt=gguf
qwen2.5-coder:32b | params=32.8B | quant=Q4_K_M | ctx=32768 | arch=qwen2 | fmt=gguf
qwen2.5vl:7b    | params=8.3B  | quant=Q4_K_M | ctx=128000 | arch=qwen25vl | fmt=gguf
bge-m3:latest   | params=0.6B  | quant=F16    | ctx=8192   | arch=bert  | fmt=gguf
```

## Other quirks
- `curl -s -o /dev/null -w '%{time_connect} %{time_total}'` may exit 23 (write error) in
  MSYS even on success — trust the printed timing numbers, not the exit code.
- `bge-m3` is the only F16 (non-Q4) model on the fleet and is a `bert` embedder, not a
  generative LLM — don't put it in a chat/reasoning column.
- Context lengths vary 8192 -> 32768 -> 40960 -> 128000 -> 131072; only deepseek-r1/llama3.3
  (131072) and qwen2.5vl (128000) reach 128K+.
