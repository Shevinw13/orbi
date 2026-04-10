"""Unit tests for RateLimitMiddleware.

Requirements: 12.4
"""

from __future__ import annotations

import os

# Provide dummy env vars so backend.config.Settings can initialise
os.environ.setdefault("SUPABASE_URL", "https://test.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "test-key")
os.environ.setdefault("UPSTASH_REDIS_URL", "redis://localhost:6379")
os.environ.setdefault("OPENAI_API_KEY", "sk-test")
os.environ.setdefault("GOOGLE_PLACES_API_KEY", "test-places-key")
os.environ.setdefault("JWT_SECRET", "test-jwt-secret")

from unittest.mock import MagicMock, patch

import pytest
from fastapi import FastAPI, Request
from starlette.middleware.base import BaseHTTPMiddleware
from fastapi.testclient import TestClient

from backend.middleware.rate_limit import RateLimitMiddleware, RATE_LIMIT


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

class FakeAuthMiddleware(BaseHTTPMiddleware):
    """Sets user_id on request.state if X-User-Id header is present."""

    async def dispatch(self, request: Request, call_next):
        uid = request.headers.get("X-User-Id")
        if uid:
            request.state.user_id = uid
        return await call_next(request)


def _create_app() -> FastAPI:
    """Build a minimal FastAPI app with RateLimitMiddleware."""
    app = FastAPI()

    # Order: RateLimit added first (inner), FakeAuth added second (outer)
    # so FakeAuth runs first on the request and sets user_id.
    app.add_middleware(RateLimitMiddleware)
    app.add_middleware(FakeAuthMiddleware)

    @app.get("/protected")
    async def protected(request: Request):
        return {"ok": True}

    @app.get("/public")
    async def public():
        return {"ok": True}

    return app


def _make_mock_redis(current_count: int = 1) -> MagicMock:
    """Return a mock Redis client with configurable incr return value."""
    mock = MagicMock()
    mock.incr.return_value = current_count
    return mock


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestRateLimitSkipsUnauthenticated:
    """Unauthenticated requests (no user_id) should pass through without rate limiting."""

    @patch("backend.middleware.rate_limit.get_redis_client")
    def test_no_user_id_passes_through(self, mock_get_redis):
        mock_redis = _make_mock_redis()
        mock_get_redis.return_value = mock_redis
        client = TestClient(_create_app())

        resp = client.get("/public")
        assert resp.status_code == 200
        mock_redis.incr.assert_not_called()

    @patch("backend.middleware.rate_limit.get_redis_client")
    def test_no_user_id_header_on_protected_passes_through(self, mock_get_redis):
        mock_redis = _make_mock_redis()
        mock_get_redis.return_value = mock_redis
        client = TestClient(_create_app())

        resp = client.get("/protected")
        assert resp.status_code == 200
        mock_redis.incr.assert_not_called()


class TestRateLimitCounterLogic:
    """Authenticated requests should increment the Redis counter."""

    @patch("backend.middleware.rate_limit.get_redis_client")
    def test_first_request_sets_ttl(self, mock_get_redis):
        mock_redis = _make_mock_redis(current_count=1)
        mock_get_redis.return_value = mock_redis
        client = TestClient(_create_app())

        resp = client.get("/protected", headers={"X-User-Id": "user-1"})
        assert resp.status_code == 200
        mock_redis.incr.assert_called_once_with("ratelimit:user-1")
        mock_redis.expire.assert_called_once_with("ratelimit:user-1", 60)

    @patch("backend.middleware.rate_limit.get_redis_client")
    def test_subsequent_request_does_not_reset_ttl(self, mock_get_redis):
        mock_redis = _make_mock_redis(current_count=50)
        mock_get_redis.return_value = mock_redis
        client = TestClient(_create_app())

        resp = client.get("/protected", headers={"X-User-Id": "user-1"})
        assert resp.status_code == 200
        mock_redis.incr.assert_called_once()
        mock_redis.expire.assert_not_called()

    @patch("backend.middleware.rate_limit.get_redis_client")
    def test_request_at_limit_still_allowed(self, mock_get_redis):
        mock_redis = _make_mock_redis(current_count=RATE_LIMIT)
        mock_get_redis.return_value = mock_redis
        client = TestClient(_create_app())

        resp = client.get("/protected", headers={"X-User-Id": "user-1"})
        assert resp.status_code == 200


class TestRateLimitExceeded:
    """Requests exceeding the limit should receive 429."""

    @patch("backend.middleware.rate_limit.get_redis_client")
    def test_over_limit_returns_429(self, mock_get_redis):
        mock_redis = _make_mock_redis(current_count=RATE_LIMIT + 1)
        mock_get_redis.return_value = mock_redis
        client = TestClient(_create_app())

        resp = client.get("/protected", headers={"X-User-Id": "user-1"})
        assert resp.status_code == 429
        body = resp.json()
        assert body["error"] == "rate_limit_exceeded"
        assert "Too many requests" in body["message"]

    @patch("backend.middleware.rate_limit.get_redis_client")
    def test_well_over_limit_returns_429(self, mock_get_redis):
        mock_redis = _make_mock_redis(current_count=200)
        mock_get_redis.return_value = mock_redis
        client = TestClient(_create_app())

        resp = client.get("/protected", headers={"X-User-Id": "user-1"})
        assert resp.status_code == 429
