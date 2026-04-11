"""Pydantic models for Explore overlays.

Requirements: 2.1, 2.2, 2.3
"""

from __future__ import annotations

from pydantic import BaseModel


class OverlayDestination(BaseModel):
    name: str
    latitude: float
    longitude: float


class ExploreOverlay(BaseModel):
    category: str
    title: str
    destinations: list[OverlayDestination]


class ExploreOverlaysResponse(BaseModel):
    overlays: list[ExploreOverlay]
