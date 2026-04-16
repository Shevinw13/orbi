# Implementation Plan: Trip Experience Redesign

## Overview

Major redesign of the Orbi trip planning experience spanning Python/FastAPI backend and Swift/SwiftUI iOS client. Implementation follows a strict dependency order: backend models → backend engine → Google Places integration → cost estimator → iOS models → iOS trip setup → iOS generated trip view (4 tabs) → iOS itinerary tab → iOS stays tab → iOS food & drinks tab → iOS cost tab.

## Tasks

- [x] 1. Backend model changes (foundation for all other work)
  - [x] 1.1 Update `ItineraryRequest` in `backend/models/itinerary.py`
    - Replace `hotel_price_range`, `hotel_vibe`, `restaurant_price_range`, `cuisine_type`, `vibe` (singular), and `selected_restaurants` fields with `budget_tier: str` and `vibes: list[str]` (min_length=1)
    - Remove `SelectedRestaurant` model
    - _Requirements: 2.5, 13.1, 13.2_

  - [x] 1.2 Add `MealSlot` model in `backend/models/itinerary.py`
    - Add `MealSlot` with fields: `meal_type`, `restaurant_name`, `cuisine`, `price_level`, `latitude`, `longitude`, `estimated_cost_usd`, `place_id`, `is_estimated`
    - _Requirements: 5.4, 13.3_

  - [x] 1.3 Update `ItineraryDay` in `backend/models/itinerary.py`
    - Add `meals: list[MealSlot]` field with default empty list
    - Remove `restaurant: RestaurantRecommendation | None` field
    - _Requirements: 5.1, 5.4_

  - [x] 1.4 Update `ItineraryResponse` in `backend/models/itinerary.py`
    - Replace `vibe: str` with `vibes: list[str]`
    - Add `budget_tier: str`
    - _Requirements: 4.1, 13.1, 13.2_

  - [x] 1.5 Update `ReplaceActivityRequest` in `backend/models/itinerary.py`
    - Replace `vibe: str` with `vibes: list[str]`
    - Add `budget_tier: str`, `item_type: str` ("activity" or "meal"), `num_suggestions: int` (default 5, ge=1, le=10)
    - Rename `current_activity_name` to `current_item_name`
    - _Requirements: 6.2, 14.1, 14.2_

  - [x] 1.6 Add `ReplaceSuggestionsResponse` in `backend/models/itinerary.py`
    - New model with `suggestions: list[ActivitySlot | MealSlot]`
    - _Requirements: 14.1_

  - [x] 1.7 Add `GooglePlaceResult` model in `backend/models/places.py`
    - Add model with fields: `place_id`, `name`, `rating`, `user_ratings_total`, `price_level`, `price_level_display`, `photo_references`, `latitude`, `longitude`, `formatted_address`, `opening_hours`, `price_range_min`, `price_range_max`, `is_estimated`
    - _Requirements: 10.1, 10.2_

  - [x] 1.8 Update cost models in `backend/models/cost.py`
    - Add `hotel_is_estimated: bool` and `food_is_estimated: bool` to `DayCost`
    - Add `hotel_is_estimated: bool` and `food_is_estimated: bool` to `CostBreakdown`
    - _Requirements: 9.3, 12.1, 12.2, 12.3_

  - [ ]* 1.9 Write property test: Budget Tier Label Mapping
    - **Property 1: Budget Tier Single Selection Invariant**
    - Generate random BudgetTier values, verify label mapping is bijective and exactly one tier is selected
    - **Validates: Requirements 2.2, 2.3**

  - [ ]* 1.10 Write property test: Cost Total Equals Sum of Categories
    - **Property 13: Cost Total Equals Sum of Categories**
    - Generate random `CostBreakdown` objects, verify `total == hotel_total + food_total + activities_total` and each day's `subtotal == hotel + food + activities`
    - **Validates: Requirements 9.1, 9.2**

  - [ ]* 1.11 Write property test: Estimated Flag Reflects Data Source
    - **Property 14: Estimated Flag Reflects Data Source**
    - Generate random cost items with mixed sources, verify `is_estimated` is `false` for Google Places data and `true` for tier-based fallbacks
    - **Validates: Requirements 9.3, 12.1, 12.2, 12.3**

