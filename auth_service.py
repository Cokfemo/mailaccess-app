"""Cookie-auth sidecar for MailAccess.

Replaces nginx basic auth with a branded login page. Verifies the
username/password against the SITE_USER / SITE_PASSWORD environment
variables and issues a signed, HttpOnly cookie valid 30 days, so mobile
browsers (notably iPhone Safari) stop re-asking for credentials.

nginx gates /, /api and /ws on the /check endpoint via auth_request.
/healthz, /login, the logo and /auth/* itself stay open.

The signing key comes from the COOKIE_SECRET environment variable (set in
Railway, never committed). If it is absent, a key is derived from
SITE_PASSWORD so existing deployments keep working.
"""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import os
import time
from urllib.parse import parse_qs

COOKIE_NAME = "ma_auth"
MAX_AGE = 30 * 24 * 3600  # 30 days

SITE_USER = os.environ.get("SITE_USER", "mailaccess")
SITE_PASSWORD = os.environ.get("SITE_PASSWORD", "")

_secret = os.environ.get("COOKIE_SECRET", "")
if not _secret:
    _secret = hashlib.sha256(("mailaccess-cookie:" + SITE_PASSWORD).encode()).hexdigest()
_KEY = hashlib.sha256(("mailaccess-auth-key:" + _secret).encode()).digest()


def _sign(payload: str) -> str:
    return hmac.new(_KEY, payload.encode(), hashlib.sha256).hexdigest()


def _make_token() -> str:
    exp = int(time.time()) + MAX_AGE
    return f"{exp}.{_sign(f'v1.{exp}.{SITE_USER}')}"


def _valid_token(value: str) -> bool:
    try:
        exp_s, sig = value.split(".", 1)
        exp = int(exp_s)
    except ValueError:
        return False
    if exp < int(time.time()):
        return False
    expected = _sign(f"v1.{exp_s}.{SITE_USER}")
    return hmac.compare_digest(sig, expected)


def _cookie_value(cookie_header: str | None) -> str | None:
    if not cookie_header:
        return None
    for part in cookie_header.split(";"):
        part = part.strip()
        if part.startswith(COOKIE_NAME + "="):
            return part[len(COOKIE_NAME) + 1:]
    return None


def _set_cookie_header(token: str) -> bytes:
    return (
        f"{COOKIE_NAME}={token}; Path=/; Max-Age={MAX_AGE}; "
        "HttpOnly; Secure; SameSite=Lax"
    ).encode()


def _clear_cookie_header() -> bytes:
    return (
        f"{COOKIE_NAME}=; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Lax"
    ).encode()


async def _read_body(receive) -> bytes:
    chunks: list[bytes] = []
    while True:
        message = await receive()
        chunks.append(message.get("body", b""))
        if not message.get("more_body"):
            break
        if sum(len(c) for c in chunks) > 64 * 1024:
            break
    return b"".join(chunks)


async def _respond(send, status: int, body: bytes, extra_headers: list[tuple[bytes, bytes]] | None = None) -> None:
    headers = [(b"content-length", str(len(body)).encode())]
    if body:
        headers.append((b"content-type", b"text/plain; charset=utf-8"))
    if extra_headers:
        headers.extend(extra_headers)
    await send({"type": "http.response.start", "status": status, "headers": headers})
    await send({"type": "http.response.body", "body": body})


async def app(scope, receive, send):
    if scope["type"] != "http":
        return
    path = scope.get("path", "")
    method = scope.get("method", "GET")

    if path == "/check":
        headers = {k.decode("latin1"): v.decode("latin1") for k, v in scope.get("headers", [])}
        ok = bool(SITE_PASSWORD) and _valid_token(_cookie_value(headers.get("cookie")) or "")
        await _respond(send, 200 if ok else 401, b"")
        return

    if path == "/login" and method == "POST":
        body = await _read_body(receive)
        form = parse_qs(body.decode("utf-8", "replace"))
        username = form.get("username", [""])[0]
        password = form.get("password", [""])[0]
        ok = (
            bool(SITE_PASSWORD)
            and hmac.compare_digest(username, SITE_USER)
            and hmac.compare_digest(password, SITE_PASSWORD)
        )
        if ok:
            await _respond(
                send,
                303,
                b"",
                [(b"set-cookie", _set_cookie_header(_make_token())), (b"location", b"/")],
            )
        else:
            await asyncio.sleep(1.0)  # slow down credential guessing
            await _respond(send, 303, b"", [(b"location", b"/login?error=1")])
        return

    if path == "/logout":
        await _respond(
            send,
            303,
            b"",
            [(b"set-cookie", _clear_cookie_header()), (b"location", b"/login")],
        )
        return

    await _respond(send, 404, b"not found")
