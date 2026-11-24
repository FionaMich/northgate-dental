# syntax=docker/dockerfile:1
# Nora's voice service (ADR 0015, 0016): joins Stream calls, listens, asks the assistant, speaks. Non-root.
FROM python:3.12-slim AS build
COPY --from=ghcr.io/astral-sh/uv:0.9.7 /uv /usr/local/bin/uv
WORKDIR /app
COPY pyproject.toml uv.lock README.md ./
RUN uv sync --frozen --no-dev --no-install-project
COPY src ./src
RUN uv sync --frozen --no-dev

FROM python:3.12-slim
RUN useradd --create-home --uid 10002 app
WORKDIR /app
COPY --from=build --chown=app:app /app /app
ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1 HF_HOME=/home/app/models
USER app
# The English speech model is baked in so the first caller is not kept waiting; other languages download once.
RUN python -c "from faster_whisper import WhisperModel; WhisperModel('base.en', device='cpu', compute_type='int8')"
CMD ["python", "-m", "voice.agent"]
