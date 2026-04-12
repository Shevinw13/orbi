# Implementation Plan: Data Trust & Clarity

## Overview

Implement data trust and clarity improvements across the Orbi backend (Python/FastAPI) and iOS app (Swift/SwiftUI). The plan follows a foundation-first approach: backend enrichment → iOS pricing → external links → rating attribution → origin labels → restaurant selection/injection → UI density verification.

## Tasks

- [ ] 1. Backend price range enrichment
  - [x] 1.1 Add tier-to-range mapping in `backend/services/places.py`
    - In `_fetch_openai_places`, populate `price_range_min` and `price_range_max` on each result based on the tier mapping table: restaurant $ → 10/20, $$ → 20/40, $$$ → 40/70; hotel $ → 60/100, $$ → 120/180, $$$ → 200/300
    - In `_parse_foursquare_result`, apply the same tier-to-range mapping when Foursquare does not provide numeric price data
    - Default to mid-tier values for unrecognized tier strings
    - _Requirements: 9.1, 9.2, 9.3_

  - [ ]* 1.2 Write property test for tier-to-range mapping (Python/Hypothesis)
    - **Property 13: Tier-to-range mapping is consistent**
    - **Validates: Requirements 9.1, 9.2, 9.3**

  - [ ]* 1.3 Write unit tests for backend price enrichment
    - Test each specific tier mapping for restaurants and hotels
    - Test unrecognized tier fallback to mid-tier
    - Test that existing Foursquare numeric data is not overridden
    - _Requirements: 9.1, 9.2, 9.3_

- [ ] 2. Backend itinerary model changes for restaurant injection
  - [x] 2.1 Add `SelectedRestaurant` model and extend `ItineraryRequest` in `backend/models/itinerary.py`
    - Add `SelectedRestaurant` Pydantic model with fields: name, cuisine, price_level, latitude, longitude
    - Add optional `selected_restaurants: list[SelectedRestaurant] | None` field to `ItineraryRequest`
    - Add optional `origin: str | None` field to `RestaurantRecommendation` (values: "user" or "ai")
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 3.1, 3.2_

- [ ] 3. Checkpoint — Ensure backend model and enrichment changes are correct
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 4. iOS PriceFormatter utility
  - [x] 4.1 Create `PriceFormatter.swift` in `ios/Orbi/Utilities/`
    - Implement `enum PriceFormatter` with static methods: `hotelPrice(min:max:tier:) -> String` and `restaurantPrice(min:max:tier:) -> String`
    - Hotel: return "$XXX / night avg" using average of min/max, or tier fallback ($80/$150/$250)
    - Restaurant: return "$XX–$XX per person" using min/max directly, or tier fallback ($10–20/$20–40/$40–70)
    - Add `restaurantPriceFromTier(_ tier: String) -> String` for itinerary restaurant rows that only have a tier string
    - Default to mid-tier for unrecognized tier strings
    - _Requirements: 4.1, 4.3, 4.4, 4.5, 5.1, 5.3, 5.4, 5.5, 6.1, 6.2_

  - [ ]* 4.2 Write property test: hotel price format is always numeric (Swift)
    - **Property 6: Hotel price format is always numeric**
    - **Validates: Requirements 4.1, 4.5**

  - [ ]* 4.3 Write property test: hotel price uses average of min and max (Swift)
    - **Property 7: Hotel price uses average of min and max**
    - **Validates: Requirements 4.3**

  - [ ]* 4.4 Write property test: restaurant price format is always a numeric range (Swift)
    - **Property 8: Restaurant price format is always a numeric range**
    - **Validates: Requirements 5.1, 5.5, 6.1**

  - [ ]* 4.5 Write property test: restaurant price uses min and max directly (Swift)
    - **Property 9: Restaurant price uses min and max directly**
    - **Validates: Requirements 5.3**

- [ ] 5. Update PlaceCard with numeric pricing and "Estimated" label
  - [x] 5.1 Update `PlaceCard` in `RecommendationsView.swift` to use `PriceFormatter`
    - Replace inline `formattedHotelPrice` / `formattedRestaurantPrice` usage with `PriceFormatter` calls
    - Add "Estimated" label in caption2 / textTertiary adjacent to the price
    - Ensure standalone dollar-sign tier strings are never shown as sole price representation
    - _Requirements: 4.1, 4.2, 4.5, 5.1, 5.2, 5.5_

- [ ] 6. Update itinerary restaurant rows with numeric pricing
  - [x] 6.1 Update `restaurantRow` in `ItineraryView.swift` and `inlineRestaurantRow` in `TripResultView.swift`
    - Replace raw `priceLevel` display with `PriceFormatter.restaurantPriceFromTier(restaurant.priceLevel)`
    - Add "Estimated" label in caption2 / textTertiary adjacent to the price
    - _Requirements: 6.1, 6.2, 6.3_

- [ ] 7. Checkpoint — Ensure pricing changes compile and display correctly
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 8. External source linking (Google Maps)
  - [x] 8.1 Create `ExternalLinkButton.swift` in `ios/Orbi/Views/`
    - Implement a small reusable view that opens `https://www.google.com/maps/search/?api=1&query={encoded_name}+{encoded_city}` in the system browser
    - Render as caption-sized "View" text in accentCyan
    - Hide the link if URL construction fails
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

  - [x] 8.2 Add `ExternalLinkButton` to `PlaceCard` in `RecommendationsView.swift`
    - Add the "View" link to each hotel and restaurant card
    - Pass the place name and city context
    - _Requirements: 7.1, 7.3, 7.4_

  - [x] 8.3 Add `ExternalLinkButton` to itinerary slot and restaurant rows
    - Add the "View" link to activity slots in `ItineraryView.swift` and `TripResultView.swift`
    - Add the "View" link to restaurant rows in both views
    - _Requirements: 7.2, 7.3, 7.4_

  - [ ]* 8.4 Write property test: external link URL format (Swift)
    - **Property 10: External link URL format**
    - **Validates: Requirements 7.3**

