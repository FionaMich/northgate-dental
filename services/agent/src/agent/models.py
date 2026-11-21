"""model_for(role): which model does which job (AGENTS 6). Ollama (Gemma 4) by decision of 2026-11-22; Bedrock is one
setting away. Roles: "assistant" (the conversation and tool calls)."""

import os

from langchain_core.language_models import BaseChatModel


def model_for(role: str = "assistant") -> BaseChatModel:
    provider = os.environ.get("MODEL_PROVIDER", "ollama")
    if provider == "ollama":
        from langchain_ollama import ChatOllama

        return ChatOllama(
            model=os.environ.get("OLLAMA_MODEL", "gemma4:e4b-it-qat"),
            base_url=os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434"),
            temperature=0,       # receptionist work: consistent, not creative
            num_ctx=8192,
            keep_alive="30m",    # keep the model loaded between patients
        )
    raise ValueError(f"MODEL_PROVIDER {provider!r} is not set up yet (Bedrock needs its call card and model access)")
