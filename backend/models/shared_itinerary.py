"""Pydantic models for Shared Itineraries (Explore feature).

Requirements: 8.1, 8.2, 8.3, 8.4, 8.6, 8.7
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field, field_validator


class SharedItineraryListItem(BaseModel):
    """Card-level data for the Explore feed."""

    id: str
    title: str
    destination: str
    num_days: int
    budget_level: int
    cover_photo_url: str | None = None
    creator_username: str | None = None
    save_count: int = 0
    tags: list[str] = Field(default_factory=list)


class SharedItineraryDetail(BaseModel):
    """Full detail including itinerary JSONB."""

    id: str
    title: str
    description: str
    destination: str
    destination_lat_lng: str | None = None
    num_days: int
    budget_level: int
    cover_photo_url: str | None = None
    creator_username: str | None = None
    save_count: int = 0
    tags: list[str] = Field(default_factory=list)
    itinerary: dict[str, Any] | None = None
    created_at: str


class SharedItineraryPublishRequest(BaseModel):
    """Publish metadata sent by the client."""

    source_trip_id: str = Field(..., min_length=1, description="ID of the trip to publish")
    cover_photo_url: str = Field("", description="Cover photo URL (optional)")
    title: str = Field(..., min_length=1, max_length=100, description="Title (1-100 chars)")
    description: str = Field(..., min_length=1, max_length=500, description="Description (1-500 chars)")
    destination: str = Field(..., min_length=1, description="Destination city")
    budget_level: int = Field(..., ge=1, le=5, description="Budget level 1-5")
    tags: list[str] = Field(default_factory=list, description="Optional tags")

    @field_validator("title")
    @classmethod
    def title_not_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Title must not be blank")
        return v.strip()

    @field_validator("description")
    @classmethod
    def description_not_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Description must not be blank")
        return v.strip()

    @field_validator("destination")
    @classmethod
    def destination_not_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Destination must not be blank")
        return v.strip()


class SharedItineraryListResponse(BaseModel):
    """Paginated list wrapper."""

    items: list[SharedItineraryListItem]
    total: int


class SharedItineraryCopyResponse(BaseModel):
    """Response after copying a shared itinerary."""

    trip_id: str