- [x] 2. Checkpoint — Backend models
  - Ensure all model changes compile and existing tests pass, ask the user if questions arise.

- [x] 3. Backend itinerary engine updates (`backend/services/itinerary.py`)
  - [x] 3.1 Rewrite `_build_prompt` for budget tier, multi-vibe, and meals
    - Accept `budget_tier` instead of separate hotel/restaurant price ranges
    - Accept `vibes: list[str]` instead of single `vibe`
    - Instruct OpenAI to generate meals (Breakfast, Lunch, Dinner) within time blocks
    - Target 3-5 items per day (activities + meals), soft cap 6
    - Update budget tier mapping table for prompt calibration
    - _Requirements: 2.6, 3.7, 5.5, 13.1, 13.2, 13.3, 13.4_

  - [x] 3.2 Update `_build_cache_key` for new request fields
    - Hash `budget_tier` and `vibes` instead of old preference fields
    - _Requirements: 13.1_

  - [x] 3.3 Update `_parse_itinerary_response` to parse meals
    - Parse `meals` array from each day in the OpenAI JSON response into `MealSlot` objects
    - Map meals to `ItineraryDay.meals`
    - _Requirements: 5.4, 5.5, 13.3_

  - [x] 3.4 Update `generate_itinerary` function signature and flow
    - Accept updated `ItineraryRequest` with `budget_tier` and `vibes`
    - Return updated `ItineraryResponse` with `vibes` list and `budget_tier`
    - _Requirements: 1.3, 2.5, 2.6, 3.6, 3.7_

  - [x] 3.5 Update replace logic for 3-5 suggestions
    - Rewrite `_build_replace_prompt` to accept `vibes` list, `budget_tier`, `item_type`, and `num_suggestions`
    - Return `ReplaceSuggestionsResponse` with 3-5 suggestions instead of a single replacement
    - Exclude items in `existing_activities` from suggestions
    - _Requirements: 6.2, 14.1, 14.2, 14.3_

  - [ ]* 3.6 Write property test: Prompt Includes Budget and All Vibes
    - **Property 3: Itinerary Prompt Includes Budget and All Vibes**
    - Generate random budget tiers and vibe lists, verify `_build_prompt` output contains the budget tier string and every vibe
    - **Validates: Requirements 2.6, 3.7, 13.1, 13.2**

  - [ ]* 3.7 Write property test: Items Per Day Within Bounds
    - **Property 5: Items Per Day Within Bounds**
    - Generate random `ItineraryDay` objects, verify total items (slots + meals) is between 3 and 6
    - **Validates: Requirements 5.2, 13.4**

  - [ ]* 3.8 Write property test: Meal-to-Time-Block Mapping
    - **Property 6: Meal-to-Time-Block Mapping**
    - Generate random `MealSlot` objects, verify Breakfast→Morning, Lunch→Afternoon, Dinner→Evening
    - **Validates: Requirements 5.4, 13.3**

  - [ ]* 3.9 Write property test: Replace Returns 3-5 Suggestions
    - **Property 8: Replace Returns 3-5 Suggestions**
    - Generate random `ReplaceActivityRequest` objects, verify response contains 3-5 suggestions with no names from `existing_activities`
    - **Validates: Requirements 6.2, 7.2, 14.1, 14.3**

  - [ ]* 3.10 Write property test: Replace Prompt Includes Context
    - **Property 9: Replace Prompt Includes Context**
    - Generate random replace requests with destination, vibes, budget_tier, and adjacent coords, verify prompt references all
    - **Validates: Requirements 14.2**

- [x] 4. Checkpoint — Backend engine
  - Ensure all itinerary engine changes work with updated models and tests pass, ask the user if questions arise.

