"""Place recommendation routes — hotels and restaurants.

Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 10.3, 10.4
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query

from backend.models.auth import ErrorResponse
from backend.models.places import PlaceQuery, PlaceResult, PlacesResponse
from backend.services.places import get_hotels, get_restaurants
from backend.services.google_places import text_search_places

router = APIRouter(prefix="/places", tags=["places"])


@router.get(
    "/hotels",
    response_model=PlacesResponse,
    responses={500: {"model": ErrorResponse}},
)
async def list_hotels(
    latitude: float = Query(..., description="Search centre latitude"),
    longitude: float = Query(..., description="Search centre longitude"),
    budget_tier: str | None = Query(None, alias="budget_tier", description="Budget tier ($-$$$$$)"),
    price_range: str | None = Query(None, description="Price filter ($–$$$$) — legacy, use budget_tier"),
    vibe: str | None = Query(None, description="Hotel vibe (luxury, boutique, budget)"),
    excluded_ids: list[str] = Query(default=[], description="Place IDs to exclude (refresh)"),
    radius: int = Query(5000, ge=500, le=50000, description="Search radius in metres"),
):
    """Return top hotel recommendations (Req 7.1)."""
    # Prefer budget_tier over legacy price_range
    effective_price = budget_tier or price_range
    query = PlaceQuery(
        latitude=latitude,
        longitude=longitude,
        price_range=effective_price,
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
    budget_tier: str | None = Query(None, alias="budget_tier", description="Budget tier ($-$$$$$)"),
    price_range: str | None = Query(None, description="Price filter ($–$$$$) — legacy, use budget_tier"),
    cuisine: str | None = Query(None, description="Cuisine type filter"),
    excluded_ids: list[str] = Query(default=[], description="Place IDs to exclude (refresh)"),
    radius: int = Query(5000, ge=500, le=50000, description="Search radius in metres"),
):
    """Return top restaurant recommendations (Req 7.2)."""
    effective_price = budget_tier or price_range
    query = PlaceQuery(
        latitude=latitude,
        longitude=longitude,
        price_range=effective_price,
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


@router.get(
    "/search",
    response_model=PlacesResponse,
    responses={500: {"model": ErrorResponse}},
)
async def search_places(
    query: str = Query(..., min_length=1, description="Free-text search query"),
    latitude: float = Query(..., description="Bias center latitude"),
    longitude: float = Query(..., description="Bias center longitude"),
    place_type: str = Query("restaurant", description="'restaurant' or 'lodging'"),
):
    """Free-text search for restaurants or hotels using Google Places Text Search."""
    try:
        results = await text_search_places(
            query=query,
            latitude=latitude,
            longitude=longitude,
            place_type=place_type,
        )
        place_results = [
            PlaceResult(
                place_id=r.place_id,
                name=r.name,
                rating=r.rating,
                price_level=r.price_level_display,
                image_url=r.photo_references[0] if r.photo_references else None,
                latitude=r.latitude,
                longitude=r.longitude,
                rating_source="google",
                review_count=r.user_ratings_total,
            )
            for r in results
        ]
        return PlacesResponse(results=place_results, filters_broadened=False)
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail={"error": "search_failed", "message": str(exc)},
        )
