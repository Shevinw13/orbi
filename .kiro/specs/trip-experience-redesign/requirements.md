# Requirements Document

## Introduction

This specification covers a major redesign of the Orbi iOS travel app's trip planning experience. The redesign streamlines the trip setup screen, introduces a 4-tab generated trip experience (Itinerary, Stays, Food & Drinks, Cost), and integrates Google Places API for real pricing data. The philosophy is "generate first, customize second" — no blank states, suggestions over manual input, and contextual editing within the itinerary.

## Glossary

- **Trip_Setup_Screen**: The screen where users configure trip preferences (trip length, budget, vibes, family-friendly toggle) before generating an itinerary. Currently implemented as `PreferencesOverlay` in `ContentView.swift` and `DestinationFlowView.swift`.
- **Trip_Budget_Selector**: A 5-tier single-select component ($ / $$ / $$$ / $$$$ / $$$$$) that replaces the old Hotel Preferences price range. Maps to Budget / Casual / Comfortable / Premium / Luxury. Influences hotel, restaurant, and activity recommendations.
- **Vibe_Selector**: A multi-select pill/card component for choosing trip vibes (Foodie, Adventure, Relaxed, Nightlife, etc.). Premium visual treatment with strong selected state and muted unselected state.
- **Generated_Trip_View**: The tabbed view displayed after itinerary generation, containing 4 tabs: Itinerary, Stays, Food & Drinks, Cost. Currently `TripResultView.swift` with 3 tabs (Itinerary, Places, Cost).
- **Itinerary_Tab**: The default tab showing a day-based layout divided into Morning / Afternoon / Evening time blocks, containing activities and meals in chronological order.
- **Time_Block**: A section within a day representing Morning, Afternoon, or Evening. Contains 1-2 items (activities and/or meals).
- **Stays_Tab**: A tab for selecting and assigning hotel accommodations, with 3-5 recommendations and optional per-day assignment.
- **Food_Drinks_Tab**: A tab for refining dining selections already placed in the itinerary, showing current selections with 3-5 suggested alternatives each.
- **Cost_Tab**: A tab displaying total estimated trip cost with breakdown by Hotels, Food & Drinks, and Activities, dynamically updated based on user selections.
- **Itinerary_Engine**: The backend service (`services/itinerary.py`) that generates AI-powered itineraries via OpenAI.
- **Place_Service**: The backend service (`services/places.py`) that fetches hotel and restaurant recommendations. Currently uses Foursquare with OpenAI fallback.
- **Google_Places_Service**: A new backend service that integrates Google Places API for verified hotel and restaurant data including real ratings, photos, hours, and pricing.
- **Cost_Estimator**: The backend service (`services/cost.py`) that calculates trip cost breakdowns.
- **Replace_Suggestion**: A set of 3-5 smart alternative items generated based on city, vibe, trip budget, and proximity when a user requests to replace an itinerary item.
- **Meal_Slot**: A meal entry (Breakfast, Lunch, or Dinner) placed within a time block. Breakfast maps to Morning, Lunch to Afternoon, Dinner to Evening.
- **Cache_Layer**: The Redis-based caching layer (`services/cache.py`) used to store API responses and reduce external API costs.

## Requirements

### Requirement 1: Trip Setup — Remove Restaurant Pre-Selection

**User Story:** As a traveler, I want a cleaner trip setup screen without restaurant pre-selection, so that I can start planning faster without unnecessary upfront choices.

#### Acceptance Criteria

1. THE Trip_Setup_Screen SHALL NOT display a restaurant pre-selection section, restaurant selector component, or restaurant loading indicators.
2. WHEN the Trip_Setup_Screen loads, THE Trip_Setup_Screen SHALL omit any API calls to fetch restaurant recommendations for pre-selection purposes.
3. THE Itinerary_Engine SHALL generate restaurant recommendations as part of the itinerary without requiring user pre-selected restaurants.

