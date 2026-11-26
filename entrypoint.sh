#!/bin/sh
set -e

PORT="${PORT:-10000}"
mkdir -p /app/data

# Inject the backend API key on proxied API/WS calls so the browser frontend
# (already protected by the cookie login) never needs to send it. The key is
# only ever set as a Railway environment variable, never committed to the repo.
if [ -n "$MAILACCESS_API_KEY" ]; then
  APIKEY_HDR="proxy_set_header X-API-Key ${MAILACCESS_API_KEY};"
else
  APIKEY_HDR=''
fi

# Cookie login: when SITE_PASSWORD is set, run the auth sidecar and gate
# /, /api and /ws behind its signed 30-day cookie. /healthz, /login, the logo
# and /auth/* stay open. Without SITE_PASSWORD the site stays open as before.
if [ -n "$SITE_PASSWORD" ]; then
  (cd /app && uvicorn auth_service:app --host 127.0.0.1 --port 8001 --log-level warning) &
  AUTH_BLOCK='auth_request /auth/check;'
  LOGIN_REDIRECT='error_page 401 403 = @login_redirect;'
  AUTH_LOCATIONS='
    location = /login {
      try_files /login.html =404;
    }

    location = /ma_logo.png {
      try_files $uri =404;
    }

    location = /auth/check {
      internal;
      proxy_pass http://127.0.0.1:8001/check;
      proxy_pass_request_body off;
      proxy_set_header Content-Length "";
      proxy_set_header Cookie $http_cookie;
    }

    location = /auth/login {
      proxy_pass http://127.0.0.1:8001/login;
      proxy_set_header Host $host;
      proxy_set_header X-Forwarded-Proto $scheme;
    }

    location @login_redirect {
      return 302 /login;
    }

    location = /auth/logout {
      proxy_pass http://127.0.0.1:8001/logout;
      proxy_set_header Host $host;
      proxy_set_header X-Forwarded-Proto $scheme;
    }
'
else
  AUTH_BLOCK=''
  LOGIN_REDIRECT=''
  AUTH_LOCATIONS=''
fi

cat > /etc/nginx/nginx.conf <<EOF
user www-data;
worker_processes 1;
pid /run/nginx.pid;
events { worker_connections 512; }
http {
  include /etc/nginx/mime.types;
  default_type application/octet-stream;
  sendfile on;
  client_max_body_size 20m;
  server {
    listen ${PORT};
    root /app/static;
    index index.html;

    location = /healthz { return 200 'ok'; }
${AUTH_LOCATIONS}
    location /api/ {
      ${AUTH_BLOCK}
      ${APIKEY_HDR}
      proxy_pass http://127.0.0.1:8000;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_read_timeout 300s;
    }

    location /ws/ {
      ${AUTH_BLOCK}
      ${APIKEY_HDR}
      proxy_pass http://127.0.0.1:8000;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host \$host;
      proxy_read_timeout 3600s;
    }

    location / {
      ${AUTH_BLOCK}
      ${LOGIN_REDIRECT}
      try_files \$uri \$uri/ /index.html;
    }
  }
}
EOF

uvicorn backend.main:app --host 127.0.0.1 --port 8000 &
nginx -g 'daemon off;'