- [x] 5. Google Places API integration (new backend service)
  - [x] 5.1 Create `backend/services/google_places.py`
    - Implement `search_nearby_places(place_type, latitude, longitude, radius, budget_tier, keyword)` using Google Places Nearby Search API
    - Implement `get_place_details(place_id)` for photos, hours, and real pricing
    - Map Google `price_level` (0-4) to dollar-sign display strings
    - Set `is_estimated = false` when real pricing data is available
    - Integrate with Redis cache using key format `gplaces:{type}:{hash(params)}` and 24h TTL
    - _Requirements: 10.1, 10.2, 11.1, 11.2, 11.3_

  - [x] 5.2 Update `backend/services/places.py` fallback chain
    - Add Google Places as primary source (when API key is configured)
    - Keep Foursquare as secondary fallback
    - Keep OpenAI as tertiary fallback
    - Return empty results with `filters_broadened=true` if all sources fail
    - Update query params to accept `budget_tier` instead of `price_range` + `vibe`
    - _Requirements: 10.3, 10.4_

  - [x] 5.3 Update `backend/config.py` for Google Places API key
    - Ensure `google_places_api_key` field is active and documented (currently exists but marked deprecated)
    - _Requirements: 10.1_

  - [ ]* 5.4 Write property test: Google Places Price Mapping
    - **Property 17: Google Places Price Mapping**
    - Generate random `price_level` values (0-4), verify mapped `price_level_display` is valid dollar-sign string and `is_estimated` is `false` when real pricing present
    - **Validates: Requirements 10.2**

  - [ ]* 5.5 Write property test: Cache Key Determinism
    - **Property 15: Cache Key Determinism**
    - Generate random `PlaceQuery` pairs, verify identical params → identical keys, different params → different keys
    - **Validates: Requirements 11.3**

  - [ ]* 5.6 Write property test: Cache Round-Trip Preserves Data
    - **Property 16: Cache Round-Trip Preserves Data**
    - Generate random `PlacesResponse` objects, store in cache and retrieve, verify equality
    - **Validates: Requirements 11.1, 11.2**

- [x] 6. Backend cost estimator updates (`backend/services/cost.py` and `backend/models/cost.py`)
  - [x] 6.1 Update `calculate_cost` to support `is_estimated` flags
    - Add `hotel_is_estimated` and `food_is_estimated` to `DayCost` and `CostBreakdown` outputs
    - When real pricing from Google Places is available, set `is_estimated = false`
    - When using tier-based fallback, set `is_estimated = true`
    - Update budget tier mapping to 5 tiers (Budget through Luxury)
    - _Requirements: 9.3, 12.1, 12.2, 12.3_

  - [x] 6.2 Update routes to pass real pricing data to cost estimator
    - Wire Google Places real pricing into cost calculation when available
    - _Requirements: 12.1_

- [x] 7. Checkpoint — Backend complete
  - Ensure all backend changes compile, all tests pass, and the fallback chain works end-to-end, ask the user if questions arise.

- [ ] 8. iOS model changes (`ios/Orbi/Models/TripModels.swift`)
  - [-] 8.1 Add `BudgetTier` enum
    - Create `BudgetTier` enum with 5 cases: `budget`, `casual`, `comfortable`, `premium`, `luxury` with raw values "$" through "$$$" and `label` computed property
    - Conform to `CaseIterable`, `Identifiable`, `Codable`
    - _Requirements: 2.1, 2.2, 2.3_

  - [~] 8.2 Add `MealSlot` model
    - Create `MealSlot` struct with fields: `mealType`, `restaurantName`, `cuisine`, `priceLevel`, `latitude`, `longitude`, `estimatedCostUsd`, `placeId`, `isEstimated`
    - Conform to `Codable`, `Identifiable`, `Equatable`
    - _Requirements: 5.4, 13.3_

  - [~] 8.3 Update `ItineraryDay` to include meals
    - Add `meals: [MealSlot]` field
    - Remove `restaurant: ItineraryRestaurant?` field
    - Add `timeBlockItems` computed property that merges slots and meals in chronological order
    - _Requirements: 5.1, 5.4_

  - [~] 8.4 Update `ItineraryResponse`
    - Replace `vibe: String` with `vibes: [String]`
    - Add `budgetTier: String`
    - _Requirements: 4.1, 13.1_

  - [~] 8.5 Update `TripPreferencesRequest`
    - Replace `hotelPriceRange`, `hotelVibe`, `restaurantPriceRange`, `cuisineType`, `vibe`, `selectedRestaurants` with `budgetTier: String` and `vibes: [String]`
    - _Requirements: 2.5, 3.6_

  - [ ]* 8.6 Write property test: Multi-Vibe Selection Integrity
    - **Property 2: Multi-Vibe Selection Integrity**
    - Generate random non-empty subsets of TripVibe values, verify `selectedVibes` set contains exactly those vibes and encoded request includes all
    - **Validates: Requirements 3.1, 3.6**

  - [ ]* 8.7 Write property test: Meal Grouping Round-Trip
    - **Property 10: Meal Grouping Round-Trip**
    - Generate random itineraries, extract all meals and group by (dayNumber, mealType), verify same set as original days' meal lists
    - **Validates: Requirements 7.1**

