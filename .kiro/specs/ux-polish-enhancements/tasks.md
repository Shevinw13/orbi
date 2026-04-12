# Implementation Plan: UX Polish Enhancements

## Overview

Incremental implementation of 22 UX polish requirements across the Orbi iOS app (Swift/SwiftUI) and Python/FastAPI backend. Tasks follow the priority order: Interest Builder → City Selection → Profile → Pricing → Itinerary → Bookmark → Replace Item → Trips Empty State → Export → Activity Tags → Loading → Haptics → Supporting UX → Globe Visuals → App Icon. Each task builds on previous work and wires into existing views and services.

## Tasks

- [x] 1. Interest Builder Updates (Req 1, 2)
  - [x] 1.1 Remove ExploreCategory filter pills from GlobeView and add FlowLayout for vibe chips
    - Remove the `filterPillsRow` from `GlobeView` that renders `ExploreCategory` filter pills
    - Create a `FlowLayout` helper (SwiftUI `Layout` protocol) in a new `Utilities/FlowLayout.swift` with 8pt spacing
    - Replace the `HStack` of vibe pills in `PreferencesOverlay` (in `ContentView.swift`) with `FlowLayout`, applying 16pt horizontal and 9pt vertical padding per chip
    - Ensure vibe chips wrap to multiple lines when horizontal space is insufficient
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

  - [x] 1.2 Add Family Friendly toggle to PreferencesOverlay and backend prompt
    - Add `familyFriendly: Bool = false` to `TripPreferencesViewModel` in `DestinationFlowView.swift`
    - Add a `Toggle` below the vibe section in `PreferencesOverlay` bound to `viewModel.familyFriendly`
    - Add `familyFriendly: Bool` to `TripPreferencesRequest` in `TripModels.swift`
    - Add `family_friendly: bool = False` to `ItineraryRequest` in `backend/models/itinerary.py`
    - Modify `_build_prompt()` in `backend/services/itinerary.py` to append family-friendly constraint text when `family_friendly=True`
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [ ]* 1.3 Write property test for family-friendly prompt inclusion
    - **Property 1: Family-friendly prompt inclusion**
    - Generate random `ItineraryRequest` with `family_friendly` toggled; verify prompt contains/excludes constraint text
    - **Validates: Requirements 2.3**

- [x] 2. City Selection Weather Fix (Req 3)
  - [x] 2.1 Hide weather section on API error instead of showing error text
    - In `DestinationInsightsView.swift`, replace the `else if weatherVM.errorMessage != nil` branch with `EmptyView()` so the entire weather section is hidden on failure
    - Remove the "Weather data unavailable" text block
    - _Requirements: 3.1, 3.2, 3.3_

- [x] 3. Profile Page Cleanup (Req 4)
  - [x] 3.1 Simplify ProfileTab navigation and display name logic
    - In `ProfileTab` (in `ContentView.swift`), remove the "Orbi Explorer" subtitle text
    - Update display name to use `authService.displayName ?? authService.userId ?? "User"` — never show "Traveler"
    - Remove the Settings, Preferences, Notifications, and Appearance `NavigationLink`s
    - Keep only: Saved Trips (linking to `SavedTripsView`), My Trips (switches to Trips tab), and Sign Out
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [ ]* 3.2 Write property test for profile display name fallback chain
    - **Property 2: Profile display name fallback chain**
    - Generate random `(displayName?, userId?)` pairs; verify display text follows fallback chain and never equals "Traveler" when data is available
    - **Validates: Requirements 4.1, 4.2**

