# syntax=docker/dockerfile:1
# Receptionist assistant (section 10): multi-stage with uv, non-root, amd64 and arm64.
FROM python:3.12-slim AS build
COPY --from=ghcr.io/astral-sh/uv:0.9.7 /uv /usr/local/bin/uv
WORKDIR /app
COPY pyproject.toml uv.lock README.md ./
RUN uv sync --frozen --no-dev --no-install-project
COPY src ./src
RUN uv sync --frozen --no-dev

FROM python:3.12-slim
RUN useradd --create-home --uid 10001 app
WORKDIR /app
COPY --from=build --chown=app:app /app /app
ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1
USER app
EXPOSE 8100
# One process: conversation state is in memory for now (a restart starts conversations afresh).
CMD ["uvicorn", "agent.api:app", "--host", "0.0.0.0", "--port", "8100", "--no-server-header"]
