# Implementation Plan: Share Flow Planner

## Overview

Implementation follows a bug-fixes-first approach for quick wins, then share flow enhancements. iOS uses Swift/SwiftUI, backend uses Python/FastAPI with Supabase.

## Tasks

- [x] 1. Bug fixes — quick wins
  - [x] 1.1 Fix saved itinerary display in SavedTripDetailView
    - In `drobe/ios/Orbi/Views/SavedTripsView.swift`, update `SavedTripDetailView` to decode the `itinerary` JSON (`[String: AnyCodableValue]?`) into an `ItineraryResponse` and render the full day-by-day itinerary view with activity slots, timeline indicators, and restaurant rows
    - Decode `costBreakdown` JSON into `CostBreakdown` and render the cost breakdown section when present
    - Show "No itinerary data available" fallback when itinerary is null
    - Display destination, duration, and vibe in the header
    - Show error message with retry option on load failure
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6_

  - [ ]* 1.2 Write unit tests for SavedTripDetailView decoding
    - Test itinerary JSON decoding into ItineraryResponse
    - Test null itinerary fallback message
    - Test CostBreakdown decoding
    - _Requirements: 10.2, 10.3, 10.4_

  - [x] 1.3 Fix weather display on city selection
    - In `drobe/ios/Orbi/Views/DestinationInsightsView.swift` and the CityCardView that hosts it, verify that non-zero latitude and longitude coordinates are passed to `DestinationInsightsView` when a city is selected
    - Ensure `WeatherViewModel.loadWeather` is called with the selected city's coordinates via the existing `.task` modifier
    - If coordinates are zero or not passed, fix the CityCardView to forward the city's lat/lng correctly
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_

  - [x] 1.4 Clean up day section headers
    - In `drobe/ios/Orbi/Views/TripResultView.swift`, update `InlineDaySectionView.daySectionHeader` to remove the "Optimize" button and standalone "Map" button; keep only: calendar icon, "Day N" text, spacer, "Apple Maps" button, activity count text
    - In `drobe/ios/Orbi/Views/ItineraryView.swift`, apply the same cleanup to `ItineraryView.daySectionHeader`
    - Ensure consistent spacing between "Apple Maps" button and activity count
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6_

  - [x] 1.5 Fix "Why This Plan" reasoning text truncation
    - In `drobe/ios/Orbi/Views/TripResultView.swift`, remove `.lineLimit(3)` from the reasoning text in the `whyThisPlanCard` computed property
    - In `drobe/ios/Orbi/Views/ItineraryView.swift`, remove `.lineLimit(3)` from the reasoning text in the `whyThisPlanCard` computed property
    - Keep the "Optimized for minimal travel time and best experience flow" subtitle below the reasoning text
    - _Requirements: 13.1, 13.2, 13.3, 13.4_

- [x] 2. Checkpoint — Verify bug fixes
  - Ensure all tests pass, ask the user if questions arise.

- [x] 3. Update ShareFormatter with planned-by and notes parameters
  - [x] 3.1 Extend ShareFormatter.formatTrip signature
    - In `drobe/ios/Orbi/Utilities/ShareFormatter.swift`, add optional `plannedBy: String? = nil` and `notes: String? = nil` parameters to `formatTrip`
    - When `plannedBy` is non-empty after trimming, insert `"Planned by {value}"` line below the title
    - When `notes` is non-empty after trimming, insert `"Notes:\n{text}"` section after the title block
    - When either field is nil or empty/whitespace-only, omit the corresponding lines entirely
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_

  - [ ]* 3.2 Write property test for ShareFormatter — Property 1: Formatter output contains all required components
    - **Property 1: Formatter output contains all required components**
    - Generate random `ItineraryResponse` with 1–14 days, 0–5 slots per day, random costs; verify output contains title, all day headers, all activity names, and cost total when cost data exists
    - **Validates: Requirements 5.1**

  - [ ]* 3.3 Write property test for ShareFormatter — Property 2: Planned-by line conditional inclusion
    - **Property 2: Planned-by line conditional inclusion**
    - Generate random itineraries paired with random `plannedBy` strings (nil, empty, whitespace, non-empty); verify presence/absence of "Planned by" line
    - **Validates: Requirements 5.2, 5.3**

  - [ ]* 3.4 Write property test for ShareFormatter — Property 3: Notes section conditional inclusion
    - **Property 3: Notes section conditional inclusion**
    - Generate random itineraries paired with random `notes` strings (nil, empty, whitespace, non-empty); verify presence/absence of "Notes:" section
    - **Validates: Requirements 5.4, 5.5**

