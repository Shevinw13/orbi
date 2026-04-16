"""Weather service — Open-Meteo API proxy.

Uses the free Open-Meteo API (no key needed) to fetch current weather data.
Cached with 1-hour TTL.

Requirements: 17.3, 17.4
"""

from __future__ import annotations

import logging

import httpx

from backend.models.weather import WeatherResponse
from backend.services.cache import get_cached, set_cached

logger = logging.getLogger(__name__)

OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"
WEATHER_CACHE_TTL = 3600  # 1 hour


def _cache_key(lat: float, lng: float) -> str:
    return f"weather:v2:{round(lat, 2)}:{round(lng, 2)}"


# WMO weather code to condition string mapping
_WMO_CONDITIONS: dict[int, str] = {
    0: "Clear sky",
    1: "Mainly clear",
    2: "Partly cloudy",
    3: "Overcast",
    45: "Foggy",
    48: "Depositing rime fog",
    51: "Light drizzle",
    53: "Moderate drizzle",
    55: "Dense drizzle",
    61: "Slight rain",
    63: "Moderate rain",
    65: "Heavy rain",
    71: "Slight snow",
    73: "Moderate snow",
    75: "Heavy snow",
    80: "Slight rain showers",
    81: "Moderate rain showers",
    82: "Violent rain showers",
    95: "Thunderstorm",
}


def _best_time_to_visit(latitude: float) -> str:
    """Heuristic best time to visit based on latitude band."""
    abs_lat = abs(latitude)
    if abs_lat < 15:
        return "November – March (dry season)"
    elif abs_lat < 30:
        return "October – April (mild weather)"
    elif abs_lat < 50:
        return "May – September (summer)"
    else:
        return "June – August (warmest months)"


async def get_weather(latitude: float, longitude: float) -> WeatherResponse:
    """Fetch current weather from Open-Meteo and return structured response."""
    cache_key = _cache_key(latitude, longitude)
    cached = get_cached(cache_key)
    if cached is not None:
        return WeatherResponse(**cached)

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(
                OPEN_METEO_URL,
                params={
                    "latitude": latitude,
                    "longitude": longitude,
                    "daily": "temperature_2m_max,temperature_2m_min,weather_code",
                    "temperature_unit": "fahrenheit",
                    "timezone": "auto",
                    "forecast_days": 1,
                },
            )
            resp.raise_for_status()
            data = resp.json()

        daily = data.get("daily", {})
        temp_high = daily.get("temperature_2m_max", [20.0])[0]
        temp_low = daily.get("temperature_2m_min", [10.0])[0]
        weather_code = daily.get("weather_code", [0])[0]
        condition = _WMO_CONDITIONS.get(weather_code, "Unknown")

    except Exception as exc:
        logger.warning("Open-Meteo request failed for lat=%s, lng=%s: %s", latitude, longitude, exc, exc_info=True)
        temp_high = 0.0
        temp_low = 0.0
        condition = "Unavailable"

    result = WeatherResponse(
        temp_high=temp_high,
        temp_low=temp_low,
        condition=condition,
        best_time_to_visit=_best_time_to_visit(latitude),
    )

    set_cached(cache_key, result.model_dump(), ttl=WEATHER_CACHE_TTL)
    return result
