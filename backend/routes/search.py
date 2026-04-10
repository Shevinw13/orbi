"""Destination search routes — autocomplete suggestions and popular cities.

Requirements: 3.1, 10.1, 10.4
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query

from backend.models.auth import ErrorResponse
from backend.services.search import search_destinations, get_popular_cities

router = APIRouter(prefix="/search", tags=["search"])


@router.get(
    "/destinations",
    responses={500: {"model": ErrorResponse}},
)
async def destinations(
    q: str = Query(
        ...,
        min_length=2,
        description="Search query (min 2 characters)",
    ),
):
    """Return city autocomplete suggestions for the given query."""
    try:
        results = await search_destinations(q)
        return {"results": results}
    except RuntimeError as exc:
        raise HTTPException(
            status_code=500,
            detail={"error": "search_api_error", "message": str(exc)},
        )


@router.get("/popular-cities")
async def popular_cities():
    """Return curated list of popular travel destinations (public, no auth)."""
    results = await get_popular_cities()
    return {"results": results}
