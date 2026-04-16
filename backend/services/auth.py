"""Auth_Service — Apple Sign-In, Google OAuth, JWT issuance, refresh tokens.

Requirements: 11.1, 11.2, 11.3, 11.4, 11.7
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

import bcrypt
import httpx
import jwt

from backend.config import settings

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24  # 24 hours
REFRESH_TOKEN_EXPIRE_DAYS = 90
BCRYPT_COST_FACTOR = 12  # ≥10 per Req 11.4

APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
GOOGLE_TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"

# ---------------------------------------------------------------------------
# Supabase client helper
# ---------------------------------------------------------------------------

_supabase_client = None


def _get_supabase():
    """Lazily initialise and return the Supabase client."""
    global _supabase_client
    if _supabase_client is None:
        from supabase import create_client

        _supabase_client = create_client(settings.supabase_url, settings.supabase_key)
    return _supabase_client


# ---------------------------------------------------------------------------
# Apple token validation (Req 11.1)
# ---------------------------------------------------------------------------


async def _fetch_apple_jwks() -> dict[str, Any]:
    """Fetch Apple's current JSON Web Key Set."""
    async with httpx.AsyncClient() as client:
        resp = await client.get(APPLE_JWKS_URL, timeout=10)
        resp.raise_for_status()
        return resp.json()


async def validate_apple_token(identity_token: str) -> dict[str, Any]:
    """Validate an Apple identity JWT and return its claims.

    Steps:
    1. Decode the JWT header to get the `kid`.
    2. Fetch Apple's JWKS and find the matching public key.
    3. Verify signature, expiry, issuer, and audience.

    Returns decoded claims dict on success; raises ValueError on failure.
    """
    try:
        unverified_header = jwt.get_unverified_header(identity_token)
    except jwt.DecodeError as exc:
        raise ValueError(f"Invalid token header: {exc}") from exc

    kid = unverified_header.get("kid")
    if not kid:
        raise ValueError("Token header missing 'kid'")

    jwks = await _fetch_apple_jwks()
    matching_key = None
    for key_data in jwks.get("keys", []):
        if key_data.get("kid") == kid:
            matching_key = key_data
            break

    if matching_key is None:
        raise ValueError("No matching Apple public key for kid")

    public_key = jwt.algorithms.RSAAlgorithm.from_jwk(matching_key)

    claims = jwt.decode(
        identity_token,
        public_key,
        algorithms=["RS256"],
        issuer="https://appleid.apple.com",
        options={"verify_aud": False},  # audience varies per app bundle
    )
    return claims


# ---------------------------------------------------------------------------
# Google token validation (Req 11.2)
# ---------------------------------------------------------------------------


async def validate_google_token(id_token: str) -> dict[str, Any]:
    """Validate a Google ID token via Google's tokeninfo endpoint.

    Returns the token payload on success; raises ValueError on failure.
    """
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            GOOGLE_TOKENINFO_URL,
            params={"id_token": id_token},
            timeout=10,
        )

    if resp.status_code != 200:
        raise ValueError(f"Google token validation failed: {resp.text}")

    payload = resp.json()

    # Google returns "email_verified" as a string "true"/"false"
    if payload.get("email_verified") != "true":
        raise ValueError("Google email not verified")

    return payload


# ---------------------------------------------------------------------------
# JWT issuance (Req 11.3)
# ---------------------------------------------------------------------------


def create_access_token(user_id: str) -> tuple[str, int]:
    """Create a short-lived JWT access token.

    Returns (token_string, expires_in_seconds).
    """
    expires_in = ACCESS_TOKEN_EXPIRE_MINUTES * 60
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "iat": now,
        "exp": now + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
        "type": "access",
    }
    token = jwt.encode(payload, settings.jwt_secret, algorithm="HS256")
    return token, expires_in


def create_refresh_token(user_id: str) -> tuple[str, datetime]:
    """Create a long-lived opaque refresh token.

    Returns (raw_token, expiry_datetime).
    """
    raw_token = uuid.uuid4().hex + uuid.uuid4().hex  # 64-char hex string
    expires_at = datetime.now(timezone.utc) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    return raw_token, expires_at


