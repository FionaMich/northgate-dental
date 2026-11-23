# Northgate receptionist assistant

LangGraph service for the patient app's chat: safety gate first (red flags in 7 languages skip the model), then the
model with tools that act as the signed-in patient, bookings and cancellations confirmed by the patient's button, and a
grounding check on prices and times. See the main README for the design.

```bash
uv run pytest -q                                  # fast tests, scripted model
uv run python evals/smoke_live_model.py           # real model through Ollama (slow on CPU)
uv run uvicorn agent.api:app --port 8100          # the API (needs SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY)
```