- [x] 4. Pricing Logic Improvements (Req 5, 6)
  - [x] 4.1 Implement hotel and restaurant pricing format helpers
    - Add helper functions (or computed properties) for hotel pricing: format as `"$XXX / night avg"` using average of `priceRangeMin`/`priceRangeMax` when available, else tier fallback ($80/$150/$250)
    - Add helper functions for restaurant pricing: format as `"$XX–$XX per person"` using `priceRangeMin`/`priceRangeMax` when available, else tier fallback ($10–$20/$20–$40/$40–$80)
    - Update `PlaceCard` in `RecommendationsView.swift` to use the new formatters instead of raw `priceLevel` strings
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 6.1, 6.2, 6.3, 6.4_

  - [ ]* 4.2 Write property test for hotel pricing format
    - **Property 3: Hotel pricing format**
    - Generate random hotel `PlaceRecommendation` data with optional `priceRangeMin`/`priceRangeMax`; verify formatted string matches `"$XXX / night avg"` pattern
    - **Validates: Requirements 5.1, 5.2, 5.3, 5.4**

  - [ ]* 4.3 Write property test for restaurant pricing format
    - **Property 4: Restaurant pricing format**
    - Generate random restaurant `PlaceRecommendation` data; verify formatted string matches `"$XX–$XX per person"` pattern
    - **Validates: Requirements 6.1, 6.2, 6.3, 6.4**

- [x] 5. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Itinerary Enhancements (Req 7, 8, 9)
  - [x] 6.1 Add auto-optimization on itinerary load and reasoning section
    - In `ItineraryViewModel`, call `optimizeDay()` for all days with ≥3 slots on init or first appearance
    - Add `reasoningText: String?` to `ItineraryResponse` in `TripModels.swift`
    - Add `reasoning_text: str | None = None` to `ItineraryResponse` in `backend/models/itinerary.py`
    - Update `_build_prompt()` in `backend/services/itinerary.py` to request a `"reasoning"` field in the JSON schema
    - Update `_parse_itinerary_response()` to extract `reasoning_text`
    - Display a "Why This Plan" card at the top of the itinerary tab with reasoning text, plus microcopy "Optimized for minimal travel time and best experience flow"
    - _Requirements: 7.1, 7.2, 9.1, 9.2_

  - [ ]* 6.2 Write property test for nearest-neighbor optimization preserving activities
    - **Property 5: Nearest-neighbor optimization preserves activities**
    - Generate random lists of ≥3 `ItinerarySlot` items with coordinates; verify `optimizeDay()` output is a permutation with same first element
    - **Validates: Requirements 7.1**

  - [x] 6.3 Add Apple Maps deep link button to day sections
    - Add an "Open in Apple Maps" button in `InlineDaySectionView.daySectionHeader` and `ItineraryView.daySectionHeader`
    - On tap, construct a URL using `MKMapItem.openMaps(with:launchOptions:)` with waypoints from the day's slot coordinates
    - Disable the button when the day has no activities
    - _Requirements: 8.1, 8.2_

  - [ ]* 6.4 Write property test for Apple Maps URL construction
    - **Property 6: Apple Maps URL construction**
    - Generate random lists of coordinates; verify Apple Maps URL is valid and contains all coordinate pairs
    - **Validates: Requirements 8.2**

- [x] 7. Bookmark UX Upgrade (Req 10)
  - [x] 7.1 Replace Save button with bookmark toggle icon
    - In `TripResultView`, replace the `saveButton` with a `bookmark` / `bookmark.fill` SF Symbol icon in the toolbar
    - On tap, toggle save state: save trip on first tap (fill icon), unsave on second tap (unfill icon)
    - Remove the `showSaveSuccess` alert dialog
    - On load, check if trip is already saved (match destination + numDays + vibe) and show filled icon
    - Persist `savedTripId` so bookmark state survives app restarts
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

