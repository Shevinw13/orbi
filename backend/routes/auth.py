"""Authentication routes — Apple Sign-In, Google OAuth, token refresh.

Requirements: 11.1, 11.2, 11.3, 11.5
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException

from backend.models.auth import (
    AppleSignInRequest,
    AuthResponse,
    GoogleSignInRequest,
    RefreshRequest,
)
from backend.services.auth import (
    apple_sign_in,
    google_sign_in,
    refresh_access_token,
)

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/apple", response_model=AuthResponse)
async def auth_apple(body: AppleSignInRequest):
    """Authenticate via Apple Sign-In (Req 11.1)."""
    try:
        result = await apple_sign_in(body.identity_token, name=body.name)
        return AuthResponse(**result)
    except ValueError as exc:
        raise HTTPException(status_code=401, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Authentication failed: {exc}")


@router.post("/google", response_model=AuthResponse)
async def auth_google(body: GoogleSignInRequest):
    """Authenticate via Google OAuth (Req 11.2)."""
    try:
        result = await google_sign_in(body.id_token)
        return AuthResponse(**result)
    except ValueError as exc:
        raise HTTPException(status_code=401, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Authentication failed: {exc}")


@router.post("/refresh", response_model=AuthResponse)
async def auth_refresh(body: RefreshRequest):
    """Exchange a refresh token for a new access token (Req 11.5)."""
    try:
        result = await refresh_access_token(body.refresh_token)
        return AuthResponse(**result)
    except ValueError as exc:
        raise HTTPException(status_code=401, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Token refresh failed: {exc}")
