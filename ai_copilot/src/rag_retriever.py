from pathlib import Path
from typing import List, Dict

import faiss
import numpy as np
from sentence_transformers import SentenceTransformer


BASE_DIR = Path(__file__).resolve().parents[2]
KB_DIR = BASE_DIR / "ai_copilot" / "knowledge_base"

MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"


def load_knowledge_documents() -> List[Dict[str, str]]:
    docs = []

    for path in sorted(KB_DIR.glob("*.md")):
        text = path.read_text(encoding="utf-8")

        chunks = chunk_text(text)

        for i, chunk in enumerate(chunks):
            docs.append({
                "source": path.name,
                "chunk_id": f"{path.name}_{i}",
                "text": chunk
            })

    return docs


def chunk_text(text: str, max_chars: int = 900, overlap: int = 150) -> List[str]:
    text = text.strip()

    if len(text) <= max_chars:
        return [text]

    chunks = []
    start = 0

    while start < len(text):
        end = start + max_chars
        chunk = text[start:end].strip()

        if chunk:
            chunks.append(chunk)

        start = end - overlap

    return chunks


import streamlit as st

@st.cache_resource
def build_faiss_index():
    docs = load_knowledge_documents()

    if not docs:
        raise ValueError("No knowledge base documents found in ai_copilot/knowledge_base/")

    model = SentenceTransformer(MODEL_NAME)

    texts = [doc["text"] for doc in docs]
    embeddings = model.encode(texts, convert_to_numpy=True, normalize_embeddings=True)

    index = faiss.IndexFlatIP(embeddings.shape[1])
    index.add(embeddings.astype(np.float32))

    return model, index, docs


def retrieve_relevant_chunks(question: str, top_k: int = 4) -> List[Dict[str, str]]:
    model, index, docs = build_faiss_index()

    query_embedding = model.encode(
        [question],
        convert_to_numpy=True,
        normalize_embeddings=True
    ).astype(np.float32)

    scores, indices = index.search(query_embedding, top_k)

    results = []

    for score, idx in zip(scores[0], indices[0]):
        if idx == -1:
            continue

        result = docs[idx].copy()
        result["score"] = float(score)
        results.append(result)

    return results