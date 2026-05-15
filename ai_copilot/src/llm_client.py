import os
from typing import Optional

import streamlit as st
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()


def get_api_key(user_api_key: Optional[str] = None) -> str:
    """
    API key priority:
    1. Key entered in Streamlit UI
    2. Streamlit secrets
    3. .env / environment variable
    """

    if user_api_key:
        return user_api_key

    try:
        if "OPENAI_API_KEY" in st.secrets:
            return st.secrets["OPENAI_API_KEY"]
    except Exception:
        pass

    env_key = os.getenv("OPENAI_API_KEY")
    if env_key:
        return env_key

    raise ValueError(
        "OPENAI_API_KEY not found. Add it to Streamlit secrets, .env, "
        "environment variables, or enter it in the app sidebar."
    )


def get_openai_client(user_api_key: Optional[str] = None) -> OpenAI:
    api_key = get_api_key(user_api_key)
    return OpenAI(api_key=api_key)


def call_llm(
    system_prompt: str,
    user_prompt: str,
    model: str = "gpt-4.1-mini",
    temperature: float = 0.2,
    max_output_tokens: int = 900,
    user_api_key: Optional[str] = None,
) -> str:
    client = get_openai_client(user_api_key=user_api_key)

    response = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        temperature=temperature,
        max_output_tokens=max_output_tokens,
    )

    return response.output_text