# syntax=docker/dockerfile:1
# All-in-one MailAccess image: FastAPI backend + React frontend served by nginx.
# Source pinned to an upstream commit of github.com/KatrielMoses/MailAccess (MIT).

ARG MAILACCESS_SHA=346cfe984f40efb494aeffaac3614fd759862135

# ---- Stage 1: build the React frontend ----
FROM node:20-alpine AS frontend-build
ARG MAILACCESS_SHA
RUN apk add --no-cache git
RUN git clone https://github.com/KatrielMoses/MailAccess.git /src \
    && cd /src && git checkout ${MAILACCESS_SHA}
WORKDIR /src/frontend
RUN npm ci && npm run build

# ---- Stage 2: runtime (uvicorn backend + nginx serving frontend) ----
FROM python:3.12-slim
ARG MAILACCESS_SHA
RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx openssl git \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN git clone https://github.com/KatrielMoses/MailAccess.git /src \
    && cd /src && git checkout ${MAILACCESS_SHA}
RUN cp /src/pyproject.toml /src/README.md /app/ \
    && pip install --no-cache-dir /app \
    && cp -r /src/backend /src/cli /app/ \
    && mkdir -p /app/data
COPY --from=frontend-build /src/frontend/dist /app/static
COPY entrypoint.sh /entrypoint.sh
EXPOSE 10000
CMD ["sh", "/entrypoint.sh"]
