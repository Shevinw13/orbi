"""Rate Limiting Middleware.

Enforces 100 requests per minute per authenticated user.
Uses Redis when available, falls back to in-memory counters.
Requirements: 11.1, 11.2, 11.3, 12.4
"""

from __future__ import annotations

import logging
import time

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

from backend.services.cache import get_redis_client

logger = logging.getLogger(__name__)

RATE_LIMIT = 100  # max requests per window
WINDOW_SECONDS = 60  # sliding window duration

# In-memory fallback: user_id -> (count, window_start_timestamp)
_memory_counters: dict[str, tuple[int, float]] = {}


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Starlette middleware that rate-limits authenticated users.

    Uses Redis INCR/EXPIRE when available, in-memory counters otherwise.
    On any error, allows the request through (fail-open).
    """

    async def dispatch(self, request: Request, call_next):
        user_id = getattr(request.state, "user_id", None)
        if user_id is None:
            return await call_next(request)

        try:
            redis_client = get_redis_client()
            if redis_client is None:
                # No Redis — use in-memory counter
                return await self._check_memory_limit(user_id, request, call_next)

            key = f"ratelimit:{user_id}"
            current_count = redis_client.incr(key)
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
        except Exception:
            logger.warning("Rate limit check failed for user=%s, allowing request through", user_id)

        return await call_next(request)

    async def _check_memory_limit(self, user_id: str, request: Request, call_next):
        """In-memory rate limiting when Redis is unavailable."""
        now = time.time()
        entry = _memory_counters.get(user_id)

        if entry is None or (now - entry[1]) > WINDOW_SECONDS:
            # New window
            _memory_counters[user_id] = (1, now)
        else:
            count, window_start = entry
            count += 1
            _memory_counters[user_id] = (count, window_start)

            if count > RATE_LIMIT:
                return JSONResponse(
                    status_code=429,
                    content={
                        "error": "rate_limit_exceeded",
                        "message": "Too many requests. Please try again later.",
                    },
                )

        return await call_next(request)
