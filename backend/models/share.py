"""Pydantic models for the Share_Service endpoints.

Requirements: 10.1, 10.2, 10.3, 10.4, 8.1, 8.2, 8.4
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class ShareResponse(BaseModel):
    """Response from POST /trips/{id}/share — the generated share link."""

    share_id: str = Field(..., description="UUID-based share identifier")
    share_url: str = Field(..., description="Full deep-link URL for the shared trip")


class ShareCreateRequest(BaseModel):
    """Request body for POST /trips/{id}/share with optional planner fields."""

    planned_by: str | None = Field(None, max_length=100)
    notes: str | None = Field(None, max_length=500)


class SharedTripResponse(BaseModel):
    """Read-only trip data returned by GET /share/{share_id}.

    Deliberately excludes user_id and email to strip sensitive data (Req 10.4).
    """

    destination: str
    destination_lat_lng: str | None = None
    num_days: int
    vibe: str | None = None
    itinerary: dict[str, Any] | None = None
    selected_hotel_id: str | None = None
    selected_restaurants: list[dict[str, Any]] | None = None
    cost_breakdown: dict[str, Any] | None = None
    planned_by: str | None = None
    notes: str | None = None
