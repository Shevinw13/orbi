"""Rate Limiting Middleware.

Enforces 100 requests per minute per authenticated user using Redis counters.
Requirements: 12.4
"""

from __future__ import annotations

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

from backend.services.cache import get_redis_client

RATE_LIMIT = 100  # max requests per window
WINDOW_SECONDS = 60  # sliding window duration


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Starlette middleware that rate-limits authenticated users.

    • Skips unauthenticated requests (no ``user_id`` on ``request.state``).
    • Uses a Redis key ``ratelimit:{user_id}`` with a 60-second TTL.
    • Increments the counter on each request.
    • Returns 429 JSON when the counter exceeds 100.
    """

    async def dispatch(self, request: Request, call_next):
        # Only rate-limit authenticated requests
        user_id = getattr(request.state, "user_id", None)
        if user_id is None:
            return await call_next(request)

        redis_client = get_redis_client()
        key = f"ratelimit:{user_id}"

        # Increment counter; INCR creates the key with value 1 if it doesn't exist
        current_count = redis_client.incr(key)

        # Set TTL only on the first request in the window (count == 1)
        if current_count == 1:
            redis_client.expire(key, WINDOW_SECONDS)

        if current_count > RATE_LIMIT:
            return JSONResponse(
                status_code=429,
                content={
                    "error": "rate_limit_exceeded",
                    "message": "Too many requests. Please try again later.",
                },
            )

        return await call_next(request)
