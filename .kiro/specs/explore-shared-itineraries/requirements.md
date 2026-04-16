# Requirements Document

## Introduction

The Explore Shared Itineraries feature adds a structured library of high-quality, reusable itineraries to the Orbi iOS travel app. Users can discover itineraries created by other users, evaluate them via a detail view, and save (copy) them into their own "My Trips" for full editing. Users can also publish their own completed itineraries to the library. This is not a social feed — it is a curated, actionable collection. The feature introduces a new "Explore" tab in the bottom navigation bar, with the existing globe/search screen renamed to "Plan."

## Glossary

- **Explore_Feed**: The scrollable screen within the new Explore tab that displays shared itineraries organized into curated sections (Featured, Trending, Browse by Destination, Browse by Budget Level).
- **Itinerary_Card**: A compact card displayed in the Explore_Feed showing a shared itinerary's cover photo, title, destination, trip duration, budget indicator, creator username, and save count.
- **Itinerary_Detail_View**: A full-screen view showing the complete day-by-day breakdown of a shared itinerary, including cover photo, title, description, destination, budget level, creator username, and a "Save to My Trips" action.
- **Save_Copy_Service**: The backend service responsible for creating a fully editable copy of a shared itinerary in the requesting user's My Trips collection.
- **Share_Publishing_Flow**: The user-facing flow that allows a user to publish a completed itinerary from My Trips to the Explore_Feed, including required metadata entry.
- **Shared_Itinerary**: An itinerary record published to the Explore library by a user, containing the full trip structure plus metadata (cover photo, title, description, destination, budget level, tags, creator username).
- **Tab_Bar**: The bottom navigation bar in the Orbi app, currently containing Explore (globe), Trips, and Profile tabs.
- **Budget_Indicator**: A 1-to-5 dollar-sign scale ($–$$$$$) representing the cost level of a shared itinerary.
- **Tag**: An optional label (e.g., food, nightlife, outdoors, family) attached to a Shared_Itinerary for categorization.
- **Creator_Username**: The username of the user who originally created and published a Shared_Itinerary.

## Requirements

### Requirement 1: Tab Bar Restructuring

**User Story:** As a user, I want the bottom navigation to clearly separate trip planning from itinerary discovery, so that I can quickly access either function.

#### Acceptance Criteria

1. THE Tab_Bar SHALL display four tabs in the following order: Plan, Explore, Trips, Profile.
2. WHEN the app launches, THE Tab_Bar SHALL display the Plan tab as the default selected tab.
3. THE Tab_Bar SHALL use the icon "globe.americas.fill" for the Plan tab and a "compass" or "square.grid.2x2" icon for the Explore tab.
4. WHEN the user taps the Plan tab, THE Tab_Bar SHALL navigate to the existing globe/search screen (currently named Explore).
5. WHEN the user taps the Explore tab, THE Tab_Bar SHALL navigate to the Explore_Feed screen.

### Requirement 2: Explore Feed Display

**User Story:** As a user, I want to browse a curated collection of shared itineraries organized by category, so that I can find relevant travel inspiration.

#### Acceptance Criteria

1. WHEN the Explore tab is selected, THE Explore_Feed SHALL display itineraries organized into the following sections in order: Featured, Trending, Browse by Destination, Browse by Budget Level.
2. THE Explore_Feed SHALL display each section as a horizontally scrollable row of Itinerary_Cards.
3. THE Explore_Feed SHALL populate the Trending section based on the number of saves/copies in descending order.
4. THE Explore_Feed SHALL populate the Browse by Destination section grouped by city name.
5. THE Explore_Feed SHALL populate the Browse by Budget Level section grouped by Budget_Indicator value.
6. WHEN the Explore_Feed data is loading, THE Explore_Feed SHALL display a loading indicator.
7. IF the Explore_Feed fails to load data, THEN THE Explore_Feed SHALL display an error message with a retry button.
8. THE Explore_Feed SHALL support pull-to-refresh to reload all sections.

### Requirement 3: Itinerary Card

**User Story:** As a user, I want to see key details of a shared itinerary at a glance, so that I can decide whether to view the full itinerary.

#### Acceptance Criteria

1. THE Itinerary_Card SHALL display the following fields: cover photo, title, destination, trip duration in days, Budget_Indicator, Creator_Username, and save count.
2. WHEN a cover photo is not available, THE Itinerary_Card SHALL display a gradient placeholder with a destination icon.
3. THE Itinerary_Card SHALL display the Budget_Indicator as a string of dollar signs (e.g., "$$" for budget level 2).
4. THE Itinerary_Card SHALL display the save count as a numeric value with a bookmark icon.
5. WHEN the user taps an Itinerary_Card, THE Explore_Feed SHALL navigate to the Itinerary_Detail_View for that Shared_Itinerary.

