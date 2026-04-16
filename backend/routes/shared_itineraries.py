"""Shared Itineraries routes — browse, detail, copy, publish.

Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, Request

from backend.models.shared_itinerary import (
    SharedItineraryCopyResponse,
    SharedItineraryDetail,
    SharedItineraryListItem,
    SharedItineraryListResponse,
    SharedItineraryPublishRequest,
)
from backend.services.shared_itineraries import (
    copy_shared_itinerary,
    get_shared_itinerary,
    list_shared_itineraries,
    publish_shared_itinerary,
)

router = APIRouter(prefix="/shared-itineraries", tags=["shared-itineraries"])


@router.get("", response_model=SharedItineraryListResponse)
async def list_itineraries(
    section: str | None = Query(None, description="Section: featured, trending, destination, budget"),
    destination: str | None = Query(None, description="Destination filter (partial match)"),
    budget_level: int | None = Query(None, ge=1, le=5, description="Budget level 1-5"),
    min_days: int | None = Query(None, ge=1, description="Minimum trip days"),
    max_days: int | None = Query(None, ge=1, description="Maximum trip days"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Page size"),
):
    """List/search shared itineraries. No auth required."""
    try:
        result = await list_shared_itineraries(
            section=section,
            destination=destination,
            budget_level=budget_level,
            min_days=min_days,
            max_days=max_days,
            page=page,
            page_size=page_size,
        )
        return SharedItineraryListResponse(
            items=[SharedItineraryListItem(**item) for item in result["items"]],
            total=result["total"],
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to list shared itineraries: {exc}")


@router.get("/{itinerary_id}", response_model=SharedItineraryDetail)
async def get_itinerary_detail(itinerary_id: str):
    """Get full detail of a shared itinerary. No auth required."""
    try:
        result = await get_shared_itinerary(itinerary_id)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to load shared itinerary: {exc}")

    if result is None:
        raise HTTPException(status_code=404, detail="Shared itinerary not found")

    return SharedItineraryDetail(**result)


@router.post("/{itinerary_id}/copy", response_model=SharedItineraryCopyResponse)
async def copy_itinerary(itinerary_id: str, request: Request):
    """Copy a shared itinerary to the user's trips. Auth required."""
    user_id: str = request.state.user_id
    try:
        result = await copy_shared_itinerary(itinerary_id, user_id)
        return SharedItineraryCopyResponse(**result)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to copy itinerary: {exc}")


@router.post("", status_code=201)
async def publish_itinerary(body: SharedItineraryPublishRequest, request: Request):
    """Publish a trip as a shared itinerary. Auth required."""
    user_id: str = request.state.user_id
    try:
        result = await publish_shared_itinerary(
            user_id=user_id,
            source_trip_id=body.source_trip_id,
            title=body.title,
            description=body.description,
            destination=body.destination,
            budget_level=body.budget_level,
            cover_photo_url=body.cover_photo_url,
            tags=body.tags,
        )
        return result
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    except PermissionError:
        raise HTTPException(status_code=403, detail="You do not have access to this trip")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to publish itinerary: {exc}")
