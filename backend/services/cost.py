"""Cost_Estimator — pure computation module for trip cost estimation.

No external API calls. Calculates hotel, food, and activity costs
and returns a total with per-day breakdown.

Requirements: 8.1, 8.2, 8.3, 8.4
"""

from __future__ import annotations

from backend.models.cost import CostBreakdown, CostRequest, CostRequestDay, DayCost

# Daily food cost estimates by restaurant price range (Req 8.2).
FOOD_COST_MAP: dict[str, float] = {
    "$": 30.0,
    "$$": 60.0,
    "$$$": 100.0,
    "$$$$": 200.0,
}

DEFAULT_FOOD_COST = 30.0  # fallback if price range is unrecognised


def _daily_food_cost(price_range: str) -> float:
    """Return the daily food estimate for a given price range."""
    return FOOD_COST_MAP.get(price_range, DEFAULT_FOOD_COST)


def _day_activity_cost(day: CostRequestDay) -> float:
    """Sum individual activity costs for a single day (Req 8.3)."""
    return sum(a.estimated_cost_usd for a in day.activities)


def calculate_cost(request: CostRequest) -> CostBreakdown:
    """Calculate the full trip cost breakdown (Req 8.1, 8.2, 8.3, 8.4).

    - hotel_cost  = nightly_rate × num_days  (Req 8.1)
    - food_cost   = daily_estimate × num_days (Req 8.2)
    - activity_cost = sum of individual costs  (Req 8.3)
    - Returns total and per-day breakdown      (Req 8.4)
    """
    nightly_rate = request.hotel_nightly_rate
    daily_food = _daily_food_cost(request.restaurant_price_range)

    # Build a lookup of day_number → CostRequestDay for activity costs.
    day_map: dict[int, CostRequestDay] = {d.day_number: d for d in request.days}

    per_day: list[DayCost] = []
    hotel_total = 0.0
    food_total = 0.0
    activities_total = 0.0

    for day_num in range(1, request.num_days + 1):
        hotel = nightly_rate
        food = daily_food
        activities = _day_activity_cost(day_map[day_num]) if day_num in day_map else 0.0
        subtotal = hotel + food + activities

        per_day.append(
            DayCost(
                day=day_num,
                hotel=hotel,
                food=food,
                activities=activities,
                subtotal=subtotal,
            )
        )

        hotel_total += hotel
        food_total += food
        activities_total += activities

    return CostBreakdown(
        hotel_total=hotel_total,
        food_total=food_total,
        activities_total=activities_total,
        total=hotel_total + food_total + activities_total,
        per_day=per_day,
    )
