"""JWT Authentication Middleware.

Validates Bearer tokens on all routes except public paths.
Requirements: 11.5, 11.6, 12.1
"""

from __future__ import annotations

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

from backend.services.auth import decode_access_token

# Paths that do not require authentication
PUBLIC_PATH_PREFIXES = ("/auth", "/share", "/health", "/docs", "/openapi.json", "/search")

# Specific public paths (not prefix-based)
PUBLIC_PATHS = {"/search/popular-cities"}


class JWTAuthMiddleware(BaseHTTPMiddleware):
    """Starlette middleware that enforces JWT Bearer auth.

    • Skips authentication for public paths (auth, share, health, docs, openapi).
    • Extracts the Bearer token from the Authorization header.
    • Decodes the token and sets ``request.state.user_id``.
    • Returns 401 JSON for missing, malformed, or invalid tokens.
    """

    async def dispatch(self, request: Request, call_next):
        path = request.url.path

        # Allow public endpoints through without auth
        if any(path.startswith(prefix) for prefix in PUBLIC_PATH_PREFIXES):
            return await call_next(request)
        if path in PUBLIC_PATHS:
            return await call_next(request)

        # Extract Authorization header
        auth_header = request.headers.get("Authorization")
        if not auth_header:
            return JSONResponse(
                status_code=401,
                content={"error": "unauthorized", "message": "Missing Authorization header"},
            )

        # Expect "Bearer <token>"
        parts = auth_header.split(" ", 1)
        if len(parts) != 2 or parts[0].lower() != "bearer":
            return JSONResponse(
                status_code=401,
                content={"error": "unauthorized", "message": "Invalid Authorization header format"},
            )

        token = parts[1]

        try:
            payload = decode_access_token(token)
        except Exception:
            return JSONResponse(
                status_code=401,
                content={"error": "unauthorized", "message": "Invalid or expired token"},
            )

        # Attach user identity to request state for downstream handlers
        request.state.user_id = payload.get("sub")
        return await call_next(request)
