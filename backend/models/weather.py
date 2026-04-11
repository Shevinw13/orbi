"""Pydantic models for Weather service.

Requirements: 17.3, 17.4
"""

from __future__ import annotations

from pydantic import BaseModel


class WeatherResponse(BaseModel):
    temp_high: float
    temp_low: float
    condition: str
    best_time_to_visit: str
