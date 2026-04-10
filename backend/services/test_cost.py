"""Unit tests for Cost_Estimator service.

Requirements: 8.1, 8.2, 8.3, 8.4
"""

from backend.models.cost import ActivityCostItem, CostRequest, CostRequestDay
from backend.services.cost import calculate_cost


def test_hotel_cost_nightly_rate_times_days():
    """Req 8.1 — hotel_cost = nightly_rate × num_days."""
    req = CostRequest(num_days=3, hotel_nightly_rate=150.0, restaurant_price_range="$")
    result = calculate_cost(req)
    assert result.hotel_total == 450.0


def test_food_cost_dollar_sign():
    """Req 8.2 — $ = $30/day."""
    req = CostRequest(num_days=2, hotel_nightly_rate=0, restaurant_price_range="$")
    result = calculate_cost(req)
    assert result.food_total == 60.0


def test_food_cost_double_dollar():
    """Req 8.2 — $$ = $60/day."""
    req = CostRequest(num_days=2, hotel_nightly_rate=0, restaurant_price_range="$$")
    result = calculate_cost(req)
    assert result.food_total == 120.0


def test_food_cost_triple_dollar():
    """Req 8.2 — $$$ = $100/day."""
    req = CostRequest(num_days=1, hotel_nightly_rate=0, restaurant_price_range="$$$")
    result = calculate_cost(req)
    assert result.food_total == 100.0


def test_food_cost_quad_dollar():
    """Req 8.2 — $$$$ = $200/day."""
    req = CostRequest(num_days=1, hotel_nightly_rate=0, restaurant_price_range="$$$$")
    result = calculate_cost(req)
    assert result.food_total == 200.0


def test_activity_cost_sum():
    """Req 8.3 — activity_cost = sum of individual costs."""
    days = [
        CostRequestDay(
            day_number=1,
            activities=[
                ActivityCostItem(activity_name="Museum", estimated_cost_usd=20),
                ActivityCostItem(activity_name="Tour", estimated_cost_usd=35),
            ],
        ),
    ]
    req = CostRequest(num_days=1, hotel_nightly_rate=0, restaurant_price_range="$", days=days)
    result = calculate_cost(req)
    assert result.activities_total == 55.0


def test_per_day_breakdown():
    """Req 8.4 — per-day breakdown returned."""
    days = [
        CostRequestDay(
            day_number=1,
            activities=[ActivityCostItem(activity_name="A", estimated_cost_usd=10)],
        ),
        CostRequestDay(
            day_number=2,
            activities=[ActivityCostItem(activity_name="B", estimated_cost_usd=25)],
        ),
    ]
    req = CostRequest(
        num_days=2, hotel_nightly_rate=100.0, restaurant_price_range="$$", days=days
    )
    result = calculate_cost(req)

    assert len(result.per_day) == 2
    d1 = result.per_day[0]
    assert d1.day == 1
    assert d1.hotel == 100.0
    assert d1.food == 60.0
    assert d1.activities == 10.0
    assert d1.subtotal == 170.0

    d2 = result.per_day[1]
    assert d2.day == 2
    assert d2.activities == 25.0
    assert d2.subtotal == 185.0


def test_total_equals_sum_of_components():
    """Req 8.4 — total = hotel_total + food_total + activities_total."""
    days = [
        CostRequestDay(
            day_number=1,
            activities=[ActivityCostItem(activity_name="X", estimated_cost_usd=40)],
        ),
    ]
    req = CostRequest(
        num_days=1, hotel_nightly_rate=200.0, restaurant_price_range="$$$", days=days
    )
    result = calculate_cost(req)
    assert result.total == result.hotel_total + result.food_total + result.activities_total
    assert result.total == 200.0 + 100.0 + 40.0


def test_days_without_activities():
    """Days with no activity data should have 0 activity cost."""
    req = CostRequest(num_days=3, hotel_nightly_rate=50.0, restaurant_price_range="$")
    result = calculate_cost(req)
    assert result.activities_total == 0.0
    assert len(result.per_day) == 3
    for d in result.per_day:
        assert d.activities == 0.0


def test_unknown_price_range_falls_back():
    """Unknown price range should use default $30/day."""
    req = CostRequest(num_days=1, hotel_nightly_rate=0, restaurant_price_range="?")
    result = calculate_cost(req)
    assert result.food_total == 30.0
