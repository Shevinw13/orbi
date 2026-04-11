# Implementation Plan: Feature Enhancements

## Overview

Implements all 19 requirements across bug fixes, share formatting, Smart Explore, Interactive Itinerary, Route Intelligence, UX improvements, and backend endpoints. Tasks are ordered by priority: quick-win bug fixes first, then high-impact UX, then feature builds, then backend support.

The iOS client uses Swift/SwiftUI with MapKit. The backend uses Python/FastAPI with Pydantic models. All new UI follows the existing dark gradient + glassmorphism design language via `DesignTokens`.

## Tasks

- [x] 1. Bug Fixes — Quick Wins
  - [x] 1.1 Fix restaurant selection state in RecommendationsView
    - In `RecommendationsView.swift`, add a `@Published var selectedRestaurants: Set<String>` to `RecommendationsViewModel`
    - Add `toggleRestaurant(_ restaurant: PlaceRecommendation)` method that adds/removes from `selectedRestaurants`
    - Update the restaurant `ForEach` in `restaurantsSection` to pass `isSelected: viewModel.selectedRestaurants.contains(restaurant.placeId)` and `onTap: { viewModel.toggleRestaurant(restaurant) }` to `PlaceCard`
    - Ensure selected restaurants show accent border and checkmark (already handled by `PlaceCard` `isSelected` prop)
    - _Requirements: 11.1, 11.2, 11.3, 11.4_

  - [ ]* 1.2 Write property test for restaurant selection toggle
    - **Property 16: Restaurant selection toggle**
    - **Validates: Requirements 11.2, 11.4**

  - [x] 1.3 Fix Trips screen Close button
    - In `SavedTripsView.swift`, verify the Close button uses `@Environment(\.dismiss)` and `.cancellationAction` placement — currently correct, confirm it works when presented as a sheet
    - In `ContentView.swift` `SavedTripsTab`, ensure `SavedTripsView` is presented via `.sheet` or `NavigationStack` so `dismiss()` functions correctly
    - _Requirements: 12.1, 12.2, 12.3_

  - [x] 1.4 Fix Profile page user name display and navigation
    - In `AuthService.swift`, add `@Published var displayName: String?` property
    - In `AuthService.authenticate(path:body:)`, parse and store the display name from `AuthResponse` (add `name` field to `AuthResponse` in `AuthModels.swift`)
    - In `ContentView.swift` `ProfileTab`, replace hardcoded `"Traveler"` with `authService.displayName ?? authService.userId ?? "Traveler"`
    - Add NavigationLink for Settings, Saved Trips, and Preferences sections in `ProfileTab`
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5, 13.6_

  - [ ]* 1.5 Write property test for auth display name storage
    - **Property 17: Auth stores display name from response**
    - **Validates: Requirements 13.6**

- [x] 2. Checkpoint — Verify bug fixes
  - Ensure all tests pass, ask the user if questions arise.

- [x] 3. Human-Readable Share Formatter
  - [x] 3.1 Implement ShareFormatter utility
    - Create `ShareFormatter.swift` in `Orbi/Utilities/`
    - Implement `static func formatTrip(_ itinerary: ItineraryResponse) -> String` that produces:
      - Title line: `"[numDays]-Day [destination] [vibe] Trip"`
      - Day-by-day breakdown with `"Day N:"` headers
      - Activity highlights per day (activity name, time slot)
      - Restaurant name for days that have one
    - Output must be plain text suitable for iMessage, Email, Notes
    - _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5_

  - [x] 3.2 Wire ShareFormatter into share flow
    - In `TripResultView.swift`, replace the existing `ShareTripButton` with a new share action that calls `ShareFormatter.formatTrip()` and presents `UIActivityViewController` via a SwiftUI wrapper
    - The share button should work immediately without requiring a saved trip ID
    - _Requirements: 14.5, 14.6_

  - [ ]* 3.3 Write property test for share formatter output
    - **Property 18: Share formatter produces correct structured plain text**
    - **Validates: Requirements 14.2, 14.3, 14.4**