- [x] 4. Create ShareSheetView and wire into TripResultView
  - [x] 4.1 Create ShareSheetView
    - Create new SwiftUI view in `drobe/ios/Orbi/Views/ShareSheetView.swift`
    - Accept `itinerary: ItineraryResponse` and `@Binding var plannedBy: String`
    - Display trip title at top, "Planned by (optional)" single-line TextField (max 100 chars), "Add notes (optional)" multi-line TextField (max 500 chars, placeholder text, expands up to 4 lines)
    - "Share" button formats text via `ShareFormatter.formatTrip` with plannedBy and notes, then presents `UIActivityViewController`
    - "Cancel" button dismisses the sheet
    - Use `DesignTokens` colors and `.glassmorphic()` styling
    - Allow sharing without entering any optional fields
    - Do not use "Client", "Planner tools", or "Professional mode" terminology
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4, 3.5, 4.1, 4.2, 4.3, 4.4_

  - [x] 4.2 Wire ShareSheetView into TripResultView
    - In `drobe/ios/Orbi/Views/TripResultView.swift`, add `@State private var plannedByText: String = ""` for session persistence
    - Replace the existing `.sheet(isPresented: $showShareSheet)` that directly presents `ActivityViewControllerWrapper` with a presentation of `ShareSheetView`, passing `itineraryVM.itinerary` and `$plannedByText`
    - Remove the `ActivityViewControllerWrapper` struct if no longer used elsewhere (it will be used inside ShareSheetView instead)
    - _Requirements: 1.1, 2.4, 2.5, 9.1, 9.2, 9.3_

  - [ ]* 4.3 Write unit tests for ShareSheetView
    - Test trip title display, field labels, placeholder text, button presence, cancel dismissal
    - _Requirements: 1.2, 1.3, 1.4, 2.1, 3.1, 3.2_

- [x] 5. Checkpoint — Verify share flow works end-to-end on iOS
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Backend shared trip data extension
  - [x] 6.1 Add database migration for planned_by and notes columns
    - Create `drobe/backend/migrations/005_share_planner_fields.sql` adding nullable `planned_by` (text) and `notes` (text) columns to the `shared_trips` table
    - _Requirements: 8.1, 8.2_

  - [x] 6.2 Update backend share models
    - In `drobe/backend/models/share.py`, add `planned_by: str | None = None` and `notes: str | None = None` to `SharedTripResponse`
    - Create `ShareCreateRequest` model with `planned_by: str | None = Field(None, max_length=100)` and `notes: str | None = Field(None, max_length=500)`
    - _Requirements: 8.1, 8.2, 8.4_

  - [x] 6.3 Update share service and route
    - In `drobe/backend/services/share.py`, update `create_share_link` to accept optional `planned_by` and `notes` params; store them in the `shared_trips` row; normalize empty/whitespace strings to `null`
    - Update `get_shared_trip` to return `planned_by` and `notes` from the `shared_trips` row
    - In `drobe/backend/routes/share.py`, update `POST /trips/{trip_id}/share` to accept `ShareCreateRequest` body and pass fields to `create_share_link`
    - _Requirements: 8.3, 8.4, 8.5_

  - [ ]* 6.4 Write property test for backend null normalization — Property 4
    - **Property 4: Backend null normalization for empty planner fields**
    - Using `hypothesis`, generate random empty/whitespace and non-empty strings for `planned_by` and `notes`; verify stored values are null or original
    - **Validates: Requirements 8.4**

  - [ ]* 6.5 Write integration test for share flow round-trip
    - Create share link with `planned_by` and `notes` via POST, resolve via GET, verify fields returned correctly
    - _Requirements: 8.3, 8.5_

- [x] 7. Update SharedTripView for planned-by and notes display
  - [x] 7.1 Update iOS SharedTripResponse model
    - In `drobe/ios/Orbi/Models/TripModels.swift`, add `let plannedBy: String?` and `let notes: String?` to `SharedTripResponse`
    - _Requirements: 8.1, 8.2_

  - [x] 7.2 Update SharedTripView to display planned-by and notes
    - In `drobe/ios/Orbi/Views/ShareTripView.swift`, update `sharedTripContent` to conditionally display "Planned by [value]" below the destination title in `DesignTokens.textSecondary` style when `plannedBy` is non-empty
    - Conditionally display a "Notes" section with heading and full text when `notes` is non-empty
    - No visual gaps or empty placeholders when fields are absent
    - _Requirements: 6.1, 6.2, 6.3, 7.1, 7.2, 7.3, 7.4_

  - [ ]* 7.3 Write unit tests for SharedTripView conditional rendering
    - Test "Planned by" display with and without data
    - Test "Notes" section display with and without data
    - _Requirements: 6.1, 6.3, 7.1, 7.3_

- [x] 8. Wire ShareSheetView to backend share creation
  - [x] 8.1 Pass planned-by and notes to share link creation
    - Update the share link creation flow so that when `ShareSheetView` triggers a share via the backend (if applicable), the `planned_by` and `notes` values are included in the `POST /trips/{trip_id}/share` request body
    - Update `ShareTripViewModel` or the relevant API call to accept and forward these fields
    - _Requirements: 8.3_

- [x] 9. Final checkpoint — Verify all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- Bug fixes (tasks 1.1–1.5) are prioritized first as quick wins before share flow work
