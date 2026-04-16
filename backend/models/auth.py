"""Pydantic models for authentication endpoints.

Covers Apple Sign-In, Google OAuth, token refresh, and auth responses.
Requirements: 11.1, 11.2, 11.3
"""

from __future__ import annotations

from pydantic import BaseModel, Field


class AppleSignInRequest(BaseModel):
    """POST /auth/apple request body."""

    identity_token: str = Field(..., description="Apple identity JWT from ASAuthorizationAppleIDCredential")
    name: str | None = Field(None, description="User's full name (only provided on first sign-in)")


class GoogleSignInRequest(BaseModel):
    """POST /auth/google request body."""

    id_token: str = Field(..., description="Google ID token from GIDSignIn")


class RefreshRequest(BaseModel):
    """POST /auth/refresh request body."""

    refresh_token: str = Field(..., description="Opaque refresh token issued at sign-in")


class AuthResponse(BaseModel):
    """Successful authentication response."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int = Field(description="Access token lifetime in seconds")
    user_id: str
    name: str | None = None
    username: str | None = None


class EmailRegisterRequest(BaseModel):
    """POST /auth/register request body."""

    email: str | None = Field(None, description="User email address (optional if username provided)")
    username: str | None = Field(None, description="Username (optional if email provided)")
    password: str = Field(..., min_length=6, description="Password (min 6 chars)")
    name: str | None = Field(None, description="User's display name")


class EmailLoginRequest(BaseModel):
    """POST /auth/login request body."""

    email: str | None = Field(None, description="User email address")
    username: str | None = Field(None, description="Username")
    password: str = Field(..., description="User password")


class ErrorResponse(BaseModel):
    """Structured error response (Req 14.4)."""

    error: str
    message: str