- [-] 4. Smart Explore — GPS, Filters, Overlays, Clustering
  - [x] 4.1 Create LocationManager ObservableObject
    - Create `LocationManager.swift` in `Orbi/Services/`
    - Implement `CLLocationManagerDelegate` wrapper with `@Published var currentLocation: CLLocationCoordinate2D?` and `@Published var authorizationStatus: CLAuthorizationStatus`
    - Implement `requestLocation()`, `persistLastKnown()`, `loadLastKnown()` using UserDefaults
    - Fallback chain: GPS → UserDefaults → New York default (40.7128, -74.0060)
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

  - [ ]* 4.2 Write property test for location persistence round-trip
    - **Property 1: Location persistence round-trip**
    - **Validates: Requirements 1.5, 19.3**

  - [x] 4.3 Add category filter pills to GlobeView
    - Create `ExploreFilterViewModel` ObservableObject with `@Published var selectedCategory: ExploreCategory?` and `filteredCities`
    - Add `ExploreCategory` enum (Foodie, Adventure, Relaxation, Nightlife) to `DestinationModels.swift`
    - Add horizontal `FilterPill` row above the map in `GlobeView.swift`
    - Implement toggle behavior: tap to select (accent gradient highlight), tap again to deselect
    - Filter visible city markers based on selected category
    - _Requirements: 4.1, 4.2, 4.4_

  - [ ]* 4.4 Write property tests for category filter
    - **Property 2: Category filter returns only matching cities (client)**
    - **Property 4: Filter toggle round-trip restores original state**
    - **Validates: Requirements 4.2, 4.4**

  - [x] 4.5 Add category query parameter to backend popular-cities endpoint
    - In `backend/services/search.py`, add optional `category` tag to each city in `POPULAR_CITIES` list
    - In `backend/routes/search.py`, accept optional `category` query param on `GET /search/popular-cities`
    - Filter returned cities by category tag when param is present
    - _Requirements: 4.3_

  - [ ]* 4.6 Write property test for backend category filter
    - **Property 3: Category filter returns only matching cities (backend)**
    - **Validates: Requirements 4.3**

  - [x] 4.7 Implement explore overlays (backend endpoint + iOS overlay cards)
    - Create `backend/services/explore.py` with `get_overlays(latitude, longitude)` returning up to 4 overlay categories
    - Create `backend/models/explore.py` with `ExploreOverlay`, `OverlayDestination`, `ExploreOverlaysResponse` Pydantic models
    - Create `backend/routes/explore.py` with `GET /explore/overlays` endpoint, register in `main.py`
    - Cache overlay responses for 6 hours
    - Create `ExploreOverlayViewModel` on iOS with `loadOverlays(latitude:longitude:)` async method
    - Add `ExploreOverlay` and `OverlayDestination` Codable models to `DestinationModels.swift`
    - Render up to 4 glassmorphic `OverlayCard` views on the explore map
    - Hide overlays gracefully if backend is unreachable
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

  - [ ] 4.8 Implement map marker clustering with MKMapView
    - Create a `ClusterMapView` UIViewRepresentable using `MKMapView` with `MKClusterAnnotation` support
    - Replace the SwiftUI `Map` in `GlobeView` with `ClusterMapView` for the explore tab
    - Configure clustering threshold so markers group at low zoom and expand on zoom-in
    - Show count badge on cluster annotations, hide individual city labels at low zoom
    - Tap on cluster zooms into the cluster region
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 19.4_

  - [x] 4.9 Wire LocationManager into GlobeView
    - Inject `LocationManager` into `ExploreTab` and pass location to `GlobeView`
    - Center map on user's GPS location on first load (or fallback)
    - Pass user location to overlay and filter view models
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 5. Checkpoint — Verify Smart Explore features
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Interactive Itinerary — Optimize Day, Timeline Bar, Drag-and-Drop Refinement
  - [x] 6.1 Implement Optimize Day with nearest-neighbor algorithm
    - Add `optimizeDay(_ dayNumber: Int)` to `ItineraryViewModel` using nearest-neighbor on haversine distance
    - Add "Optimize Day" button in each day section header (in both `ItineraryView` and `InlineDaySectionView`)
    - Disable button with reduced opacity when day has fewer than 3 activities
    - Animate position changes after optimization
    - Recalculate travel times between consecutive activities after reorder
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

  - [ ]* 6.2 Write property tests for Optimize Day
    - **Property 9: Nearest-neighbor optimization produces valid permutation with non-increasing total distance**
    - **Property 10: Optimize Day button disabled for fewer than 3 activities**
    - **Validates: Requirements 7.2, 7.5**

  - [x] 6.3 Implement TimelineBarView
    - Create `TimelineBarView.swift` in `Orbi/Views/`
    - Display three segments: Morning (cyan), Afternoon (blue), Evening (purple)
    - Fill segments that have activities, dim segments without
    - Tap a segment to scroll to the first activity in that time slot
    - Add `TimelineBarView` at the top of each day section in `ItineraryView` and `InlineDaySectionView`
    - _Requirements: 8.1, 8.2, 8.3, 8.4_

  - [ ]* 6.4 Write property test for timeline segment fill
    - **Property 11: Timeline segment fill matches activity presence**
    - **Validates: Requirements 8.2, 8.3**

  - [x] 6.5 Refine drag-and-drop reordering
    - Enhance the existing drag-and-drop in `ItineraryView` with a visual lift effect on long-press (scale + shadow)
    - Add a drop indicator line showing the target position during drag
    - Ensure cross-day drop (onto day header) works reliably with the existing `moveSlotToDay` logic
    - Verify cost breakdown recalculates after any reorder
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

  - [ ]* 6.6 Write property tests for drag-and-drop reorder
    - **Property 5: Intra-day reorder preserves all slots**
    - **Property 6: Cross-day move transfers slot correctly**
    - **Validates: Requirements 5.3, 5.4**

  - [ ]* 6.7 Write property test for replace activity preserves slot index
    - **Property 8: Replace activity preserves slot index**
    - **Validates: Requirements 6.3**