- [ ] 9. iOS trip setup screen changes (`ios/Orbi/Views/DestinationFlowView.swift`, `ios/Orbi/Views/ContentView.swift`)
  - [~] 9.1 Remove restaurant pre-selection from trip setup
    - Remove `RestaurantSelector` usage from `PreferencesOverlay` in `ContentView.swift`
    - Remove restaurant loading indicators and restaurant-related API calls from trip setup flow
    - Delete or deprecate `RestaurantSelector.swift` if no longer referenced
    - _Requirements: 1.1, 1.2_

  - [~] 9.2 Replace hotel preferences with `BudgetTier` selector
    - Remove `PriceRange` enum and hotel price range pills from `DestinationFlowView.swift`
    - Remove `HotelVibe` enum and hotel vibe selector
    - Add `BudgetTier` selector UI with 5 tiers, single-select behavior, and helper text for selected tier
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [~] 9.3 Convert vibe to multi-select
    - Change `selectedVibe: TripVibe` to `selectedVibes: Set<TripVibe>` in the view model
    - Update `TripVibe` UI to pill/card style with strong selected state (highlight + elevation) and muted unselected state
    - Ensure at-least-one validation (disable Generate button if empty)
    - Make vibe selector the most visually expressive section
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

  - [~] 9.4 Clean up trip setup layout
    - Arrange sections in order: trip length selector → Budget Tier → Vibe Selector → Family Friendly toggle → Generate CTA
    - Maintain existing city header
    - Ensure consistent spacing between sections
    - _Requirements: 15.1, 15.2, 15.3_

  - [~] 9.5 Wire updated preferences to API call
    - Update the `POST /trips/generate` call to send `budgetTier` and `vibes` array instead of old fields
    - Remove `selectedRestaurants` from the request payload
    - _Requirements: 2.5, 3.6, 1.2_

- [ ] 10. Checkpoint — iOS trip setup
  - Ensure trip setup screen builds, displays correctly, and sends the updated request payload, ask the user if questions arise.

- [ ] 11. iOS generated trip view — 4-tab structure (`ios/Orbi/Views/TripResultView.swift`)
  - [~] 11.1 Update `TripResultTab` enum to 4 tabs
    - Replace current 3-tab enum (Itinerary, Places, Cost) with 4 tabs: Itinerary, Stays, Food & Drinks, Cost
    - Update icons for each tab
    - _Requirements: 4.2, 4.4_

  - [~] 11.2 Update `TripResultView` header and init
    - Display city name, trip length, and selected vibes in the header
    - Update init to accept `vibes: [String]` and `budgetTier: String` instead of old hotel/restaurant params
    - Set default selected tab to `.itinerary`
    - _Requirements: 4.1, 4.3_

  - [~] 11.3 Update tab picker and content switching
    - Wire tab picker to show all 4 tabs
    - Add placeholder views for `StaysView` and `FoodDrinksView` (implemented in later tasks)
    - _Requirements: 4.2_

