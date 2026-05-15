import streamlit as st
import sys
from pathlib import Path

CURRENT_DIR = Path(__file__).resolve().parent
sys.path.append(str(CURRENT_DIR))
from pathlib import Path

from src.summary_agent import generate_executive_summary
from src.experiment_agent import answer_experiment_question
from src.rag_agent import answer_documentation_question
from src.metric_agent import answer_metric_question


BASE_DIR = Path(__file__).resolve().parents[1]


def load_demo_output(file_name: str) -> str:
    path = BASE_DIR / "ai_copilot" / "demo_outputs" / file_name
    if path.exists():
        return path.read_text(encoding="utf-8")
    return "Demo output file not found."


def escape_markdown_dollars(text: str) -> str:
    return text.replace("$", "\\$")


st.set_page_config(
    page_title="AI-Powered E-Commerce Analytics Copilot",
    layout="wide",
)

st.title("AI-Powered E-Commerce Analytics Copilot")
st.caption(
    "GenAI layer for KPI interpretation, metric documentation, executive summaries, and experiment analysis."
)

# -----------------------------
# Sidebar
# -----------------------------
st.sidebar.caption(
    "Enter your own OpenAI API key to run live GenAI features. "
    "The key is used only for this session and is not stored."
)

user_api_key = st.sidebar.text_input(
    "OpenAI API Key",
    type="password",
    help="Optional locally. For deployment, use Streamlit Secrets or Demo Mode."
)

demo_mode = st.sidebar.toggle(
    "Demo Mode",
    value=False,
    help="Use saved sample AI outputs without calling the OpenAI API."
)

if user_api_key:
    st.sidebar.success("API key added for this session.")

module = st.sidebar.radio(
    "Choose module",
    [
        "Executive Summary",
        "Experiment Analyst",
        "Metric & Methodology Q&A",
        "Ask Your Metrics",
    ],
)

# -----------------------------
# Executive Summary
# -----------------------------
if module == "Executive Summary":
    st.header("Executive Summary")
    st.write(
        "Generates a stakeholder-ready summary from Tableau export files, model outputs, and experiment results."
    )

    if st.button("Generate Executive Summary"):
        if demo_mode:
            summary = load_demo_output("executive_summary_demo.md")
        else:
            with st.spinner("Generating summary..."):
                summary = generate_executive_summary(user_api_key=user_api_key)

        st.markdown(escape_markdown_dollars(summary))

        with st.expander("View source files used"):
            st.markdown(
                """
                - `data/tableau_exports/tableau_executive_scorecard.csv`
                - `data/tableau_exports/tableau_funnel_daily.csv`
                - `data/tableau_exports/tableau_category_performance.csv`
                - `data/tableau_exports/tableau_segment_summary.csv`
                - `outputs/model_metrics.csv`
                - `outputs/experiment_lift_results.csv`
                - `outputs/experiment_revenue_bootstrap_ci.csv`
                """
            )

# -----------------------------
# Experiment Analyst
# -----------------------------
elif module == "Experiment Analyst":
    st.header("Experiment Analyst")
    st.write(
        "Ask questions about the email campaign experiment, treatment lift, revenue impact, and rollout recommendations."
    )

    example_questions = [
        "Should we roll out Mens E-Mail?",
        "Which email campaign performed best?",
        "Was the revenue lift statistically significant?",
        "Which customer segments responded best to the campaign?",
        "Should we continue testing Womens E-Mail?",
    ]

    selected_question = st.selectbox(
        "Choose an example question",
        [""] + example_questions,
    )

    custom_question = st.text_area(
        "Or ask your own experiment question",
        value=selected_question,
        height=100,
    )

    if st.button("Analyze Experiment"):
        if not custom_question.strip():
            st.warning("Enter a question first.")
        else:
            if demo_mode:
                answer = load_demo_output("experiment_analyst_demo.md")
            else:
                with st.spinner("Analyzing experiment results..."):
                    answer = answer_experiment_question(
                        custom_question,
                        user_api_key=user_api_key,
                    )

            st.markdown(escape_markdown_dollars(answer))

            with st.expander("View source files used"):
                st.markdown(
                    """
                    - `outputs/experiment_group_summary.csv`
                    - `outputs/experiment_lift_results.csv`
                    - `outputs/experiment_revenue_bootstrap_ci.csv`
                    - `outputs/experiment_segment_lift.csv`
                    """
                )

# -----------------------------
# Metric & Methodology Q&A
# -----------------------------
elif module == "Metric & Methodology Q&A":
    st.header("Metric & Methodology Q&A")
    st.write(
        "Ask questions about metric definitions, SQL logic, dashboard methodology, modeling assumptions, and experimentation design."
    )

    example_questions = [
        "How is purchase conversion rate calculated?",
        "What does cart abandonment rate mean?",
        "Which table powers the funnel dashboard?",
        "How was leakage avoided in the purchase propensity model?",
        "Why is PR-AUC more useful than accuracy in this model?",
        "How was the email campaign experiment evaluated?",
    ]

    selected_question = st.selectbox(
        "Choose an example documentation question",
        [""] + example_questions,
    )

    rag_question = st.text_area(
        "Or ask your own documentation question",
        value=selected_question,
        height=100,
    )

    if st.button("Answer Documentation Question"):
        if not rag_question.strip():
            st.warning("Enter a question first.")
        else:
            if demo_mode:
                rag_answer = load_demo_output("rag_demo.md")
                st.markdown(escape_markdown_dollars(rag_answer))
            else:
                with st.spinner("Retrieving relevant documentation and generating answer..."):
                    rag_answer, retrieved_chunks = answer_documentation_question(
                        rag_question,
                        user_api_key=user_api_key,
                    )

                st.markdown(escape_markdown_dollars(rag_answer))

                with st.expander("View retrieved documentation sources"):
                    for chunk in retrieved_chunks:
                        st.markdown(f"**Source:** `{chunk['source']}`")
                        st.markdown(f"**Similarity Score:** `{chunk['score']:.3f}`")
                        st.text(chunk["text"][:700])

# -----------------------------
# Ask Your Metrics
# -----------------------------
elif module == "Ask Your Metrics":
    st.header("Ask Your Metrics")
    st.write(
        "Ask natural-language questions over curated KPI, category, segment, model, and experiment outputs."
    )

    example_questions = [
        "What are the overall KPIs?",
        "Which product categories generated the most revenue?",
        "Which customer segment has the highest revenue per user?",
        "Where are the biggest funnel drop-offs?",
        "How did the purchase propensity model perform?",
        "Which email experiment treatment performed best?",
    ]

    selected_question = st.selectbox(
        "Choose an example metric question",
        [""] + example_questions,
    )

    metric_question = st.text_area(
        "Or ask your own metric question",
        value=selected_question,
        height=100,
    )

    if st.button("Ask Metric Question"):
        if not metric_question.strip():
            st.warning("Enter a question first.")
        else:
            if demo_mode:
                metric_answer = load_demo_output("metric_question_demo.md")
                st.markdown(escape_markdown_dollars(metric_answer))
            else:
                with st.spinner("Querying analytics outputs and generating answer..."):
                    metric_answer, result_df, source, intent = answer_metric_question(
                        metric_question,
                        user_api_key=user_api_key,
                    )

                st.markdown(escape_markdown_dollars(metric_answer))

                with st.expander("View supporting data"):
                    st.caption(f"Intent: `{intent}`")
                    st.caption(f"Source: `{source}`")
                    st.dataframe(result_df, use_container_width=True)