- [x] 7. Checkpoint — Verify Interactive Itinerary features
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Route Intelligence — Full-Day Optimization, Ride-Hail Costs
  - [x] 8.1 Implement full-day route optimization in MapRouteView
    - Modify `MapRouteViewModel.calculateRoutes()` to calculate routes as a single optimized sequence
    - Add `walkingTime` and `drivingTime` computed properties summing segment times by transport type
    - Update Route Summary Card to show total travel time, walking vs driving breakdown
    - When a walking segment exceeds 30 minutes, automatically calculate and display driving alternative
    - _Requirements: 9.1, 9.2, 9.3, 9.4_

  - [ ]* 8.2 Write property tests for route intelligence
    - **Property 12: Route segment time aggregation is consistent**
    - **Property 13: Walking segments exceeding 30 minutes trigger driving alternative**
    - **Validates: Requirements 9.2, 9.3, 9.4**

  - [x] 8.3 Implement ride-hail cost estimation
    - Add a `RideHailEstimator` struct with city rate table and cost formula: `baseFare + distanceKm × perKmRate` with 0.8x–1.5x range
    - Display estimated ride-hail cost range on route segments exceeding 15 minutes walking
    - Display public transit option label where MapKit transit data is available
    - Add detail card on segment tap showing walking time, driving time, ride-hail cost, transit option
    - _Requirements: 10.1, 10.2, 10.3, 10.4_

  - [ ]* 8.4 Write property tests for ride-hail estimation
    - **Property 14: Ride-hail cost displayed for segments exceeding 15 minutes walking**
    - **Property 15: Ride-hail cost formula correctness**
    - **Validates: Requirements 10.1, 10.2**

- [x] 9. Checkpoint — Verify Route Intelligence features
  - Ensure all tests pass, ask the user if questions arise.

