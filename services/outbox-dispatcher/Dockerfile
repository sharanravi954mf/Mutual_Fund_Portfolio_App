FROM python:3.12.11-slim-bookworm@sha256:519591d6871b7bc437060736b9f7456b8731f1499a57e22e6c285135ae657bf7 AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt requirements-dev.txt ./
RUN pip install --requirement requirements.txt \
    && groupadd --gid 10002 dispatcher \
    && useradd --uid 10002 --gid dispatcher --no-create-home --shell /usr/sbin/nologin dispatcher

FROM base AS runtime

COPY dispatcher.py routes.json ./

USER 10002:10002

CMD ["python", "dispatcher.py"]

FROM base AS test

RUN pip install --requirement requirements-dev.txt

COPY dispatcher.py routes.json ./
COPY tests ./tests
COPY pyproject.toml ./pyproject.toml

USER 10002:10002

CMD ["python", "-m", "pytest"]