def decode_access_token(token: str) -> dict[str, Any]:
    """Decode and verify a JWT access token. Raises jwt.PyJWTError on failure."""
    return jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])


# ---------------------------------------------------------------------------
# Refresh token hashing (Req 11.4)
# ---------------------------------------------------------------------------


def hash_refresh_token(raw_token: str) -> str:
    """Hash a refresh token with bcrypt (cost factor ≥ 10)."""
    salt = bcrypt.gensalt(rounds=BCRYPT_COST_FACTOR)
    return bcrypt.hashpw(raw_token.encode(), salt).decode()


def verify_refresh_token(raw_token: str, token_hash: str) -> bool:
    """Verify a raw refresh token against its bcrypt hash."""
    return bcrypt.checkpw(raw_token.encode(), token_hash.encode())


# ---------------------------------------------------------------------------
# User record management (Req 11.7)
# ---------------------------------------------------------------------------


async def _find_or_create_user(
    *,
    auth_provider: str,
    sub: str,
    email: str | None = None,
    name: str | None = None,
) -> dict[str, Any]:
    """Look up a user by provider sub; create on first auth.

    Returns the user row as a dict.
    """
    sb = _get_supabase()
    sub_column = "apple_sub" if auth_provider == "apple" else "google_sub"

    # Check for existing user
    result = sb.table("users").select("*").eq(sub_column, sub).execute()

    if result.data:
        return result.data[0]

    # First authentication — create user record (Req 11.7)
    new_user = {
        "email": email,
        "name": name,
        "auth_provider": auth_provider,
        sub_column: sub,
    }
    insert_result = sb.table("users").insert(new_user).execute()
    return insert_result.data[0]


async def _store_refresh_token(user_id: str, raw_token: str, expires_at: datetime) -> None:
    """Hash and persist a refresh token in the database."""
    sb = _get_supabase()
    sb.table("refresh_tokens").insert(
        {
            "user_id": user_id,
            "token_hash": hash_refresh_token(raw_token),
            "expires_at": expires_at.isoformat(),
        }
    ).execute()


# ---------------------------------------------------------------------------
# Public sign-in orchestrators
# ---------------------------------------------------------------------------


async def apple_sign_in(identity_token: str, name: str | None = None) -> dict[str, Any]:
    """Full Apple Sign-In flow.

    1. Validate identity token against Apple JWKS.
    2. Find or create user.
    3. Issue access + refresh tokens.
    4. Store hashed refresh token.
    """
    claims = await validate_apple_token(identity_token)
    apple_sub = claims["sub"]
    email = claims.get("email")

    user = await _find_or_create_user(
        auth_provider="apple",
        sub=apple_sub,
        email=email,
        name=name,
    )

    access_token, expires_in = create_access_token(user["id"])
    raw_refresh, refresh_expires = create_refresh_token(user["id"])
    await _store_refresh_token(user["id"], raw_refresh, refresh_expires)

    return {
        "access_token": access_token,
        "refresh_token": raw_refresh,
        "token_type": "bearer",
        "expires_in": expires_in,
        "user_id": user["id"],
        "name": user.get("name"),
        "username": user.get("username"),
    }


async def google_sign_in(id_token: str) -> dict[str, Any]:
    """Full Google OAuth flow.

    1. Validate ID token via Google tokeninfo.
    2. Find or create user.
    3. Issue access + refresh tokens.
    4. Store hashed refresh token.
    """
    payload = await validate_google_token(id_token)
    google_sub = payload["sub"]
    email = payload.get("email")
    name = payload.get("name")

    user = await _find_or_create_user(
        auth_provider="google",
        sub=google_sub,
        email=email,
        name=name,
    )

    access_token, expires_in = create_access_token(user["id"])
    raw_refresh, refresh_expires = create_refresh_token(user["id"])
    await _store_refresh_token(user["id"], raw_refresh, refresh_expires)

    return {
        "access_token": access_token,
        "refresh_token": raw_refresh,
        "token_type": "bearer",
        "expires_in": expires_in,
        "user_id": user["id"],
        "name": user.get("name"),
        "username": user.get("username"),
    }


