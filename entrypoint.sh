#!/bin/sh
set -e

PORT="${PORT:-10000}"
mkdir -p /app/data

if [ -n "$SITE_PASSWORD" ]; then
  SITE_USER="${SITE_USER:-mailaccess}"
  openssl passwd -apr1 "$SITE_PASSWORD" > /tmp/.htpasswd_hash
  printf '%s:%s\n' "$SITE_USER" "$(cat /tmp/.htpasswd_hash)" > /etc/nginx/.htpasswd
  rm -f /tmp/.htpasswd_hash
  AUTH='auth_basic "MailAccess"; auth_basic_user_file /etc/nginx/.htpasswd;'
else
  AUTH=''
fi

# Inject the backend API key on proxied API/WS calls so the browser frontend
# (already protected by nginx basic auth) never needs to send it. The key is
# only ever set as a Railway environment variable, never committed to the repo.
if [ -n "$MAILACCESS_API_KEY" ]; then
  APIKEY_HDR="proxy_set_header X-API-Key ${MAILACCESS_API_KEY};"
else
  APIKEY_HDR=''
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

    location /api/ {
      ${AUTH}
      ${APIKEY_HDR}
      proxy_pass http://127.0.0.1:8000;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_read_timeout 300s;
    }

    location /ws/ {
      ${AUTH}
      ${APIKEY_HDR}
      proxy_pass http://127.0.0.1:8000;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host \$host;
      proxy_read_timeout 3600s;
    }

    location / {
      ${AUTH}
      try_files \$uri \$uri/ /index.html;
    }
  }
}
EOF

uvicorn backend.main:app --host 127.0.0.1 --port 8000 &
nginx -g 'daemon off;'