### Requirement 4: Search Shared Itineraries

**User Story:** As a user, I want to search for shared itineraries by destination and trip duration, so that I can find itineraries matching my travel plans.

#### Acceptance Criteria

1. THE Explore_Feed SHALL display a search bar at the top of the screen.
2. WHEN the user enters a destination city name in the search bar, THE Explore_Feed SHALL filter displayed itineraries to those matching the destination (case-insensitive partial match).
3. WHEN the user selects a trip duration filter, THE Explore_Feed SHALL filter displayed itineraries to those matching the selected duration range.
4. WHEN both destination and duration filters are active, THE Explore_Feed SHALL display only itineraries matching both criteria.
5. WHEN the search query is cleared, THE Explore_Feed SHALL return to the default curated section layout.
6. WHEN no itineraries match the search criteria, THE Explore_Feed SHALL display an empty state message indicating no results were found.

### Requirement 5: Itinerary Detail View

**User Story:** As a user, I want to view the full day-by-day breakdown of a shared itinerary before saving it, so that I can evaluate whether it suits my travel style.

#### Acceptance Criteria

1. THE Itinerary_Detail_View SHALL display the cover photo, title, description, destination, Budget_Indicator, and Creator_Username.
2. THE Itinerary_Detail_View SHALL display the full day-by-day itinerary organized by day number, with each day divided into Morning, Afternoon, and Evening time blocks.
3. THE Itinerary_Detail_View SHALL display each activity slot with the activity name, description, estimated duration, and estimated cost.
4. THE Itinerary_Detail_View SHALL display each meal slot with the restaurant name, cuisine type, price level, and meal type.
5. THE Itinerary_Detail_View SHALL display a prominent "Save to My Trips" button.
6. WHEN the user taps the "Save to My Trips" button, THE Save_Copy_Service SHALL create a copy of the Shared_Itinerary in the user's My Trips collection.
7. WHEN the save operation completes successfully, THE Itinerary_Detail_View SHALL display a confirmation message and update the button state to indicate the itinerary has been saved.
8. IF the save operation fails, THEN THE Itinerary_Detail_View SHALL display an error message with a retry option.
9. THE Itinerary_Detail_View SHALL display an optional link to view the original Shared_Itinerary.

### Requirement 6: Save/Copy Behavior

**User Story:** As a user, I want saved itineraries to be fully editable in My Trips, so that I can customize them for my own travel dates and preferences.

#### Acceptance Criteria

1. WHEN the Save_Copy_Service creates a copy, THE Save_Copy_Service SHALL preserve the full itinerary structure including all days, time blocks, activity slots, and meal slots.
2. WHEN the Save_Copy_Service creates a copy, THE Save_Copy_Service SHALL store the Creator_Username as attribution metadata on the copied trip.
3. WHEN the Save_Copy_Service creates a copy, THE Save_Copy_Service SHALL store a reference to the original Shared_Itinerary identifier on the copied trip.
4. THE Save_Copy_Service SHALL increment the save count on the original Shared_Itinerary by one for each successful copy operation.
5. WHEN a copied trip is opened in My Trips, THE copied trip SHALL be fully editable including date customization, activity replacement, activity removal, meal replacement, and meal removal.
6. WHEN a copied trip is opened in My Trips, THE copied trip SHALL display the Creator_Username as "Originally by [Creator_Username]" in the trip header.

### Requirement 7: Share Publishing Flow

**User Story:** As a user, I want to share my completed itinerary to the Explore library, so that other travelers can benefit from my trip planning.

#### Acceptance Criteria

1. WHEN a user views a saved trip in My Trips, THE Share_Publishing_Flow SHALL display a "Share to Explore" option.
2. WHILE the Share_Publishing_Flow is active, THE Share_Publishing_Flow SHALL require the user to provide: a cover photo, a title (max 100 characters), a destination city, a Budget_Indicator (1-5), and a short description (max 500 characters).
3. WHILE the Share_Publishing_Flow is active, THE Share_Publishing_Flow SHALL allow the user to optionally select one or more Tags from the set: food, nightlife, outdoors, family.
4. IF the trip does not contain at least one complete day with at least one activity slot, THEN THE Share_Publishing_Flow SHALL prevent submission and display a message indicating only completed itineraries can be shared.
5. WHEN the user submits the Share_Publishing_Flow, THE Share_Publishing_Flow SHALL create a Shared_Itinerary record with the provided metadata and the full itinerary structure.
6. WHEN the publish operation completes successfully, THE Share_Publishing_Flow SHALL display a confirmation message.
7. IF the publish operation fails, THEN THE Share_Publishing_Flow SHALL display an error message with a retry option.

