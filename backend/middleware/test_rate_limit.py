"""Unit tests for RateLimitMiddleware.

Requirements: 11.1, 11.2, 11.3, 12.4
"""

from __future__ import annotations

import os

os.environ.setdefault("SUPABASE_URL", "https://test.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "test-key")
os.environ.setdefault("OPENAI_API_KEY", "sk-test")
os.environ.setdefault("JWT_SECRET", "test-jwt-secret")

from unittest.mock import MagicMock, patch

import pytest
from fastapi import FastAPI, Request
from starlette.middleware.base import BaseHTTPMiddleware
from fastapi.testclient import TestClient

from backend.middleware.rate_limit import RateLimitMiddleware, RATE_LIMIT, _memory_counters


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


@pytest.fixture(autouse=True)
def _clear_counters():
    """Clear in-memory rate limit counters between tests."""
    _memory_counters.clear()
    yield
    _memory_counters.clear()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestRateLimitSkipsUnauthenticated:
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


class TestRateLimitWithRedis:
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
    def test_over_limit_returns_429(self, mock_get_redis):
        mock_redis = _make_mock_redis(current_count=RATE_LIMIT + 1)
        mock_get_redis.return_value = mock_redis
        client = TestClient(_create_app())

        resp = client.get("/protected", headers={"X-User-Id": "user-1"})
        assert resp.status_code == 429
        body = resp.json()
        assert body["error"] == "rate_limit_exceeded"


class TestRateLimitInMemoryFallback:
    @patch("backend.middleware.rate_limit.get_redis_client", return_value=None)
    def test_allows_request_when_no_redis(self, mock_get_redis):
        client = TestClient(_create_app())
        resp = client.get("/protected", headers={"X-User-Id": "user-mem"})
        assert resp.status_code == 200

    @patch("backend.middleware.rate_limit.get_redis_client", return_value=None)
    def test_memory_counter_enforces_limit(self, mock_get_redis):
        """In-memory counter should return 429 after exceeding limit."""
        import time as _time

        client = TestClient(_create_app())
        # Pre-fill the counter to just at the limit (window still active)
        _memory_counters["user-flood"] = (RATE_LIMIT, _time.time())

        # Next request should push over the limit and return 429
        resp = client.get("/protected", headers={"X-User-Id": "user-flood"})
        assert resp.status_code == 429


class TestRateLimitRedisError:
    @patch("backend.middleware.rate_limit.get_redis_client")
    def test_allows_request_on_redis_error(self, mock_get_redis):
        """Redis errors should fail-open (allow request through)."""
        mock_redis = MagicMock()
        mock_redis.incr.side_effect = Exception("Redis connection lost")
        mock_get_redis.return_value = mock_redis
        client = TestClient(_create_app())

        resp = client.get("/protected", headers={"X-User-Id": "user-err"})
        assert resp.status_code == 200
