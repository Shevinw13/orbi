"""Pydantic models for the Cost_Estimator module.

Pure computation — no external API calls.
Requirements: 8.1, 8.2, 8.3, 8.4, 9.3, 12.1, 12.2, 12.3
"""

from __future__ import annotations

from pydantic import BaseModel, Field


class ActivityCostItem(BaseModel):
    """A single activity with its estimated cost."""

    activity_name: str = ""
    estimated_cost_usd: float = Field(0.0, ge=0, description="Cost in USD for this activity")


class CostRequestDay(BaseModel):
    """Activities for a single day, used as input to cost calculation."""

    day_number: int = Field(..., ge=1)
    activities: list[ActivityCostItem] = Field(default_factory=list)


class CostRequest(BaseModel):
    """Input for the Cost_Estimator (Req 8.1, 8.2, 8.3)."""

    num_days: int = Field(..., ge=1, le=14, description="Trip length in days")
    hotel_nightly_rate: float = Field(0.0, ge=0, description="Hotel nightly rate in USD (Req 8.1)")
    restaurant_price_range: str = Field(
        "$",
        description="Restaurant price range or budget tier (Req 8.2)",
    )
    days: list[CostRequestDay] = Field(
        default_factory=list,
        description="Per-day activity lists for activity cost calculation (Req 8.3)",
    )
    hotel_is_estimated: bool = Field(True, description="True if hotel rate is tier-based estimate")
    food_is_estimated: bool = Field(True, description="True if food cost is tier-based estimate")


class DayCost(BaseModel):
    """Cost breakdown for a single day (Req 8.4, 9.3)."""

    day: int
    hotel: float
    hotel_is_estimated: bool = True
    food: float
    food_is_estimated: bool = True
    activities: float
    subtotal: float


class CostBreakdown(BaseModel):
    """Full trip cost breakdown (Req 8.4, 9.3, 12.1, 12.2, 12.3)."""

    hotel_total: float
    hotel_is_estimated: bool = True
    food_total: float
    food_is_estimated: bool = True
    activities_total: float
    total: float
    per_day: list[DayCost]
