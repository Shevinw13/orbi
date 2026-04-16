# Implementation Plan: Explore Shared Itineraries

## Overview

This plan implements the Explore Shared Itineraries feature across backend (Python/FastAPI + Supabase PostgreSQL) and iOS (Swift/SwiftUI). Tasks follow dependency order: database migration → backend models → backend service → backend routes → iOS models → iOS tab bar restructuring → iOS views → iOS publish flow → attribution display.

## Tasks

- [ ] 1. Database migration for shared itineraries
  - [-] 1.1 Create migration `006_shared_itineraries.sql`
    - Create `shared_itineraries` table with columns: id (UUID PK), user_id (FK to users, CASCADE), source_trip_id (FK to trips, SET NULL), title (text, max 100), description (text, max 500), destination (text), destination_lat_lng (text), budget_level (integer 1-5), cover_photo_url (text), tags (text[]), num_days (integer ≥1), itinerary (JSONB), save_count (integer default 0), is_featured (boolean default false), created_at (timestamptz), updated_at (timestamptz)
    - Add CHECK constraints for title length, description length, budget_level range, num_days minimum
    - Create indexes on destination, budget_level, save_count DESC, is_featured (partial), user_id
    - Add updated_at trigger reusing existing `update_updated_at_column()` function
    - Add `copied_from_shared_id` (UUID, FK to shared_itineraries, SET NULL) and `original_creator_username` (text) columns to the existing `trips` table
    - Add RLS policies: public SELECT on shared_itineraries, INSERT restricted to owner via user_id match
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 6.2, 6.3_

- [ ] 2. Backend Pydantic models for shared itineraries
  - [~] 2.1 Create `backend/models/shared_itinerary.py`
    - Define `SharedItineraryListItem` model (id, title, destination, num_days, budget_level, cover_photo_url, creator_username, save_count, tags)
    - Define `SharedItineraryDetail` model (full detail including itinerary JSONB, description, destination_lat_lng, created_at)
    - Define `SharedItineraryPublishRequest` model with Field validators (cover_photo_url required, title max 100, description max 500, budget_level 1-5, destination required, tags optional)
    - Define `SharedItineraryListResponse` (paginated wrapper with items list and total count)
    - Define `SharedItineraryCopyResponse` (trip_id string)
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.6, 8.7_

  - [ ]* 2.2 Write unit tests for publish request validation
    - Test that invalid title lengths, empty descriptions, out-of-range budget levels are rejected by Pydantic
    - _Requirements: 8.6, 8.7, 11.2, 11.3, 11.4_

- [ ] 3. Checkpoint - Ensure models are correct
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 4. Backend service for shared itineraries
  - [~] 4.1 Create `backend/services/shared_itineraries.py`
    - Implement `list_shared_itineraries(section, destination, budget_level, min_days, max_days, page, page_size)` — query shared_itineraries with filters, join users table for creator_username, support section-based queries (featured: is_featured=true, trending: order by save_count DESC), destination partial match (ilike), budget_level filter, duration range filter, pagination
    - Implement `get_shared_itinerary(id)` — fetch single record with username join
    - Implement `copy_shared_itinerary(shared_id, user_id)` — read shared itinerary, insert new trips row with itinerary JSONB + destination + num_days + copied_from_shared_id + original_creator_username, atomically increment save_count on shared_itineraries
    - Implement `publish_shared_itinerary(user_id, trip_id, metadata)` — validate user owns trip, validate trip has ≥1 day with ≥1 activity slot, snapshot itinerary JSONB into new shared_itineraries row with metadata
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 6.1, 6.2, 6.3, 6.4, 7.4, 7.5, 11.1_

  - [ ]* 4.2 Write property test: Trending sort order (Property 1)
    - **Property 1: Trending section is sorted by save count descending**
    - Generate random lists of itineraries with varying save_counts, verify trending query returns them in non-increasing save_count order
    - **Validates: Requirements 2.3**

  - [ ]* 4.3 Write property test: Budget indicator formatting (Property 3)
    - **Property 3: Budget indicator formatting**
    - For integers 1-5, verify formatted string is exactly N dollar signs
    - **Validates: Requirements 3.3**

  - [ ]* 4.4 Write property test: Search filter correctness (Property 4)
    - **Property 4: Search filter correctness**
    - Generate random query strings, duration ranges, and itinerary sets; verify all results match both filters when active
    - **Validates: Requirements 4.2, 4.3, 4.4**

  - [ ]* 4.5 Write property test: Copy preserves data and attribution (Property 5)
    - **Property 5: Copy preserves itinerary data and attribution**
    - Generate random itinerary JSONB structures, verify copied trip contains identical itinerary, correct creator_username, and correct copied_from_shared_id
    - **Validates: Requirements 6.1, 6.2, 6.3**

  - [ ]* 4.6 Write property test: Save count increment (Property 6)
    - **Property 6: Copy increments save count by exactly one**
    - Generate random initial save_counts, verify post-copy count equals initial + 1
    - **Validates: Requirements 6.4**

  - [ ]* 4.7 Write property test: Publish validation (Property 7)
    - **Property 7: Publish validation rejects invalid metadata**
    - Generate random metadata payloads with valid and invalid fields, verify correct accept/reject behavior
    - **Validates: Requirements 7.2, 8.6, 11.2, 11.3, 11.4**

  - [ ]* 4.8 Write property test: Quality gate (Property 8)
    - **Property 8: Quality gate rejects incomplete itineraries**
    - Generate random itinerary structures (some with 0 days/activities, some valid), verify quality check accept/reject
    - **Validates: Requirements 7.4, 11.1**

  - [ ]* 4.9 Write property test: Ownership check (Property 9)
    - **Property 9: Only trip owner can publish**
    - Generate random user_id/trip owner_id pairs, verify publish succeeds only when they match
    - **Validates: Requirements 8.5**

