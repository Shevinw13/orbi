"""Trip CRUD routes — save, list, load, delete trips.

Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 12.5
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request

from backend.models.trip import TripCreate, TripListItem, TripResponse
from backend.services.trips import create_trip, delete_trip, get_trip, list_trips

router = APIRouter(prefix="/trips", tags=["trips"])


@router.post("", response_model=TripResponse, status_code=201)
async def save_trip(body: TripCreate, request: Request):
    """Save a new trip for the authenticated user (Req 9.1)."""
    user_id: str = request.state.user_id
    data = body.model_dump(exclude_none=True)
    try:
        trip = await create_trip(user_id, data)
        return TripResponse(**trip)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to save trip: {exc}")


@router.get("", response_model=list[TripListItem])
async def list_saved_trips(request: Request):
    """List all trips for the authenticated user (Req 9.2)."""
    user_id: str = request.state.user_id
    try:
        trips = await list_trips(user_id)
        return [TripListItem(**t) for t in trips]
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to list trips: {exc}")


@router.get("/{trip_id}", response_model=TripResponse)
async def load_trip(trip_id: str, request: Request):
    """Load a single trip by ID (Req 9.3). Returns 403 if not owned by user."""
    user_id: str = request.state.user_id
    try:
        trip = await get_trip(trip_id, user_id)
    except PermissionError:
        raise HTTPException(status_code=403, detail="You do not have access to this trip")

    if trip is None:
        raise HTTPException(status_code=404, detail="Trip not found")

    return TripResponse(**trip)


@router.delete("/{trip_id}", status_code=204)
async def remove_trip(trip_id: str, request: Request):
    """Delete a trip by ID (Req 9.4). Returns 403 if not owned by user."""
    user_id: str = request.state.user_id
    try:
        deleted = await delete_trip(trip_id, user_id)
    except PermissionError:
        raise HTTPException(status_code=403, detail="You do not have access to this trip")

    if not deleted:
        raise HTTPException(status_code=404, detail="Trip not found")
