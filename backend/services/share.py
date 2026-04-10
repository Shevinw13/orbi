"""Share_Service — generate and resolve UUID-based share links.

Requirements: 10.1, 10.2, 10.3, 10.4
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


async def create_share_link(trip_id: str, user_id: str) -> dict[str, str]:
    """Generate a UUID share link for a trip owned by *user_id*.

    Returns ``{"share_id": "<uuid>"}`` on success.
    Raises ``PermissionError`` if the trip is not owned by the user.
    Raises ``LookupError`` if the trip does not exist.
    """
    sb = _get_supabase()

    # Verify the trip exists and belongs to the requesting user
    result = sb.table("trips").select("id, user_id").eq("id", trip_id).execute()
    if not result.data:
        raise LookupError("Trip not found")
    if result.data[0]["user_id"] != user_id:
        raise PermissionError("You do not have access to this trip")

    # Check if a share link already exists for this trip
    existing = sb.table("shared_trips").select("share_id").eq("trip_id", trip_id).execute()
    if existing.data:
        return {"share_id": existing.data[0]["share_id"]}

    # Create a new share record
    share_id = str(uuid.uuid4())
    sb.table("shared_trips").insert({"trip_id": trip_id, "share_id": share_id}).execute()
    return {"share_id": share_id}


async def get_shared_trip(share_id: str) -> dict[str, Any] | None:
    """Resolve a share_id to read-only trip data.

    Returns the trip dict (without sensitive fields) or *None* if the
    share link is invalid.
    """
    sb = _get_supabase()

    # Look up the share record
    share_result = sb.table("shared_trips").select("trip_id").eq("share_id", share_id).execute()
    if not share_result.data:
        return None

    trip_id = share_result.data[0]["trip_id"]

    # Fetch the trip
    trip_result = sb.table("trips").select("*").eq("id", trip_id).execute()
    if not trip_result.data:
        return None

    trip = trip_result.data[0]

    # Strip sensitive user data (Req 10.4)
    return {
        "destination": trip["destination"],
        "destination_lat_lng": trip.get("destination_lat_lng"),
        "num_days": trip["num_days"],
        "vibe": trip.get("vibe"),
        "itinerary": trip.get("itinerary"),
        "selected_hotel_id": trip.get("selected_hotel_id"),
        "selected_restaurants": trip.get("selected_restaurants"),
        "cost_breakdown": trip.get("cost_breakdown"),
    }