- [ ] 5. Checkpoint - Ensure backend service and property tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 6. Backend routes for shared itineraries
  - [~] 6.1 Create `backend/routes/shared_itineraries.py`
    - `GET /shared-itineraries` — list/search with query params (section, destination, budget_level, min_days, max_days, page, page_size), no auth required
    - `GET /shared-itineraries/{id}` — get full detail, no auth required
    - `POST /shared-itineraries/{id}/copy` — copy to user's trips, auth required, returns CopyResponse
    - `POST /shared-itineraries` — publish from user's trip, auth required, validates all metadata fields, returns 422 on validation failure
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7_

  - [~] 6.2 Register router in `backend/main.py`
    - Import and include the shared_itineraries router
    - _Requirements: 8.1_

  - [ ]* 6.3 Write integration tests for shared itinerary endpoints
    - Test full publish flow: create trip → publish → verify shared_itineraries row
    - Test full copy flow: publish → copy → verify trips row + save_count increment
    - Test search with filter combinations
    - Test 422 responses for invalid publish requests
    - Test 403 for non-owner publish attempts
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7_

- [ ] 7. Checkpoint - Ensure backend is complete and all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 8. iOS models for shared itineraries
  - [~] 8.1 Create `ios/Orbi/Models/SharedItineraryModels.swift`
    - Define `SharedItineraryCard` (Codable, Identifiable): id, title, destination, numDays, budgetLevel, coverPhotoUrl, creatorUsername, saveCount, tags
    - Define `SharedItineraryDetail` (Codable, Identifiable): full detail including itinerary as `[String: AnyCodableValue]?`, description, destinationLatLng, createdAt
    - Define `ExploreSection` (Codable, Identifiable): id, title, sectionType, items array of SharedItineraryCard
    - Define `ExploreFeedResponse` (Codable): sections array
    - Define `SharedItineraryPublishRequest` (Encodable): sourceTripId, coverPhotoUrl, title, description, destination, budgetLevel, tags
    - Define `CopyResponse` (Codable): tripId
    - _Requirements: 3.1, 5.1, 8.1, 8.2, 8.3, 8.4_

- [ ] 9. iOS tab bar restructuring
  - [~] 9.1 Update `ContentView.swift` tab bar to 4 tabs
    - Extend `AppTab` enum to: `.plan`, `.explore`, `.trips`, `.profile`
    - Rename existing `.explore` case to `.plan` (globe/search screen)
    - Add new `.explore` case pointing to `ExploreFeedView` (placeholder initially)
    - Update `FloatingTabBar` tabs array: Plan (globe.americas.fill), Explore (square.grid.2x2), Trips (suitcase.fill), Profile (person.fill)
    - Set default selected tab to `.plan`
    - Update switch statement in body to handle all 4 cases
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

- [ ] 10. iOS Explore feed view
  - [~] 10.1 Create `ExploreFeedView` and `ExploreFeedViewModel`
    - ViewModel: `@MainActor ObservableObject` with `@Published sections`, `searchQuery`, `durationFilter`, `searchResults`, `isLoading`, `errorMessage`
    - Implement `loadFeed()` — GET /shared-itineraries with section grouping
    - Implement `search(query:duration:)` — GET /shared-itineraries with filters
    - Implement `refresh()` — pull-to-refresh
    - View: search bar at top, vertical ScrollView of horizontal card rows per section
    - Show loading indicator while fetching (Req 2.6)
    - Show error message with retry button on failure (Req 2.7)
    - Support pull-to-refresh (Req 2.8)
    - When search is active, switch to filtered flat list
    - Show empty state when no search results (Req 4.6)
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6_

  - [ ]* 10.2 Write unit tests for ExploreFeedViewModel
    - Test section ordering, search filtering, error/loading states
    - _Requirements: 2.1, 4.2, 4.4_

