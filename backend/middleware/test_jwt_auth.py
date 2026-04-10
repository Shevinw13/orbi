"""Unit tests for JWTAuthMiddleware.

Requirements: 11.5, 11.6, 12.1
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

from unittest.mock import patch

import pytest
from fastapi import FastAPI, Request
from fastapi.testclient import TestClient

from backend.middleware.jwt_auth import JWTAuthMiddleware


# ---------------------------------------------------------------------------
# Minimal app fixture with the middleware applied
# ---------------------------------------------------------------------------

def _create_app() -> FastAPI:
    app = FastAPI()
    app.add_middleware(JWTAuthMiddleware)

    @app.get("/health")
    async def health():
        return {"status": "ok"}

    @app.get("/auth/login")
    async def auth_login():
        return {"ok": True}

    @app.get("/share/abc123")
    async def share_link():
        return {"shared": True}

    @app.get("/docs")
    async def docs():
        return {"docs": True}

    @app.get("/openapi.json")
    async def openapi():
        return {"openapi": True}

    @app.get("/protected")
    async def protected(request: Request):
        return {"user_id": request.state.user_id}

    return app


@pytest.fixture()
def client():
    return TestClient(_create_app())


# ---------------------------------------------------------------------------
# Public paths — no auth required
# ---------------------------------------------------------------------------

class TestPublicPaths:
    def test_health_no_auth(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200

    def test_auth_routes_no_auth(self, client):
        resp = client.get("/auth/login")
        assert resp.status_code == 200

    def test_share_routes_no_auth(self, client):
        resp = client.get("/share/abc123")
        assert resp.status_code == 200

    def test_docs_no_auth(self, client):
        resp = client.get("/docs")
        assert resp.status_code == 200

    def test_openapi_json_no_auth(self, client):
        resp = client.get("/openapi.json")
        assert resp.status_code == 200


# ---------------------------------------------------------------------------
# Protected paths — auth required
# ---------------------------------------------------------------------------

class TestProtectedPaths:
    def test_missing_auth_header_returns_401(self, client):
        resp = client.get("/protected")
        assert resp.status_code == 401
        body = resp.json()
        assert body["error"] == "unauthorized"
        assert "Missing" in body["message"]

    def test_malformed_auth_header_returns_401(self, client):
        resp = client.get("/protected", headers={"Authorization": "Token abc"})
        assert resp.status_code == 401
        body = resp.json()
        assert "Invalid" in body["message"]

    def test_bearer_only_no_token_returns_401(self, client):
        resp = client.get("/protected", headers={"Authorization": "Bearer"})
        assert resp.status_code == 401

    def test_invalid_token_returns_401(self, client):
        resp = client.get("/protected", headers={"Authorization": "Bearer bad.token.here"})
        assert resp.status_code == 401
        body = resp.json()
        assert body["error"] == "unauthorized"

    @patch("backend.middleware.jwt_auth.decode_access_token")
    def test_valid_token_sets_user_id(self, mock_decode, client):
        mock_decode.return_value = {"sub": "user-42", "type": "access"}
        resp = client.get("/protected", headers={"Authorization": "Bearer valid.jwt.token"})
        assert resp.status_code == 200
        assert resp.json()["user_id"] == "user-42"

    @patch("backend.middleware.jwt_auth.decode_access_token")
    def test_expired_token_returns_401(self, mock_decode, client):
        import jwt as pyjwt
        mock_decode.side_effect = pyjwt.ExpiredSignatureError("Token expired")
        resp = client.get("/protected", headers={"Authorization": "Bearer expired.jwt.token"})
        assert resp.status_code == 401
