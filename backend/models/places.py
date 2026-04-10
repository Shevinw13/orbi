"""Pydantic models for Place_Service requests and responses.

Requirements: 7.1, 7.2, 7.3, 7.4, 7.5
"""

from __future__ import annotations

from pydantic import BaseModel, Field


class PlaceQuery(BaseModel):
    """Query parameters for hotel/restaurant search."""

    latitude: float = Field(..., description="Search centre latitude")
    longitude: float = Field(..., description="Search centre longitude")
    price_range: str | None = Field(
        None,
        description="Price filter: $, $$, $$$, or $$$$",
    )
    vibe: str | None = Field(
        None,
        description="Hotel vibe filter (luxury, boutique, budget). Hotels only.",
    )
    cuisine: str | None = Field(
        None,
        description="Cuisine type filter. Restaurants only.",
    )
    excluded_ids: list[str] = Field(
        default_factory=list,
        description="Place IDs already shown — excluded for refresh (Req 7.4).",
    )
    radius: int = Field(
        5000,
        ge=500,
        le=50000,
        description="Search radius in metres (default 5 km).",
    )


class PlaceResult(BaseModel):
    """A single place recommendation (Req 7.3)."""

    place_id: str
    name: str
    rating: float = 0.0
    price_level: str = ""
    image_url: str | None = None
    latitude: float = 0.0
    longitude: float = 0.0


class PlacesResponse(BaseModel):
    """Response wrapper for place recommendations."""

    results: list[PlaceResult]
    filters_broadened: bool = Field(
        False,
        description="True when original filters returned no results and were relaxed (Req 7.5).",
    )