- [x] 8. Replace Item Logic Validation (Req 11)
  - [x] 8.1 Add adjacent activity coordinates to replace-item request
    - Add `adjacentActivityCoords: [[String: Double]]?` to `ReplaceActivityRequest` in `TripModels.swift`
    - Add `adjacent_activity_coords: list[dict] | None = None` to `ReplaceActivityRequest` in `backend/models/itinerary.py`
    - In `ItineraryViewModel.replaceActivity()`, populate `adjacentActivityCoords` with lat/lng of the previous and next activities in the same day
    - Update `_build_replace_prompt()` in `backend/services/itinerary.py` to include adjacent coordinates in the prompt with a 60-minute travel constraint
    - _Requirements: 11.1, 11.2, 11.3, 11.4_

  - [ ]* 8.2 Write property test for replace prompt including adjacent coordinates
    - **Property 7: Replace prompt includes adjacent coordinates**
    - Generate random `ReplaceActivityRequest` with non-empty `adjacent_activity_coords`; verify prompt contains those coordinate values
    - **Validates: Requirements 11.4**

- [x] 9. Trips Empty State (Req 12)
  - [x] 9.1 Implement empty state with CTA in SavedTripsView
    - In `SavedTripsView`, replace the current empty state with "No trips yet" heading, a "Plan your first trip" button, and suggestion text "Try a weekend in Atlanta"
    - The "Plan your first trip" button should navigate to the Explore tab (via callback or environment binding to `selectedTab` in `ContentView`)
    - _Requirements: 12.1, 12.2, 12.3, 12.4_

- [x] 10. Export / Share Upgrade (Req 13)
  - [x] 10.1 Upgrade ShareFormatter to include costs and restaurant details
    - In `ShareFormatter.formatTrip()` (both in `ShareFormatter.swift` and `TripResultView.swift`), add estimated cost per activity in parentheses
    - Add restaurant recommendations with cuisine type per day
    - Add a total estimated cost line at the bottom
    - Ensure output is clean plain text with no JSON or markdown
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5_

  - [ ]* 10.2 Write property test for export formatter content completeness
    - **Property 8: Export formatter content completeness**
    - Generate random `ItineraryResponse` data; verify export string contains title, all activity names, all restaurant names, and cost total
    - **Validates: Requirements 13.1, 13.2, 13.3, 13.5**

  - [ ]* 10.3 Write property test for export formatter clean plain text
    - **Property 9: Export formatter produces clean plain text**
    - Generate random `ItineraryResponse` data; verify export string contains no JSON structural characters
    - **Validates: Requirements 13.4**

- [x] 11. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 12. Activity Tags (Req 14)
  - [x] 12.1 Add activity tag field to models and backend prompt
    - Add `tag: String?` to `ItinerarySlot` in `TripModels.swift`
    - Add `tag: str | None = None` to `ActivitySlot` in `backend/models/itinerary.py`
    - Update `_build_prompt()` in `backend/services/itinerary.py` to request a `"tag"` field per slot with values like "Popular", "Highly rated", "Hidden gem", "Family-friendly"
    - Display the tag as a small capsule badge below the activity name in slot rows in `ItineraryView` and `InlineDaySectionView`
    - _Requirements: 14.1, 14.2, 14.3, 14.4_

- [x] 13. Loading Experience (Req 15)
  - [x] 13.1 Implement staged loading messages in GeneratingOverlay
    - In `GeneratingOverlay` (in `ContentView.swift`), replace the static "Generating your itinerary…" text with staged messages: "Finding top spots…" → "Optimizing your route…" → "Finalizing your itinerary…"
    - Cycle messages at ~3-second intervals using `Task.sleep`
    - Ensure 16pt horizontal padding on all text content
    - _Requirements: 15.1, 15.2, 15.3, 15.4_

- [ ] 14. Haptics Integration (Req 16)
  - [x] 14.1 Add haptic feedback to key interaction points
    - Add `UINotificationFeedbackGenerator().notificationOccurred(.success)` when itinerary generation completes (in `TripPreferencesViewModel.submit()` success path)
    - Add `UIImpactFeedbackGenerator(style: .light).impactOccurred()` on bookmark tap (in the new bookmark toggle logic in `TripResultView`)
    - Add `UIImpactFeedbackGenerator(style: .light).impactOccurred()` on successful activity replacement (in `ItineraryViewModel.replaceActivity()` success path)
    - Guard against double-firing with a boolean flag
    - _Requirements: 16.1, 16.2, 16.3, 16.4_

