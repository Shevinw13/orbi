"""Explore overlay service — returns curated overlay categories for the explore map.

Cached for 6 hours. Returns up to 4 overlay categories with destination lists.
Requirements: 2.1, 2.2, 2.3, 2.4, 2.5
"""

from __future__ import annotations

import logging
from typing import Any

from backend.models.explore import ExploreOverlay, OverlayDestination
from backend.services.cache import get_cached, set_cached

logger = logging.getLogger(__name__)

OVERLAY_CACHE_TTL = 21600  # 6 hours


def _overlay_cache_key(lat: float, lng: float) -> str:
    return f"explore:overlays:{round(lat, 1)}:{round(lng, 1)}"


async def get_overlays(latitude: float, longitude: float) -> list[ExploreOverlay]:
    """Return up to 4 explore overlay categories based on user location."""
    cache_key = _overlay_cache_key(latitude, longitude)
    cached = get_cached(cache_key)
    if cached is not None:
        return [ExploreOverlay(**o) for o in cached]

    overlays = [
        ExploreOverlay(
            category="trending",
            title="Trending Destinations",
            destinations=[
                OverlayDestination(name="Tokyo", latitude=35.6762, longitude=139.6503),
                OverlayDestination(name="Barcelona", latitude=41.3874, longitude=2.1686),
                OverlayDestination(name="Bali", latitude=-8.3405, longitude=115.0920),
            ],
        ),
        ExploreOverlay(
            category="value",
            title="Best Value Trips",
            destinations=[
                OverlayDestination(name="Lisbon", latitude=38.7223, longitude=-9.1393),
                OverlayDestination(name="Bangkok", latitude=13.7563, longitude=100.5018),
                OverlayDestination(name="Marrakech", latitude=31.6295, longitude=-7.9811),
            ],
        ),
        ExploreOverlay(
            category="popular",
            title="Popular This Month",
            destinations=[
                OverlayDestination(name="Paris", latitude=48.8566, longitude=2.3522),
                OverlayDestination(name="Rome", latitude=41.9028, longitude=12.4964),
                OverlayDestination(name="Dubai", latitude=25.2048, longitude=55.2708),
            ],
        ),
        ExploreOverlay(
            category="weekend",
            title="Weekend Getaways",
            destinations=[
                OverlayDestination(name="Amsterdam", latitude=52.3676, longitude=4.9041),
                OverlayDestination(name="Prague", latitude=50.0755, longitude=14.4378),
                OverlayDestination(name="Santorini", latitude=36.3932, longitude=25.4615),
            ],
        ),
    ]

    set_cached(cache_key, [o.model_dump() for o in overlays], ttl=OVERLAY_CACHE_TTL)
    return overlays
