"""Weather routes — destination weather and best time to visit.

Requirements: 17.3, 17.4
"""

from __future__ import annotations

from fastapi import APIRouter, Query

from backend.models.weather import WeatherResponse
from backend.services.weather import get_weather

router = APIRouter(prefix="/destinations", tags=["destinations"])


@router.get("/weather", response_model=WeatherResponse)
async def weather(
    latitude: float = Query(..., description="Destination latitude"),
    longitude: float = Query(..., description="Destination longitude"),
):
    """Return current weather and best time to visit for a destination."""
    return await get_weather(latitude, longitude)
