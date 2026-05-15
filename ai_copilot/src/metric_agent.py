from pathlib import Path
import pandas as pd

from src.llm_client import call_llm


BASE_DIR = Path(__file__).resolve().parents[2]


def safe_read_csv(path: Path) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(f"Missing required file: {path}")
    return pd.read_csv(path)


def classify_metric_question(question: str) -> str:
    q = question.lower()

    if any(term in q for term in ["overall", "summary", "kpi", "revenue", "sessions", "active users", "aov"]):
        return "overall_kpis"

    if any(term in q for term in ["category", "product category", "top category"]):
        return "top_categories"

    if any(term in q for term in ["segment", "customer segment", "revenue per user"]):
        return "segment_revenue"

    if any(term in q for term in ["funnel", "drop-off", "dropoff", "checkout", "cart"]):
        return "funnel_dropoff"

    if any(term in q for term in ["model", "propensity", "roc", "pr-auc", "lift"]):
        return "model_performance"

    if any(term in q for term in ["experiment", "email", "treatment", "control", "a/b", "ab test"]):
        return "experiment_performance"

    return "overall_kpis"


def get_metric_result(question: str) -> tuple[str, pd.DataFrame, str]:
    intent = classify_metric_question(question)

    if intent == "overall_kpis":
        df = safe_read_csv(BASE_DIR / "data/tableau_exports/tableau_executive_scorecard.csv")
        source = "data/tableau_exports/tableau_executive_scorecard.csv"
        return intent, df.head(10), source

    if intent == "top_categories":
        df = safe_read_csv(BASE_DIR / "data/tableau_exports/tableau_category_performance.csv")

        revenue_col = next(
            (col for col in df.columns if "revenue" in col.lower()),
            None
        )

        if revenue_col:
            df = df.sort_values(revenue_col, ascending=False).head(10)
        else:
            df = df.head(10)

        source = "data/tableau_exports/tableau_category_performance.csv"
        return intent, df, source

    if intent == "segment_revenue":
        df = safe_read_csv(BASE_DIR / "data/tableau_exports/tableau_segment_summary.csv")

        sort_col = next(
            (col for col in df.columns if "revenue_per_user" in col.lower() or "revenue per user" in col.lower()),
            None
        )

        if sort_col:
            df = df.sort_values(sort_col, ascending=False).head(10)
        else:
            df = df.head(10)

        source = "data/tableau_exports/tableau_segment_summary.csv"
        return intent, df, source

    if intent == "funnel_dropoff":
        df = safe_read_csv(BASE_DIR / "data/tableau_exports/tableau_funnel_daily.csv")
        source = "data/tableau_exports/tableau_funnel_daily.csv"
        return intent, df.head(15), source

    if intent == "model_performance":
        metrics = safe_read_csv(BASE_DIR / "outputs/model_metrics.csv")
        lift = safe_read_csv(BASE_DIR / "outputs/top_percentile_lift.csv")

        df = pd.concat(
            [
                metrics.head(10).assign(source_table="model_metrics"),
                lift.head(10).assign(source_table="top_percentile_lift")
            ],
            ignore_index=True
        )

        source = "outputs/model_metrics.csv; outputs/top_percentile_lift.csv"
        return intent, df, source

    if intent == "experiment_performance":
        df = safe_read_csv(BASE_DIR / "outputs/experiment_lift_results.csv")
        source = "outputs/experiment_lift_results.csv"
        return intent, df, source

    raise ValueError(f"Unsupported intent: {intent}")


def answer_metric_question(
    question: str,
    user_api_key: str | None = None,
) -> tuple[str, pd.DataFrame, str, str]:
    intent, result_df, source = get_metric_result(question)

    prompt_path = BASE_DIR / "ai_copilot/prompts/metric_analyst_prompt.txt"
    system_prompt = prompt_path.read_text()

    result_markdown = result_df.head(15).to_markdown(index=False)

    user_prompt = f"""
User question:
{question}

Classified intent:
{intent}

Source file:
{source}

Result table:
{result_markdown}

Answer the user's question using only the result table.
"""

    answer = call_llm(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        temperature=0.1,
        max_output_tokens=700,
        user_api_key=user_api_key,
    )

    return answer, result_df, source, intent