### Requirement 2: Trip Setup — Replace Hotel Preferences with Trip Budget

**User Story:** As a traveler, I want to set a single trip budget tier that influences all recommendations, so that my hotels, restaurants, and activities all match my spending expectations.

#### Acceptance Criteria

1. THE Trip_Setup_Screen SHALL display a Trip_Budget_Selector with exactly 5 tiers: "$" (Budget), "$$" (Casual), "$$$" (Comfortable), "$$$$" (Premium), "$$$$$" (Luxury).
2. THE Trip_Budget_Selector SHALL allow exactly one tier to be selected at a time.
3. WHEN a budget tier is selected, THE Trip_Budget_Selector SHALL display helper text corresponding to the selected tier (Budget, Casual, Comfortable, Premium, or Luxury).
4. THE Trip_Setup_Screen SHALL remove the existing "Hotel Preferences" section including the hotel price range pills and hotel vibe selector.
5. WHEN the user submits trip preferences, THE Trip_Setup_Screen SHALL send the selected budget tier to the Itinerary_Engine as a unified budget parameter.
6. THE Itinerary_Engine SHALL use the budget tier to influence hotel recommendations, restaurant recommendations, and activity cost expectations.

### Requirement 3: Trip Setup — Multi-Select Vibe Enhancement

**User Story:** As a traveler, I want to select multiple vibes for my trip, so that I can combine interests like "Foodie" and "Adventure" in a single itinerary.

#### Acceptance Criteria

1. THE Vibe_Selector SHALL allow the user to select one or more vibes simultaneously.
2. WHEN a vibe is selected, THE Vibe_Selector SHALL display a strong selected state with visual highlight and elevation.
3. WHEN a vibe is not selected, THE Vibe_Selector SHALL display a muted unselected state.
4. THE Vibe_Selector SHALL render each vibe as a premium pill or card-style component with no text wrapping.
5. THE Vibe_Selector SHALL be the most visually expressive section on the Trip_Setup_Screen.
6. WHEN the user submits trip preferences, THE Trip_Setup_Screen SHALL send all selected vibes to the Itinerary_Engine.
7. THE Itinerary_Engine SHALL incorporate all selected vibes when generating the itinerary, balancing activities across the selected vibes.

### Requirement 4: Generated Trip View — 4-Tab Structure

**User Story:** As a traveler, I want to navigate my generated trip through 4 focused tabs, so that I can review and customize different aspects of my trip independently.

#### Acceptance Criteria

1. THE Generated_Trip_View SHALL display a header containing the city name, trip length, and selected vibe(s).
2. THE Generated_Trip_View SHALL display exactly 4 tabs: Itinerary, Stays, Food & Drinks, and Cost.
3. WHEN the Generated_Trip_View loads, THE Generated_Trip_View SHALL display the Itinerary_Tab as the default selected tab.
4. THE Generated_Trip_View SHALL replace the existing 3-tab layout (Itinerary, Places, Cost) with the new 4-tab layout.

### Requirement 5: Itinerary Tab — Day-Based Time Block Layout

**User Story:** As a traveler, I want my itinerary organized by day with Morning, Afternoon, and Evening sections, so that I can see a clear chronological plan for each day.

#### Acceptance Criteria

1. THE Itinerary_Tab SHALL display each day divided into three time blocks: Morning, Afternoon, and Evening, in strict chronological order.
2. THE Itinerary_Tab SHALL display 1-2 items per time block, targeting 3-5 items per day with a soft cap of 6 items per day.
3. THE Itinerary_Tab SHALL display a fully generated itinerary with no empty states upon initial load.
4. THE Itinerary_Tab SHALL display both activities and meals within time blocks, mapping Breakfast to Morning, Lunch to Afternoon, and Dinner to Evening.
5. WHEN the itinerary is generated, THE Itinerary_Engine SHALL produce a complete itinerary with activities and meals distributed across time blocks for each day.

### Requirement 6: Itinerary Tab — Item Actions (Replace, Remove, Add)

