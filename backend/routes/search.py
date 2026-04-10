"""Destination search route — autocomplete suggestions.

Requirements: 2.2
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query

from backend.models.auth import ErrorResponse
from backend.services.search import search_destinations

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
    """Return city autocomplete suggestions for the given query (Req 2.2)."""
    try:
        results = await search_destinations(q)
        return {"results": results}
    except RuntimeError as exc:
        raise HTTPException(
            status_code=500,
            detail={"error": "search_api_error", "message": str(exc)},
        )
