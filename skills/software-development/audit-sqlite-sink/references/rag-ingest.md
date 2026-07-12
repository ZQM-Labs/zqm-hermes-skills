# Memory -> vectorization system ingestion (proven ZQM 2026-07-11)

"memory to sql vectorization systems" = feed durable audit memory + ledger
findings into an in-repo RAG. The target was `ZQM-AI-Council/rag/`.

## What the target actually is (locate before writing)
- `rag/embeddings.py` -> `LocalAIEmbeddings` POSTs to LocalAI `/v1/embeddings` (384-dim).
- `rag/retriever.py` -> `RAGRetriever` holds docs + embeddings in **in-memory
  Python lists**, cosine-sim over them. **NO SQLite/Chroma/FAISS sink.** "Vectorization"
  is ephemeral per-process.
- `config.py` defines `DATA_DIR=data/`, `data/documents/`, `data/embeddings/`
  but those dirs may NOT exist yet (create them).
- `rag/document_loader.py` -> `DocumentLoader.load_text` chunks text into
  `{content, source, start, end}` dicts.

## GOTCHAS that burned turns
1. **It is NOT a SQL store.** Do not assume "vectorization" = SQLite.
   The retriever is lists. Persistence is up to you (or absent).
2. **Probe the embedding endpoint BEFORE writing.** `LocalAIEmbeddings.embed_query()`
   fails to a **384-dim ZERO vector** when the backend is down. Ingesting then =
   fabricating meaningless vectors (every doc scores 0.0 on retrieve).
   - Check: `netstat` for a LocalAI port (8080/8081/3928/8899); OR
     `urllib` POST a test embed to Ollama `:11434/api/embed` (may 404 if no
     embedding model loaded). If dead -> REFUSE to vectorize.
3. **Instead, pre-build the corpus + record the blocker.** Chunk the ledger memory
   into the repo's own DocumentLoader schema, persist to `data/documents/`,
   and write a `_INGEST_STATUS.json` saying `vectorization_status=NOT_VECTORIZED`
   + the exact command to finish (`python rag/ingest_corpus.py` once backend up).

## Reusable ingest script shape
```python
import sys, os, json
sys.path.insert(0, COUNCIL_ROOT)
from rag.document_loader import DocumentLoader
from rag.embeddings import LocalAIEmbeddings
from rag.retriever import RAGRetriever
chunks = json.load(open(corpus_path))
docs = [{"content": c["content"], "source": c.get("source","mem")} for c in chunks]
emb = LocalAIEmbeddings()               # reads API_BASE_URL from config/.env
retriever = RAGRetriever(embeddings=emb)
retriever.add_documents(docs)           # embeds each -> populates lists
res = retriever.retrieve("critical N2 Redis exposure?")
```
Run `python rag/ingest_corpus.py` from the council root once the endpoint is live.
Smoke test: retrieve a known claim -> expect real hits (threshold 0.75); if 0,
the endpoint is not actually serving.

## Honesty rule
Never write zero-vectors into a retriever and call it "vectorized." Build the
corpus, gate on a live endpoint, leave a one-command finish. That is the
verifiable deliverable; the embed step is the user's go (or yours, once you
stand the backend up).