# ---------------------------------------------------------------------------
# Email/Password auth
# ---------------------------------------------------------------------------


def hash_password(password: str) -> str:
    """Hash a password with bcrypt."""
    salt = bcrypt.gensalt(rounds=BCRYPT_COST_FACTOR)
    return bcrypt.hashpw(password.encode(), salt).decode()


def verify_password(password: str, password_hash: str) -> bool:
    """Verify a password against its bcrypt hash."""
    return bcrypt.checkpw(password.encode(), password_hash.encode())


async def email_register(email: str, password: str, name: str | None = None, username: str | None = None) -> dict[str, Any]:
    """Register a new user with email/username and password."""
    sb = _get_supabase()

    if not email and not username:
        raise ValueError("Either email or username is required")

    # Check for existing user
    if email:
        result = sb.table("users").select("*").eq("email", email).execute()
        if result.data:
            raise ValueError("An account with this email already exists")

    new_user = {
        "email": email,
        "name": name or (email.split("@")[0] if email else "User"),
        "auth_provider": "email",
        "password_hash": hash_password(password),
    }
    if username:
        new_user["username"] = username
    insert_result = sb.table("users").insert(new_user).execute()
    user = insert_result.data[0]

    access_token, expires_in = create_access_token(user["id"])
    raw_refresh, refresh_expires = create_refresh_token(user["id"])
    await _store_refresh_token(user["id"], raw_refresh, refresh_expires)

    return {
        "access_token": access_token,
        "refresh_token": raw_refresh,
        "token_type": "bearer",
        "expires_in": expires_in,
        "user_id": user["id"],
        "name": user.get("name"),
        "username": user.get("username"),
    }


async def email_login(email: str | None, password: str, username: str | None = None) -> dict[str, Any]:
    """Authenticate with email or username and password."""
    sb = _get_supabase()

    if not email and not username:
        raise ValueError("Either email or username is required")

    if email:
        result = sb.table("users").select("*").eq("email", email).execute()
    else:
        result = sb.table("users").select("*").eq("username", username).execute()

    if not result.data:
        raise ValueError("Invalid credentials")

    user = result.data[0]
    stored_hash = user.get("password_hash")
    if not stored_hash or not verify_password(password, stored_hash):
        raise ValueError("Invalid credentials")

    access_token, expires_in = create_access_token(user["id"])
    raw_refresh, refresh_expires = create_refresh_token(user["id"])
    await _store_refresh_token(user["id"], raw_refresh, refresh_expires)

    return {
        "access_token": access_token,
        "refresh_token": raw_refresh,
        "token_type": "bearer",
        "expires_in": expires_in,
        "user_id": user["id"],
        "name": user.get("name"),
        "username": user.get("username"),
    }


async def refresh_access_token(raw_refresh_token: str) -> dict[str, Any]:
    """Exchange a valid refresh token for a new access token.

    Validates the raw token against stored hashes and checks expiry.
    Raises ValueError if the token is invalid or expired.
    """
    sb = _get_supabase()

    # Fetch all non-expired refresh tokens (we must check bcrypt against each)
    now_iso = datetime.now(timezone.utc).isoformat()
    result = (
        sb.table("refresh_tokens")
        .select("id, user_id, token_hash, expires_at")
        .gte("expires_at", now_iso)
        .execute()
    )

    matched_row = None
    for row in result.data:
        if verify_refresh_token(raw_refresh_token, row["token_hash"]):
            matched_row = row
            break

    if matched_row is None:
        raise ValueError("Invalid or expired refresh token")

    access_token, expires_in = create_access_token(matched_row["user_id"])

    return {
        "access_token": access_token,
        "refresh_token": raw_refresh_token,  # same refresh token stays valid
        "token_type": "bearer",
        "expires_in": expires_in,
        "user_id": matched_row["user_id"],
    }
