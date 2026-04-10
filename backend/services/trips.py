"""Trip CRUD service — Supabase persistence with user-ownership enforcement.

Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 12.5
"""

from __future__ import annotations

from typing import Any

from backend.config import settings

_supabase_client = None


def _get_supabase():
    """Lazily initialise and return the Supabase client."""
    global _supabase_client
    if _supabase_client is None:
        from supabase import create_client

        _supabase_client = create_client(settings.supabase_url, settings.supabase_key)
    return _supabase_client


async def create_trip(user_id: str, data: dict[str, Any]) -> dict[str, Any]:
    """Insert a new trip row owned by *user_id*. Returns the created row."""
    sb = _get_supabase()
    row = {**data, "user_id": user_id}
    result = sb.table("trips").insert(row).execute()
    return result.data[0]


async def list_trips(user_id: str) -> list[dict[str, Any]]:
    """Return all trips owned by *user_id*, newest first."""
    sb = _get_supabase()
    result = (
        sb.table("trips")
        .select("id, destination, num_days, vibe, created_at")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .execute()
    )
    return result.data


async def get_trip(trip_id: str, user_id: str) -> dict[str, Any] | None:
    """Fetch a single trip by ID. Returns *None* if not found.

    Raises ``PermissionError`` if the trip belongs to a different user.
    """
    sb = _get_supabase()
    result = sb.table("trips").select("*").eq("id", trip_id).execute()

    if not result.data:
        return None

    trip = result.data[0]
    if trip["user_id"] != user_id:
        raise PermissionError("You do not have access to this trip")

    return trip


async def delete_trip(trip_id: str, user_id: str) -> bool:
    """Delete a trip by ID. Returns *True* on success.

    Raises ``PermissionError`` if the trip belongs to a different user.
    Returns *False* if the trip does not exist.
    """
    sb = _get_supabase()

    # Verify ownership first
    existing = sb.table("trips").select("id, user_id").eq("id", trip_id).execute()
    if not existing.data:
        return False

    if existing.data[0]["user_id"] != user_id:
        raise PermissionError("You do not have access to this trip")

    sb.table("trips").delete().eq("id", trip_id).execute()
    return True