- [ ] 11. iOS itinerary card view
  - [~] 11.1 Create `ItineraryCardView`
    - Display cover photo (AsyncImage) or gradient placeholder with destination icon when unavailable
    - Display title, destination, trip duration in days, budget indicator (dollar signs), creator username, save count with bookmark icon
    - Tappable — navigates to ItineraryDetailView
    - Use DesignTokens for theming, glassmorphic card style
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [ ] 12. iOS itinerary detail view with save/copy
  - [~] 12.1 Create `ItineraryDetailView` and `ItineraryDetailViewModel`
    - ViewModel: `@MainActor ObservableObject` with `@Published itinerary`, `isSaving`, `hasSaved`, `errorMessage`
    - Implement `loadDetail(id:)` — GET /shared-itineraries/{id}
    - Implement `saveToMyTrips(id:)` — POST /shared-itineraries/{id}/copy
    - View: cover photo, title, description, destination, budget indicator, creator username
    - Day-by-day breakdown reusing existing day/slot/meal card patterns from SavedTripDetailView
    - Prominent "Save to My Trips" button
    - Show confirmation and update button state after successful save (Req 5.7)
    - Show error alert with retry on failure (Req 5.8)
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9, 6.1, 6.5_

  - [ ]* 12.2 Write unit tests for ItineraryDetailViewModel
    - Test save state transitions, error handling
    - _Requirements: 5.6, 5.7, 5.8_

- [ ] 13. Checkpoint - Ensure Explore tab views are functional
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 14. iOS share publishing flow
  - [~] 14.1 Create `SharePublishView` and `SharePublishViewModel`
    - ViewModel: `@MainActor ObservableObject` with `@Published coverPhotoURL`, `title` (max 100), `description` (max 500), `destination`, `budgetLevel` (1-5), `selectedTags` (Set<String>: food, nightlife, outdoors, family), `isPublishing`, `publishError`
    - Implement `publish(tripId:)` — POST /shared-itineraries with metadata
    - Computed `canSubmit` — validates all required fields and minimum quality (Req 7.4, 11.1, 11.2, 11.3, 11.4)
    - View: form with cover photo URL input, title field, description field, destination (pre-filled from trip), budget level picker (1-5), tag multi-select pills
    - Show confirmation on success (Req 7.6)
    - Show error with retry on failure (Req 7.7)
    - Prompt username creation if user has no username set (Req 10.2)
    - Accessible from SavedTripDetailView via "Share to Explore" button
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 10.2, 11.1, 11.2, 11.3, 11.4_

  - [~] 14.2 Add "Share to Explore" button to `SavedTripDetailView`
    - Add button in the saved trip detail toolbar or header
    - Present SharePublishView as a sheet
    - _Requirements: 7.1_

  - [ ]* 14.3 Write unit tests for SharePublishViewModel validation
    - Test canSubmit logic with various valid/invalid field combinations
    - _Requirements: 11.2, 11.3, 11.4_

- [ ] 15. iOS profile username updates
  - [~] 15.1 Add username display and edit to ProfileTab
    - Show current username in profile section
    - Allow user to set/update username if not already set
    - Enforce max 30 characters, uniqueness handled by backend
    - _Requirements: 10.1, 10.2, 10.3_

- [ ] 16. iOS attribution display on copied trips
  - [~] 16.1 Update `TripResponse` and `TripListItem` models
    - Add optional `copiedFromSharedId` and `originalCreatorUsername` fields to `TripResponse`
    - _Requirements: 6.2, 6.3_

  - [~] 16.2 Update `SavedTripDetailView` to show attribution
    - When `originalCreatorUsername` is present, display "Originally by [Creator_Username]" in the trip header
    - _Requirements: 6.6_

- [ ] 17. Non-goals enforcement verification
  - [~] 17.1 Verify no social features in Explore views
    - Confirm ExploreFeedView, ItineraryCardView, and ItineraryDetailView do NOT include: follower counts, follow buttons, DM/chat interfaces, comments sections, stories/reels/ephemeral content
    - _Requirements: 12.1, 12.2, 12.3, 12.4_

- [x] 18. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- The backend uses the existing Supabase client pattern (`_get_supabase()`) and FastAPI router conventions
- iOS views follow existing DesignTokens theming and glassmorphic card patterns
