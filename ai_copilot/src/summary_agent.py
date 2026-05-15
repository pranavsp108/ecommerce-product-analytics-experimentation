from pathlib import Path
import pandas as pd

from src.llm_client import call_llm


BASE_DIR = Path(__file__).resolve().parents[2]


def safe_read_csv(path: Path) -> pd.DataFrame | None:
    if path.exists():
        return pd.read_csv(path)
    return None


def dataframe_preview(df: pd.DataFrame, max_rows: int = 10) -> str:
    if df is None:
        return "File not found."
    return df.head(max_rows).to_markdown(index=False)


def build_summary_context() -> str:
    files = {
        "Executive Scorecard": BASE_DIR / "data/tableau_exports/tableau_executive_scorecard.csv",
        "Funnel Daily": BASE_DIR / "data/tableau_exports/tableau_funnel_daily.csv",
        "Category Performance": BASE_DIR / "data/tableau_exports/tableau_category_performance.csv",
        "Segment Summary": BASE_DIR / "data/tableau_exports/tableau_segment_summary.csv",
        "Model Metrics": BASE_DIR / "outputs/model_metrics.csv",
        "Experiment Lift Results": BASE_DIR / "outputs/experiment_lift_results.csv",
        "Experiment Revenue Bootstrap CI": BASE_DIR / "outputs/experiment_revenue_bootstrap_ci.csv",
    }

    context_parts = []

    for label, path in files.items():
        df = safe_read_csv(path)
        context_parts.append(f"\n## {label}\n")
        context_parts.append(dataframe_preview(df))

    return "\n".join(context_parts)


def generate_executive_summary(user_api_key: str | None = None) -> str:
    prompt_path = BASE_DIR / "ai_copilot/prompts/executive_summary_prompt.txt"
    system_prompt = prompt_path.read_text()

    context = build_summary_context()

    user_prompt = f"""
Generate an executive business summary for the e-commerce analytics project using the data below.

Structured data:
{context}
"""

    return call_llm(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        temperature=0.2,
        max_output_tokens=1000,
        user_api_key=user_api_key,
    )