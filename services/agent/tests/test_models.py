"""model_for: the settings that decide how long a patient waits (measured on staging 2026-11-23: thinking on, 137 s for one
short reply; off, 4 s)."""

from agent.models import model_for


def test_gemma_answers_without_hidden_thinking():
    assert model_for("assistant").reasoning is False


def test_the_server_decides_how_long_gemma_stays_loaded():
    # Ollama's OLLAMA_KEEP_ALIVE (24h in compose) applies only when the request does not override it.
    assert model_for("assistant").keep_alive is None
