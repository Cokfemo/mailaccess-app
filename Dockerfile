# All-in-one MailAccess image: FastAPI backend + pre-built React frontend served by nginx.
# Backend source pinned to an upstream commit of github.com/KatrielMoses/MailAccess (MIT).
# Frontend is pre-built (see static/) with branding: "Mail Access" by femo.

ARG MAILACCESS_SHA=346cfe984f40efb494aeffaac3614fd759862135

FROM python:3.12-slim
ARG MAILACCESS_SHA
RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx openssl git \
    libgobject-2.0-0 libcairo2 libpango-1.0-0 libpangocairo-1.0-0 \
    libgdk-pixbuf-xlib-2.0-0 libffi-dev shared-mime-info \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN git clone https://github.com/KatrielMoses/MailAccess.git /src \
 && cd /src && git checkout ${MAILACCESS_SHA}
RUN cp /src/pyproject.toml /src/README.md /app/ \
 && cp -r /src/backend /src/cli /src/data /app/ \
 && pip install --no-cache-dir /app
COPY static /app/static
COPY auth_service.py /app/auth_service.py
COPY entrypoint.sh /entrypoint.sh
EXPOSE 10000
CMD ["sh", "/entrypoint.sh"]
