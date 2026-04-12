"""Share_Service — generate and resolve UUID-based share links.

Requirements: 10.1, 10.2, 10.3, 10.4, 8.3, 8.4, 8.5
"""

from __future__ import annotations

import uuid
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


def _normalize_empty(value: str | None) -> str | None:
    """Return None if value is None, empty, or whitespace-only; otherwise return the original."""
    if value is None:
        return None
    stripped = value.strip()
    return stripped if stripped else None


async def create_share_link(
    trip_id: str,
    user_id: str,
    planned_by: str | None = None,
    notes: str | None = None,
) -> dict[str, str]:
    """Generate a UUID share link for a trip owned by *user_id*.

    Returns ``{"share_id": "<uuid>"}`` on success.
    Raises ``PermissionError`` if the trip is not owned by the user.
    Raises ``LookupError`` if the trip does not exist.
    """
    sb = _get_supabase()

    # Normalize empty/whitespace strings to null (Req 8.4)
    planned_by = _normalize_empty(planned_by)
    notes = _normalize_empty(notes)

    # Verify the trip exists and belongs to the requesting user
    result = sb.table("trips").select("id, user_id").eq("id", trip_id).execute()
    if not result.data:
        raise LookupError("Trip not found")
    if result.data[0]["user_id"] != user_id:
        raise PermissionError("You do not have access to this trip")

    # Check if a share link already exists for this trip
    existing = sb.table("shared_trips").select("share_id").eq("trip_id", trip_id).execute()
    if existing.data:
        # Update planner fields on existing share
        share_id = existing.data[0]["share_id"]
        sb.table("shared_trips").update(
            {"planned_by": planned_by, "notes": notes}
        ).eq("trip_id", trip_id).execute()
        return {"share_id": share_id}

    # Create a new share record
    share_id = str(uuid.uuid4())
    sb.table("shared_trips").insert({
        "trip_id": trip_id,
        "share_id": share_id,
        "planned_by": planned_by,
        "notes": notes,
    }).execute()
    return {"share_id": share_id}


async def get_shared_trip(share_id: str) -> dict[str, Any] | None:
    """Resolve a share_id to read-only trip data.

    Returns the trip dict (without sensitive fields) or *None* if the
    share link is invalid.
    """
    sb = _get_supabase()

    # Look up the share record
    share_result = (
        sb.table("shared_trips")
        .select("trip_id, planned_by, notes")
        .eq("share_id", share_id)
        .execute()
    )
    if not share_result.data:
        return None

    share_row = share_result.data[0]
    trip_id = share_row["trip_id"]

    # Fetch the trip
    trip_result = sb.table("trips").select("*").eq("id", trip_id).execute()
    if not trip_result.data:
        return None

    trip = trip_result.data[0]

    # Strip sensitive user data (Req 10.4) and include planner fields (Req 8.5)
    return {
        "destination": trip["destination"],
        "destination_lat_lng": trip.get("destination_lat_lng"),
        "num_days": trip["num_days"],
        "vibe": trip.get("vibe"),
        "itinerary": trip.get("itinerary"),
        "selected_hotel_id": trip.get("selected_hotel_id"),
        "selected_restaurants": trip.get("selected_restaurants"),
        "cost_breakdown": trip.get("cost_breakdown"),
        "planned_by": share_row.get("planned_by"),
        "notes": share_row.get("notes"),
    }
