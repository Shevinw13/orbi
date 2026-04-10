"""Cost estimation route.

Requirements: 8.1, 8.2, 8.3, 8.4
"""

from __future__ import annotations

from fastapi import APIRouter

from backend.models.cost import CostBreakdown, CostRequest
from backend.services.cost import calculate_cost

router = APIRouter(tags=["cost"])


@router.post(
    "/trips/cost",
    response_model=CostBreakdown,
    summary="Estimate trip cost",
    description="Pure computation — returns hotel, food, and activity cost breakdown.",
)
async def estimate_cost(request: CostRequest) -> CostBreakdown:
    """Calculate estimated trip cost (Req 8.1, 8.2, 8.3, 8.4)."""
    return calculate_cost(request)