**User Story:** As a traveler, I want to replace, remove, or add items in my itinerary, so that I can customize the plan to my preferences.

#### Acceptance Criteria

1. THE Itinerary_Tab SHALL provide Replace, Remove, and Add actions for each itinerary item.
2. WHEN the user triggers Replace on an item, THE Itinerary_Tab SHALL display 3-5 smart suggestions based on city, vibe, trip budget, and proximity.
3. WHEN the user triggers Replace on an item, THE Itinerary_Tab SHALL provide a search option as a secondary fallback, scoped to the destination city.
4. WHEN the user triggers Remove on an item, THE Itinerary_Tab SHALL remove the item from the time block immediately.
5. THE Itinerary_Tab SHALL display a "+ Add" action within each time block.
6. WHEN the user triggers Add, THE Itinerary_Tab SHALL offer options to Add Breakfast, Add Lunch, Add Dinner, or Add Activity.
7. THE Itinerary_Tab SHALL allow multiple items to be added to a single time block.
8. THE Itinerary_Tab SHALL allow meals to be removed without forcing replacement.
9. THE Itinerary_Tab SHALL apply edits immediately and support reversibility.

### Requirement 7: Food & Drinks Tab

**User Story:** As a traveler, I want a dedicated tab to refine my dining selections, so that I can finalize restaurant choices with smart alternatives.

#### Acceptance Criteria

1. THE Food_Drinks_Tab SHALL display all meals currently placed in the itinerary, grouped by day and time block.
2. THE Food_Drinks_Tab SHALL display 3-5 suggested alternative restaurants for each meal, based on city, vibe, trip budget, and proximity.
3. WHEN the user selects an alternative restaurant, THE Food_Drinks_Tab SHALL update the corresponding meal in the itinerary.
4. THE Food_Drinks_Tab SHALL provide a search option as a secondary fallback for finding restaurants, scoped to the destination city.
5. THE Food_Drinks_Tab SHALL treat alternative suggestions as optional — the user is not required to change any selection.

### Requirement 8: Stays Tab

**User Story:** As a traveler, I want a dedicated tab to select and assign hotels, so that I can choose accommodations that match my budget and preferences.

#### Acceptance Criteria

1. THE Stays_Tab SHALL display 3-5 recommended hotels based on trip budget, vibe, and proximity to itinerary activities.
2. THE Stays_Tab SHALL default to assigning one hotel for the entire trip duration.
3. THE Stays_Tab SHALL provide an option to assign a different hotel per day, where each day displays the assigned hotel and allows the user to change the assignment.
4. THE Stays_Tab SHALL display hotel recommendations as the primary selection method, with search as a secondary fallback.
5. WHEN the user selects a hotel, THE Stays_Tab SHALL update the Cost_Tab with the selected hotel's pricing.

### Requirement 9: Cost Tab — Dynamic Cost Overview

**User Story:** As a traveler, I want a clear cost overview that updates as I customize my trip, so that I can understand the financial impact of my choices.

#### Acceptance Criteria

1. THE Cost_Tab SHALL display the total estimated trip cost with a breakdown into three categories: Hotels, Food & Drinks, and Activities.
2. WHEN the user changes a hotel selection, meal selection, or activity in any tab, THE Cost_Tab SHALL recalculate and update the displayed costs dynamically.
3. THE Cost_Tab SHALL clearly distinguish between real pricing data (from Google Places API) and estimated values (from tier-based fallbacks) using an "Estimated" label on fallback values.
4. THE Cost_Tab SHALL present cost information in a simple, digestible layout.

### Requirement 10: Google Places API Integration — Backend Service

**User Story:** As a traveler, I want to see real hotel and restaurant data with verified names, ratings, photos, and pricing, so that I can make informed decisions.

#### Acceptance Criteria