- [x] 10. UX Improvements — Ratings, Pricing, Weather
  - [x] 10.1 Add ratings source and review count to PlaceCard
    - Add optional `ratingSource: String?` and `reviewCount: Int?` fields to `PlaceRecommendation` in `TripModels.swift`
    - Update `PlaceCard` in `RecommendationsView.swift` to display source attribution label and review count subtext below the star rating
    - Omit review count subtext when `reviewCount` is nil
    - _Requirements: 15.1, 15.2, 15.4_

  - [x] 10.2 Add price range indicators to PlaceCard
    - Add optional `priceRangeMin: Double?` and `priceRangeMax: Double?` fields to `PlaceRecommendation` in `TripModels.swift`
    - Update `PlaceCard` to display price range (e.g., "$150–$300/night" for hotels, "$15–$60" for restaurants)
    - Fall back to price level symbol when range data is nil
    - _Requirements: 16.1, 16.2, 16.4_

  - [ ]* 10.3 Write property test for backward-compatible deserialization
    - **Property 20: Backward-compatible deserialization with optional fields**
    - **Validates: Requirements 19.5**

  - [x] 10.4 Implement Destination Insights section (weather + best time to visit)
    - Create `WeatherViewModel` ObservableObject in `Orbi/Views/` or `Orbi/Services/` with `loadWeather(latitude:longitude:)` async method
    - Add `DestinationWeather` Codable model to `DestinationModels.swift`
    - Create `DestinationInsightsView` showing best time to visit and current weather (high/low temps, condition)
    - Add `DestinationInsightsView` to `CityCardView` and `PreferencesOverlay` in `ContentView.swift`
    - Display "Weather data unavailable" placeholder when service is unreachable
    - _Requirements: 17.1, 17.2, 17.3, 17.5, 17.6_

  - [ ]* 10.5 Write property test for user preferences persistence
    - **Property 19: User preferences persistence round-trip**
    - **Validates: Requirements 19.3**

- [x] 11. Backend Endpoints — Weather, Overlays Model Extensions, Places Fields
  - [x] 11.1 Create weather backend endpoint
    - Create `backend/services/weather.py` with `get_weather(latitude, longitude)` proxying Open-Meteo API
    - Create `backend/models/weather.py` with `WeatherResponse` Pydantic model (temp_high, temp_low, condition, best_time_to_visit)
    - Create `backend/routes/weather.py` with `GET /destinations/weather` endpoint accepting latitude/longitude query params
    - Register weather router in `backend/main.py`
    - Cache weather responses with 1-hour TTL
    - _Requirements: 17.3, 17.4_

  - [x] 11.2 Add optional fields to backend PlaceResult model
    - Add `rating_source: str | None = None`, `review_count: int | None = None`, `price_range_min: float | None = None`, `price_range_max: float | None = None` to `PlaceResult` in `backend/models/places.py`
    - Ensure backward compatibility — all new fields optional with defaults
    - Update `_parse_foursquare_result` and `_fetch_openai_places` in `backend/services/places.py` to populate new fields when data is available
    - _Requirements: 15.3, 16.3, 19.5_

  - [ ]* 11.3 Write backend property test for replace prompt exclusion
    - **Property 7: Replace activity prompt excludes all existing activities**
    - **Validates: Requirements 6.2**

- [x] 12. Design Consistency and Architecture Compliance
  - [x] 12.1 Audit all new views for design token compliance
    - Verify all new UI components use `DesignTokens` colors, spacing, corner radii
    - Verify all card/overlay backgrounds use `.glassmorphic()` modifier
    - Verify primary action buttons use `DesignTokens.accentGradient`
    - Verify dark gradient backgrounds use `DesignTokens.backgroundPrimary` / `backgroundSecondary`
    - Verify all new views have dedicated ObservableObject view models
    - _Requirements: 18.1, 18.2, 18.3, 18.4, 19.1, 19.2_

- [x] 13. Final Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation after each feature group
- Property tests validate universal correctness properties from the design document
- Bug fixes (tasks 1.x) are prioritized first as quick wins
- The iOS client uses Swift/SwiftUI; the backend uses Python/FastAPI
