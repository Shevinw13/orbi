"""Explore overlay routes.

Requirements: 2.1, 2.3
"""

from __future__ import annotations

from fastapi import APIRouter, Query

from backend.models.explore import ExploreOverlaysResponse
from backend.services.explore import get_overlays

router = APIRouter(prefix="/explore", tags=["explore"])


@router.get("/overlays", response_model=ExploreOverlaysResponse)
async def overlays(
    latitude: float = Query(..., description="User latitude"),
    longitude: float = Query(..., description="User longitude"),
):
    """Return up to 4 explore overlay categories for the given location."""
    results = await get_overlays(latitude, longitude)
    return ExploreOverlaysResponse(overlays=results)