- [ ] 12. iOS Itinerary tab — time block layout with meals (`ios/Orbi/Views/ItineraryView.swift`)
  - [~] 12.1 Update day sections for Morning/Afternoon/Evening with meals
    - Display each day divided into Morning, Afternoon, Evening time blocks in chronological order
    - Render both activities and meals within time blocks using `ItineraryDay.timeBlockItems`
    - Map Breakfast→Morning, Lunch→Afternoon, Dinner→Evening
    - Target 1-2 items per time block, 3-5 items per day
    - Ensure fully generated itinerary with no empty states on initial load
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [~] 12.2 Add meal actions (Add Breakfast/Lunch/Dinner)
    - Add "+ Add" action within each time block
    - Offer options: Add Breakfast, Add Lunch, Add Dinner, Add Activity
    - Allow multiple items per time block
    - Allow meals to be removed without forcing replacement
    - Apply edits immediately
    - _Requirements: 6.5, 6.6, 6.7, 6.8, 6.9_

  - [~] 12.3 Update replace to show 3-5 suggestions
    - When user triggers Replace, call updated `POST /trips/replace-item` endpoint
    - Display 3-5 smart suggestions in a selection UI
    - Provide city-scoped search as secondary fallback
    - Support Replace, Remove, and Add actions for each item
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 14.4_

  - [ ]* 12.4 Write property test: Remove Activity Decreases Count
    - **Property 7: Remove Activity Decreases Count**
    - Generate random `ItineraryDay` with N slots, remove one, verify N-1 remaining and removed slot absent
    - **Validates: Requirements 6.4**

  - [ ]* 12.5 Write property test: Meal Replacement Updates Correct Position
    - **Property 11: Meal Replacement Updates Correct Position**
    - Generate random itineraries and alternative restaurants, verify only the target meal's fields update while `mealType` and `dayNumber` are preserved
    - **Validates: Requirements 7.3**

- [ ] 13. Checkpoint — iOS itinerary tab
  - Ensure itinerary tab renders time blocks with meals, replace suggestions work, and item actions function correctly, ask the user if questions arise.

- [ ] 14. iOS Stays tab (`ios/Orbi/Views/StaysView.swift`)
  - [~] 14.1 Create `StaysView` with hotel recommendations
    - Create new `StaysView.swift` file
    - Display 3-5 hotel recommendations based on budget tier, vibes, and proximity
    - Default to one hotel for entire trip duration
    - Provide option for per-day hotel assignment
    - Include search as secondary fallback
    - _Requirements: 8.1, 8.2, 8.3, 8.4_

  - [~] 14.2 Wire hotel selection to cost recalculation
    - When user selects a hotel, trigger cost recalculation with the hotel's nightly rate
    - Pass `is_estimated` flag based on data source
    - _Requirements: 8.5, 9.2_

  - [ ]* 14.3 Write property test: Hotel Selection Updates Cost
    - **Property 12: Hotel Selection Updates Cost**
    - Generate random hotel rates and trip lengths, verify `hotel_total == nightly_rate × num_days` and `total == hotel_total + food_total + activities_total`
    - **Validates: Requirements 8.5, 9.2**

- [ ] 15. iOS Food & Drinks tab (`ios/Orbi/Views/FoodDrinksView.swift`)
  - [~] 15.1 Create `FoodDrinksView` with meal alternatives
    - Create new `FoodDrinksView.swift` file
    - Display all meals from the itinerary grouped by day and time block
    - Show 3-5 suggested alternative restaurants for each meal
    - When user selects an alternative, update the corresponding meal in the itinerary
    - Include search as secondary fallback
    - Treat alternatives as optional — user not required to change any selection
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

- [ ] 16. iOS Cost tab updates (`ios/Orbi/Views/CostBreakdownView.swift`)
  - [~] 16.1 Add `is_estimated` labels and dynamic updates
    - Display total estimated trip cost with breakdown: Hotels, Food & Drinks, Activities
    - Show "Estimated" label on values derived from tier-based fallbacks (where `is_estimated == true`)
    - Do not show "Estimated" label on values from real Google Places API data
    - Recalculate and update costs dynamically when hotel, meal, or activity selections change in any tab
    - Present cost information in a simple, digestible layout
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 12.3_

- [x] 17. Final checkpoint — Full integration
  - Ensure all 4 tabs render correctly, trip setup sends updated payload, itinerary includes meals, stays and food tabs show recommendations, cost tab shows real vs estimated labels, and all tests pass. Ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation at each major milestone
- Property tests validate universal correctness properties from the design document
- Implementation order follows strict dependency chain: backend models → engine → Google Places → cost → iOS models → iOS setup → iOS tabs
