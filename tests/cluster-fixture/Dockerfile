FROM python:3.12-slim
WORKDIR /opt/fixture
COPY api_server.py vllm/entrypoints/openai/api_server.py
ENV PYTHONDONTWRITEBYTECODE=1
USER 1000:1000
# Chart command and secret interpolation stay unchanged; this is an explicit
# deterministic protocol fixture, not vLLM or a model.