1. THE Google_Places_Service SHALL fetch hotel and restaurant data from the Google Places API, including verified names, real ratings, photos, operating hours, and pricing information.
2. WHEN the Google Places API returns pricing data, THE Google_Places_Service SHALL use the real pricing to populate hotel nightly rates and restaurant price ranges.
3. IF the Google Places API is unavailable or returns an error, THEN THE Google_Places_Service SHALL fall back to the existing Foursquare/OpenAI data sources.
4. THE Google_Places_Service SHALL replace or supplement the current Foursquare-based Place_Service as the primary data source for hotel and restaurant recommendations.

### Requirement 11: Google Places API — Response Caching

**User Story:** As a product owner, I want API responses cached to minimize costs, so that the app stays within the Google Places free tier ($200/month credit).

#### Acceptance Criteria

1. THE Cache_Layer SHALL cache Google Places API responses with a configurable TTL (default 24 hours).
2. WHEN a cached response exists for a given query, THE Google_Places_Service SHALL return the cached data without making a new API call.
3. THE Cache_Layer SHALL use a deterministic cache key derived from query parameters (location, radius, price range, type) to ensure consistent cache hits.

### Requirement 12: Google Places API — Real Pricing in Cost Tab

**User Story:** As a traveler, I want the cost tab to use real pricing data when available, so that my trip budget estimate is as accurate as possible.

#### Acceptance Criteria

1. WHEN real pricing data is available from the Google Places API, THE Cost_Estimator SHALL use the real hotel nightly rates and restaurant price ranges for cost calculations.
2. WHEN real pricing data is not available, THE Cost_Estimator SHALL fall back to tier-based estimates and label those values as "Estimated."
3. THE Cost_Tab SHALL display an "Estimated" label only on cost values derived from tier-based fallbacks, not on values from real API data.

### Requirement 13: Itinerary Engine — Budget and Multi-Vibe Support

**User Story:** As a traveler, I want the itinerary engine to understand my budget tier and multiple vibes, so that the generated plan matches my preferences.

#### Acceptance Criteria

1. THE Itinerary_Engine SHALL accept a budget tier parameter (one of: $, $$, $$$, $$$$, $$$$$) and use the tier to calibrate activity costs, restaurant price levels, and hotel recommendations.
2. THE Itinerary_Engine SHALL accept a list of vibes and generate an itinerary that balances activities across all selected vibes.
3. THE Itinerary_Engine SHALL generate meals (Breakfast, Lunch, Dinner) as part of the itinerary, placed in the appropriate time blocks (Morning, Afternoon, Evening).
4. THE Itinerary_Engine SHALL generate 3-5 items per day, with a soft cap of 6 items per day, including both activities and meals.

### Requirement 14: Replace Suggestions — Smart Contextual Alternatives

**User Story:** As a traveler, I want smart replacement suggestions when I swap an item, so that alternatives are relevant to my trip context.

#### Acceptance Criteria

1. WHEN the user requests a replacement for an itinerary item, THE Itinerary_Engine SHALL generate 3-5 alternative suggestions.
2. THE Itinerary_Engine SHALL base replacement suggestions on the destination city, selected vibes, trip budget tier, and geographic proximity to adjacent activities.
3. THE Itinerary_Engine SHALL exclude all activities already present in the itinerary from replacement suggestions.
4. THE Itinerary_Tab SHALL display a city-scoped search as a secondary option when replacement suggestions do not satisfy the user.

### Requirement 15: Trip Setup — Clean Layout

**User Story:** As a traveler, I want a clean, uncluttered trip setup screen, so that I can configure my trip quickly without visual noise.

#### Acceptance Criteria

1. THE Trip_Setup_Screen SHALL maintain the existing city header, trip length selector, family-friendly toggle, and "Generate Itinerary" CTA.
2. THE Trip_Setup_Screen SHALL use consistent spacing and avoid visual clutter between sections.
3. THE Trip_Setup_Screen SHALL present the Trip_Budget_Selector, Vibe_Selector, and Family Friendly toggle as the primary configuration options, in that order after the trip length selector.
