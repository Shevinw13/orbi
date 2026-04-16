"""Itinerary generation routes.

Requirements: 4.1, 4.2, 4.6, 5.5, 14.4
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException

from backend.models.auth import ErrorResponse
from backend.models.itinerary import (
    ItineraryRequest,
    ItineraryResponse,
    ReplaceActivityRequest,
    ReplaceSuggestionsResponse,
)
from backend.services.itinerary import generate_itinerary, replace_activity

router = APIRouter(prefix="/trips", tags=["itinerary"])


@router.post(
    "/generate",
    response_model=ItineraryResponse,
    responses={500: {"model": ErrorResponse}},
)
async def post_generate_itinerary(body: ItineraryRequest):
    """Generate an AI-powered itinerary from trip preferences (Req 4.1)."""
    try:
        itinerary = await generate_itinerary(body)
        return itinerary
    except RuntimeError as exc:
        raise HTTPException(
            status_code=500,
            detail={"error": "itinerary_generation_failed", "message": str(exc)},
        )


@router.post(
    "/replace-item",
    response_model=ReplaceSuggestionsResponse,
    responses={500: {"model": ErrorResponse}},
)
async def post_replace_activity(body: ReplaceActivityRequest):
    """Replace an itinerary item with AI-generated alternatives (Req 5.5, 14.1)."""
    try:
        suggestions = await replace_activity(body)
        return suggestions
    except RuntimeError as exc:
        raise HTTPException(
            status_code=500,
            detail={"error": "replacement_failed", "message": str(exc)},
        )