### Requirement 8: Shared Itinerary Backend API

**User Story:** As a developer, I want well-defined API endpoints for shared itineraries, so that the iOS client can reliably fetch, search, save, and publish itineraries.

#### Acceptance Criteria

1. THE Shared_Itinerary backend SHALL expose a GET endpoint that returns paginated lists of Shared_Itineraries, supporting query parameters for section type (featured, trending), destination filter, budget level filter, and duration filter.
2. THE Shared_Itinerary backend SHALL expose a GET endpoint that returns the full detail of a single Shared_Itinerary by its identifier.
3. THE Shared_Itinerary backend SHALL expose a POST endpoint that creates a copy of a Shared_Itinerary in the authenticated user's trips collection and increments the save count.
4. THE Shared_Itinerary backend SHALL expose a POST endpoint that publishes a new Shared_Itinerary from an authenticated user's existing trip.
5. THE Shared_Itinerary backend SHALL validate that the publishing user owns the source trip before creating a Shared_Itinerary.
6. THE Shared_Itinerary backend SHALL validate all required metadata fields (cover photo URL, title, destination, budget level, description) before accepting a publish request.
7. IF a required field is missing or invalid in a publish request, THEN THE Shared_Itinerary backend SHALL return a 422 response with a descriptive error message.

### Requirement 9: Database Schema for Shared Itineraries

**User Story:** As a developer, I want a dedicated database table for shared itineraries, so that explore data is stored independently from user trips.

#### Acceptance Criteria

1. THE database SHALL contain a shared_itineraries table with columns for: id (UUID primary key), user_id (foreign key to users), source_trip_id (foreign key to trips), title (text, max 100 characters), description (text, max 500 characters), destination (text), destination_lat_lng (text), budget_level (integer, 1-5), cover_photo_url (text), tags (text array), num_days (integer), itinerary (JSONB), save_count (integer, default 0), is_featured (boolean, default false), created_at (timestamptz), and updated_at (timestamptz).
2. THE database SHALL create indexes on the shared_itineraries table for: destination, budget_level, save_count (descending), is_featured, and user_id.
3. WHEN a Shared_Itinerary is created, THE database SHALL store the Creator_Username by joining with the users table via user_id.
4. WHEN a trip referenced by source_trip_id is deleted, THE Shared_Itinerary record SHALL remain in the database (no cascade delete on source_trip_id).

### Requirement 10: Profile Username Visibility

**User Story:** As a user, I want my username to be visible on itineraries I share, so that other users can see who created the itinerary.

#### Acceptance Criteria

1. THE users table SHALL contain a username column (text, unique, max 30 characters).
2. WHILE a user does not have a username set, THE Share_Publishing_Flow SHALL prompt the user to create a username before publishing.
3. WHEN a Shared_Itinerary is displayed, THE Itinerary_Card and Itinerary_Detail_View SHALL display the Creator_Username retrieved from the users table.

### Requirement 11: Quality Control

**User Story:** As a product owner, I want shared itineraries to meet a minimum quality bar, so that the Explore library contains useful, reusable content.

#### Acceptance Criteria

1. IF a trip contains fewer than 1 complete day with at least 1 activity slot, THEN THE Share_Publishing_Flow SHALL reject the submission.
2. IF the title is empty or exceeds 100 characters, THEN THE Share_Publishing_Flow SHALL reject the submission with a validation error.
3. IF the description is empty or exceeds 500 characters, THEN THE Share_Publishing_Flow SHALL reject the submission with a validation error.
4. IF the budget level is not an integer between 1 and 5 inclusive, THEN THE Share_Publishing_Flow SHALL reject the submission with a validation error.

### Requirement 12: Non-Goals Enforcement

**User Story:** As a product owner, I want to ensure the Explore feature remains a content library and does not become a social network.

#### Acceptance Criteria

1. THE Explore_Feed SHALL NOT display a follower count, follow button, or any follower/following relationship.
2. THE Explore_Feed SHALL NOT display a direct messaging or chat interface.
3. THE Explore_Feed SHALL NOT display a comments section on any Shared_Itinerary.
4. THE Explore_Feed SHALL NOT display stories, reels, or ephemeral content.
