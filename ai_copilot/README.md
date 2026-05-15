## AI-Powered Analytics Copilot

This project includes a GenAI layer that turns the analytics outputs into an interactive business assistant for product, marketing, and executive stakeholders.

The copilot supports four workflows:

1. **Executive Summary**
   - Generates stakeholder-ready summaries from Tableau exports, model outputs, and experiment results.

2. **Experiment Analyst**
   - Explains treatment/control performance, conversion lift, revenue lift, confidence intervals, and rollout recommendations.

3. **Metric & Methodology Q&A**
   - Uses RAG over project documentation to answer questions about metric definitions, SQL logic, dashboard methodology, modeling assumptions, and experimentation design.

4. **Ask Your Metrics**
   - Answers natural-language questions over curated KPI, category, customer segment, model, and experiment output files.

### AI Stack

- Streamlit for app UI
- OpenAI API for LLM reasoning and summarization
- SentenceTransformers for local embeddings
- FAISS for vector search
- Pandas for structured output handling
- Curated CSV outputs from BigQuery/Tableau/Python pipelines

The app includes **Demo Mode**, which shows saved AI-generated examples without requiring an API key or making live OpenAI calls.

### Run the AI Copilot Locally

```bash
streamlit run ai_copilot/app.py