"""Share routes — create and resolve share links.

POST /trips/{trip_id}/share  → authenticated, generates share link
GET  /share/{share_id}       → public, returns read-only trip data

Requirements: 10.1, 10.2, 10.3, 10.4
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request

from backend.models.share import SharedTripResponse, ShareResponse
from backend.services.share import create_share_link, get_shared_trip

# Router for the authenticated share-creation endpoint (lives under /trips)
share_write_router = APIRouter(prefix="/trips", tags=["share"])

# Router for the public share-read endpoint (lives under /share)
share_read_router = APIRouter(prefix="/share", tags=["share"])


@share_write_router.post("/{trip_id}/share", response_model=ShareResponse)
async def create_share(trip_id: str, request: Request):
    """Generate a share link for a trip (Req 10.1). Requires auth."""
    user_id: str = request.state.user_id
    try:
        result = await create_share_link(trip_id, user_id)
    except LookupError:
        raise HTTPException(status_code=404, detail="Trip not found")
    except PermissionError:
        raise HTTPException(status_code=403, detail="You do not have access to this trip")

    share_id = result["share_id"]
    share_url = f"{request.base_url}share/{share_id}"
    return ShareResponse(share_id=share_id, share_url=share_url)


@share_read_router.get("/{share_id}", response_model=SharedTripResponse)
async def read_shared_trip(share_id: str):
    """Return read-only trip data for a share link (Req 10.2, 10.3, 10.4). No auth required."""
    trip = await get_shared_trip(share_id)
    if trip is None:
        raise HTTPException(status_code=404, detail="Shared trip not found")
    return SharedTripResponse(**trip)
