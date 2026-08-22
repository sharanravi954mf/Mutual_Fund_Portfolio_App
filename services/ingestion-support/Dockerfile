FROM python:3.12.11-slim-bookworm@sha256:519591d6871b7bc437060736b9f7456b8731f1499a57e22e6c285135ae657bf7 AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt requirements-dev.txt ./
RUN pip install --requirement requirements.txt \
    && groupadd --gid 10001 ingestion \
    && useradd --uid 10001 --gid ingestion --no-create-home --shell /usr/sbin/nologin ingestion

FROM base AS runtime

COPY app ./app

USER 10001:10001
EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--no-access-log", "--workers", "1"]

FROM base AS test

RUN pip install --requirement requirements-dev.txt
COPY app ./app
COPY tests ./tests
COPY pyproject.toml ./pyproject.toml

USER 10001:10001
CMD ["python", "-m", "pytest", "-m", "not integration"]
