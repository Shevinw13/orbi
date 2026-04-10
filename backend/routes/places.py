"""Place recommendation routes — hotels and restaurants.

Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 13.1, 13.2, 13.3, 14.1, 14.4
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query

from backend.models.auth import ErrorResponse
from backend.models.places import PlaceQuery, PlacesResponse
from backend.services.places import get_hotels, get_restaurants

router = APIRouter(prefix="/places", tags=["places"])


@router.get(
    "/hotels",
    response_model=PlacesResponse,
    responses={500: {"model": ErrorResponse}},
)
async def list_hotels(
    latitude: float = Query(..., description="Search centre latitude"),
    longitude: float = Query(..., description="Search centre longitude"),
    price_range: str | None = Query(None, description="Price filter ($–$$$$)"),
    vibe: str | None = Query(None, description="Hotel vibe (luxury, boutique, budget)"),
    excluded_ids: list[str] = Query(default=[], description="Place IDs to exclude (refresh)"),
    radius: int = Query(5000, ge=500, le=50000, description="Search radius in metres"),
):
    """Return top 3 hotel recommendations (Req 7.1)."""
    query = PlaceQuery(
        latitude=latitude,
        longitude=longitude,
        price_range=price_range,
        vibe=vibe,
        excluded_ids=excluded_ids,
        radius=radius,
    )
    try:
        return await get_hotels(query)
    except RuntimeError as exc:
        raise HTTPException(
            status_code=500,
            detail={"error": "places_api_error", "message": str(exc)},
        )


@router.get(
    "/restaurants",
    response_model=PlacesResponse,
    responses={500: {"model": ErrorResponse}},
)
async def list_restaurants(
    latitude: float = Query(..., description="Search centre latitude"),
    longitude: float = Query(..., description="Search centre longitude"),
    price_range: str | None = Query(None, description="Price filter ($–$$$$)"),
    cuisine: str | None = Query(None, description="Cuisine type filter"),
    excluded_ids: list[str] = Query(default=[], description="Place IDs to exclude (refresh)"),
    radius: int = Query(5000, ge=500, le=50000, description="Search radius in metres"),
):
    """Return top 3 restaurant recommendations (Req 7.2)."""
    query = PlaceQuery(
        latitude=latitude,
        longitude=longitude,
        price_range=price_range,
        cuisine=cuisine,
        excluded_ids=excluded_ids,
        radius=radius,
    )
    try:
        return await get_restaurants(query)
    except RuntimeError as exc:
        raise HTTPException(
            status_code=500,
            detail={"error": "places_api_error", "message": str(exc)},
        )
