from pathlib import Path
import pandas as pd

from src.llm_client import call_llm


BASE_DIR = Path(__file__).resolve().parents[2]


def safe_read_csv(path: Path) -> pd.DataFrame | None:
    if path.exists():
        return pd.read_csv(path)
    return None


def dataframe_preview(df: pd.DataFrame | None, max_rows: int = 15) -> str:
    if df is None:
        return "File not found."
    return df.head(max_rows).to_markdown(index=False)


def build_experiment_context() -> str:
    files = {
        "Experiment Group Summary": BASE_DIR / "outputs/experiment_group_summary.csv",
        "Experiment Lift Results": BASE_DIR / "outputs/experiment_lift_results.csv",
        "Experiment Revenue Bootstrap CI": BASE_DIR / "outputs/experiment_revenue_bootstrap_ci.csv",
        "Experiment Segment Lift": BASE_DIR / "outputs/experiment_segment_lift.csv",
    }

    context_parts = []

    for label, path in files.items():
        df = safe_read_csv(path)

        if label == "Experiment Segment Lift" and df is not None:
            if "revenue_per_user_lift" in df.columns:
                df = df.sort_values("revenue_per_user_lift", ascending=False).head(max_rows := 20)

        context_parts.append(f"\n## {label}\n")
        context_parts.append(dataframe_preview(df, max_rows=20))

    return "\n".join(context_parts)


def answer_experiment_question(
    question: str,
    user_api_key: str | None = None,
) -> str:
    prompt_path = BASE_DIR / "ai_copilot/prompts/experiment_analyst_prompt.txt"
    system_prompt = prompt_path.read_text()

    context = build_experiment_context()

    user_prompt = f"""
User question:
{question}

Experiment data:
{context}

Answer the user's question using only the experiment data above.
"""

    return call_llm(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        temperature=0.2,
        max_output_tokens=1000,
        user_api_key=user_api_key,
    )