- [ ] 9. Rating source attribution
  - [x] 9.1 Update `PlaceCard` rating display in `RecommendationsView.swift`
    - Format rating as "4.5 (Foursquare)" using `ratingSource` field
    - Optionally append "(1,200 reviews)" when `reviewCount` is available
    - Hide the entire rating element when `rating == 0` or `rating` is nil
    - _Requirements: 8.1, 8.2, 8.3_

  - [x] 9.2 Update itinerary restaurant rating display in `ItineraryView.swift` and `TripResultView.swift`
    - Apply the same rating source attribution format for restaurant ratings in day sections
    - Hide rating when value is 0
    - _Requirements: 8.4, 8.3_

  - [ ]* 9.3 Write property test: rating display includes source attribution (Swift)
    - **Property 11: Rating display includes source attribution**
    - **Validates: Requirements 8.1**

  - [ ]* 9.4 Write property test: zero or missing ratings are hidden (Swift)
    - **Property 12: Zero or missing ratings are hidden**
    - **Validates: Requirements 8.3**

- [ ] 10. Checkpoint — Ensure external links and rating attribution work correctly
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 11. Origin labels on itinerary items
  - [x] 11.1 Add `origin` field to iOS models in `TripModels.swift`
    - Add `let origin: String?` to `ItineraryRestaurant` (defaults to nil via Codable)
    - _Requirements: 3.1, 3.2_

  - [x] 11.2 Display origin labels in itinerary views
    - In `ItineraryView.swift` restaurant rows and `TripResultView.swift` inline restaurant rows, add origin label: "Selected by you" for origin == "user", "Suggested" for origin == "ai" or nil
    - Use caption2 font and textTertiary color per DesignTokens
    - Ensure the label does not increase card height or displace existing content
    - _Requirements: 3.1, 3.2, 3.3, 10.1_

  - [ ]* 11.3 Write property test: origin label maps correctly (Swift)
    - **Property 5: Origin label maps correctly**
    - **Validates: Requirements 3.1, 3.2**

- [ ] 12. Restaurant selection and injection
  - [x] 12.1 Create `RestaurantSelector.swift` in `ios/Orbi/Views/`
    - Implement `RestaurantSelector` as a horizontal ScrollView of compact restaurant cards
    - Reuse `RecommendationsViewModel.loadRestaurants()` to fetch data
    - Each card shows name, cuisine, and formatted price range via PriceFormatter
    - Toggle selection on tap; cap at 3 selections
    - _Requirements: 1.1, 1.2, 1.3, 1.5, 10.5_

  - [x] 12.2 Embed `RestaurantSelector` in `DestinationFlowView.swift`
    - Add the selector below the existing vibe pills in the preferences card
    - Pass selected restaurant IDs binding
    - Hide the selector section if no restaurants are available
    - Allow itinerary generation to proceed with 0 selections
    - _Requirements: 1.1, 1.4, 10.5_

  - [x] 12.3 Add `SelectedRestaurantPayload` to `TripModels.swift` and update `TripPreferencesRequest`
    - Add `SelectedRestaurantPayload` struct (name, cuisine, priceLevel, latitude, longitude)
    - Add optional `selectedRestaurants: [SelectedRestaurantPayload]?` to `TripPreferencesRequest`
    - Wire the selected restaurants from the selector into the generate request
    - _Requirements: 2.1, 2.2_

  - [x] 12.4 Implement restaurant injection logic in `backend/services/itinerary.py`
    - After OpenAI generates the base itinerary, if `selected_restaurants` is provided, replace the `restaurant` field on the first N days with user picks
    - Set `origin: "user"` on injected restaurants and `origin: "ai"` on all AI-generated ones
    - Ensure no duplicates — each selected restaurant appears at most once
    - Fill remaining days with AI-generated restaurants
    - Ignore invalid entries gracefully; fall back to full AI generation if all invalid
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 3.1, 3.2_

  - [ ]* 12.5 Write property test: restaurant selection toggle is an involution (Swift)
    - **Property 1: Restaurant selection toggle is an involution**
    - **Validates: Requirements 1.2**

  - [ ]* 12.6 Write property test: restaurant selection count never exceeds maximum (Swift)
    - **Property 2: Restaurant selection count never exceeds maximum**
    - **Validates: Requirements 1.3**

  - [ ]* 12.7 Write property test: selected restaurants are injected exactly once (Python/Hypothesis)
    - **Property 3: Selected restaurants are injected exactly once**
    - **Validates: Requirements 2.1, 2.3**

  - [ ]* 12.8 Write property test: every itinerary day has a restaurant (Python/Hypothesis)
    - **Property 4: Every itinerary day has a restaurant**
    - **Validates: Requirements 2.4**

- [ ] 13. Checkpoint — Ensure restaurant selection and injection work end-to-end
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 14. UI density verification
  - [x] 14.1 Verify all new UI elements use correct DesignTokens
    - Confirm Item_Origin_Label uses caption2 + textTertiary
    - Confirm "Estimated" label uses caption2 + textTertiary
    - Confirm External_Link uses caption + accentCyan
    - Confirm Rating_Display source attribution uses caption2 + textTertiary
    - Confirm Restaurant_Selector is a horizontal scroll within existing layout, no new full-screen sections
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

- [x] 15. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- Unit tests validate specific examples and edge cases
- Backend tasks use Python/FastAPI with Hypothesis for property tests
- iOS tasks use Swift/SwiftUI with swift-testing for property tests
