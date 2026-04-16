"""Shared Itineraries service — list, detail, copy, publish.

Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 6.1, 6.2, 6.3, 6.4, 7.4, 7.5, 11.1
"""

from __future__ import annotations

import logging
from typing import Any

from backend.config import settings

logger = logging.getLogger(__name__)

_supabase_client = None


def _get_supabase():
    """Lazily initialise and return the Supabase client."""
    global _supabase_client
    if _supabase_client is None:
        from supabase import create_client
        _supabase_client = create_client(settings.supabase_url, settings.supabase_key)
    return _supabase_client


def format_budget_indicator(level: int) -> str:
    """Return a string of N dollar signs for budget level N (1-5)."""
    return "$" * level


async def list_shared_itineraries(
    section: str | None = None,
    destination: str | None = None,
    budget_level: int | None = None,
    min_days: int | None = None,
    max_days: int | None = None,
    page: int = 1,
    page_size: int = 20,
) -> dict[str, Any]:
    """Query shared_itineraries with filters, join users for creator_username."""
    sb = _get_supabase()

    query = sb.table("shared_itineraries").select(
        "id, title, destination, num_days, budget_level, cover_photo_url, "
        "save_count, tags, is_featured, users!shared_itineraries_user_id_fkey(username)",
        count="exact",
    )

    # Section-based filtering
    if section == "featured":
        query = query.eq("is_featured", True)
    elif section == "trending":
        query = query.order("save_count", desc=True)

    # Destination partial match (case-insensitive)
    if destination:
        query = query.ilike("destination", f"%{destination}%")

    # Budget level filter
    if budget_level is not None:
        query = query.eq("budget_level", budget_level)

    # Duration range filter
    if min_days is not None:
        query = query.gte("num_days", min_days)
    if max_days is not None:
        query = query.lte("num_days", max_days)

    # Default ordering (trending already ordered above)
    if section != "trending":
        query = query.order("created_at", desc=True)

    # Pagination
    offset = (page - 1) * page_size
    query = query.range(offset, offset + page_size - 1)

    result = query.execute()

    items = []
    for row in result.data:
        user_data = row.pop("users", None) or {}
        items.append({
            **row,
            "creator_username": user_data.get("username") if isinstance(user_data, dict) else None,
        })

    return {"items": items, "total": result.count or len(items)}


async def get_shared_itinerary(itinerary_id: str) -> dict[str, Any] | None:
    """Fetch a single shared itinerary with username join."""
    sb = _get_supabase()

    result = (
        sb.table("shared_itineraries")
        .select("*, users!shared_itineraries_user_id_fkey(username)")
        .eq("id", itinerary_id)
        .execute()
    )

    if not result.data:
        return None

    row = result.data[0]
    user_data = row.pop("users", None) or {}
    row["creator_username"] = user_data.get("username") if isinstance(user_data, dict) else None
    return row


async def copy_shared_itinerary(shared_id: str, user_id: str) -> dict[str, Any]:
    """Deep copy a shared itinerary into the user's trips + increment save_count."""
    sb = _get_supabase()

    # Fetch the shared itinerary
    shared_result = (
        sb.table("shared_itineraries")
        .select("*, users!shared_itineraries_user_id_fkey(username)")
        .eq("id", shared_id)
        .execute()
    )

    if not shared_result.data:
        raise ValueError("Shared itinerary not found")

    shared = shared_result.data[0]
    user_data = shared.pop("users", None) or {}
    creator_username = user_data.get("username") if isinstance(user_data, dict) else None

    # Create a new trip row with the copied data
    trip_row = {
        "user_id": user_id,
        "destination": shared["destination"],
        "destination_lat_lng": shared.get("destination_lat_lng"),
        "num_days": shared["num_days"],
        "itinerary": shared["itinerary"],
        "copied_from_shared_id": shared_id,
        "original_creator_username": creator_username,
    }

    trip_result = sb.table("trips").insert(trip_row).execute()
    if not trip_result.data:
        raise RuntimeError("Failed to create trip copy")

    new_trip = trip_result.data[0]

    # Atomically increment save_count
    sb.rpc("increment_save_count", {"row_id": shared_id}).execute()

    return {"trip_id": new_trip["id"]}


async def publish_shared_itinerary(
    user_id: str,
    source_trip_id: str,
    title: str,
    description: str,
    destination: str,
    budget_level: int,
    cover_photo_url: str = "",
    tags: list[str] | None = None,
) -> dict[str, Any]:
    """Publish a trip to the shared itineraries explore feed.

    Completely rewritten — minimal, defensive, no quality gates.
    """
    sb = _get_supabase()

    # Step 1: Fetch the source trip
    logger.info("PUBLISH: fetching trip %s for user %s", source_trip_id, user_id)
    try:
        trip_result = sb.table("trips").select("*").eq("id", source_trip_id).execute()
    except Exception as e:
        logger.error("PUBLISH: failed to fetch trip: %s", e)
        raise RuntimeError(f"Failed to fetch trip: {e}")

    if not trip_result.data:
        logger.error("PUBLISH: trip %s not found", source_trip_id)
        raise ValueError("Trip not found")

    trip = trip_result.data[0]
    logger.info("PUBLISH: trip found, user_id=%s, destination=%s", trip.get("user_id"), trip.get("destination"))

    if str(trip["user_id"]) != str(user_id):
        logger.error("PUBLISH: ownership mismatch: trip.user_id=%s != request.user_id=%s", trip["user_id"], user_id)
        raise PermissionError("You do not have access to this trip")

    # Step 2: Build the insert row with safe defaults
    row = {
        "user_id": str(user_id),
        "source_trip_id": str(source_trip_id),
        "title": str(title)[:100],
        "description": str(description)[:500],
        "destination": str(destination),
        "budget_level": int(budget_level),
        "num_days": int(trip.get("num_days") or 1),
        "tags": list(tags) if tags else [],
    }

    # Optional fields — only include if they have values
    if cover_photo_url and cover_photo_url.strip():
        row["cover_photo_url"] = str(cover_photo_url).strip()

    if trip.get("destination_lat_lng"):
        row["destination_lat_lng"] = str(trip["destination_lat_lng"])

    if trip.get("itinerary"):
        row["itinerary"] = trip["itinerary"]

    logger.info("PUBLISH: inserting row with keys: %s", list(row.keys()))

    # Step 3: Insert
    try:
        result = sb.table("shared_itineraries").insert(row).execute()
    except Exception as e:
        logger.error("PUBLISH: Supabase insert FAILED: %s", e, exc_info=True)
        raise RuntimeError(f"Database insert failed: {e}")

    if not result.data:
        logger.error("PUBLISH: insert returned empty data")
        raise RuntimeError("Insert returned no data")

    logger.info("PUBLISH: success, id=%s", result.data[0].get("id"))
    return result.data[0]