- [ ] 15. Supporting UX Enhancements (Req 17)
  - [x] 15.1 Update cost estimation labels in CostBreakdownView
    - In `CostBreakdownView.swift`, change the `totalSection` label from "Estimated Total" to "Estimated total cost" above the total figure
    - Add "Based on average prices" disclaimer text below the total section
    - Ensure "Estimated Total" label is used consistently in the total display
    - _Requirements: 17.1, 17.2, 17.3_

- [x] 16. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 17. Globe Visual Enhancements (Req 18, 19, 20, 21, 22)
  - [x] 17.1 Add globe glow layer and landmass contrast overlay
    - Add a `RadialGradient` view behind `ClusterMapView` in `GlobeView`'s ZStack using diffused blue, purple, teal tones with max opacity 0.35
    - Add faint static `Circle` overlays at city annotation positions with opacity ≤ 0.2 in `CityAnnotationView`
    - Add a subtle gradient overlay at the map edges for landmass contrast
    - Ensure glow is consistent with `DesignTokens` dark theme
    - _Requirements: 18.1, 18.2, 18.3, 18.4, 18.5_

  - [x] 17.2 Implement subtle globe rotation with touch pause/resume
    - In `ClusterMapView.Coordinator`, add a `Timer` that increments `camera.heading` by ~2°/sec
    - On `touchesBegan` (via gesture recognizer), pause the timer
    - Resume 3 seconds after `touchesEnded` using a debounced restart
    - Invalidate timer in `Coordinator.deinit` to prevent leaks
    - Ensure rotation does not interfere with annotation taps, zoom controls, or search
    - _Requirements: 19.1, 19.2, 19.3, 19.4_

  - [x] 17.3 Increase search bar visual emphasis and add guidance text
    - Reduce `ClusterMapView` height by ~12% (add top padding or constrain frame) in `GlobeView`
    - Increase `SearchBarView` background opacity from 0.08 to ~0.15
    - Add shadow with blur 8pt, opacity 0.25 to `SearchBarView`
    - Add `Text("Where do you want to go?")` above `SearchBarView` in `ExploreTab` with `DesignTokens.textSecondary`, `.subheadline` weight, `lineLimit(1)`
    - Fade guidance text out on search field focus, fade in when focus lost and query empty, using `@FocusState` with 0.2s opacity animation
    - _Requirements: 20.1, 20.2, 20.3, 20.4, 21.1, 21.2, 21.3, 21.4, 21.5_

  - [x] 17.4 Add globe tap feedback ripple animation
    - Add a tap gesture recognizer to `ClusterMapView` Coordinator that detects taps not on annotations
    - On tap, overlay a `Circle` at the tap point that animates from 0→80pt diameter, 0.3→0 opacity over 0.4s using `DesignTokens.accentCyan`
    - Use `hitTest` in the gesture recognizer to exclude annotation views, cluster views, and UI controls
    - _Requirements: 22.1, 22.2, 22.3, 22.4_

- [x] 18. App Icon
  - [x] 18.1 Generate and configure the Orbi app icon
    - Create a Swift script or use `ImageRenderer` (iOS 16+) to render the `OrbiLogoDark` view from `AppIconView.swift` at 1024×1024 into a PNG file
    - Alternatively, create a programmatic 1024×1024 PNG matching the Orbi globe/travel branding (dark background, blue-green gradient globe with white orbital ring)
    - Save the PNG as `drobe/ios/Orbi/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
    - Update `Contents.json` in `AppIcon.appiconset` to reference the new `AppIcon.png` file with the `"filename"` key
    - _Additional polish item — not tied to a specific requirement_

- [x] 19. Final Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- The tech stack is Swift/SwiftUI (iOS) and Python/FastAPI (backend) — no language selection needed
- The app icon task (18) is an additional polish item not tied to the 22 requirements
