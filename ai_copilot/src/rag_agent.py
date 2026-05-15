from pathlib import Path

from src.llm_client import call_llm
from src.rag_retriever import retrieve_relevant_chunks


BASE_DIR = Path(__file__).resolve().parents[2]


def format_retrieved_context(chunks: list[dict]) -> str:
    context_parts = []

    for i, chunk in enumerate(chunks, start=1):
        context_parts.append(
            f"""
[Context {i}]
Source: {chunk["source"]}
Similarity Score: {chunk["score"]:.3f}

{chunk["text"]}
"""
        )

    return "\n".join(context_parts)


def answer_documentation_question(
    question: str,
    user_api_key: str | None = None,
) -> str:
    prompt_path = BASE_DIR / "ai_copilot/prompts/rag_qa_prompt.txt"
    system_prompt = prompt_path.read_text()

    chunks = retrieve_relevant_chunks(question, top_k=4)
    context = format_retrieved_context(chunks)

    user_prompt = f"""
User question:
{question}

Retrieved project documentation:
{context}

Answer the question using only the retrieved documentation.
"""

    answer = call_llm(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        temperature=0.1,
        max_output_tokens=800,
        user_api_key=user_api_key,
    )

    return answer, chunks