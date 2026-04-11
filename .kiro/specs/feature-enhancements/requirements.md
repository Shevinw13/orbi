# Requirements Document

## Introduction

This specification defines comprehensive feature enhancements for the Orbi iOS travel planning app, covering core feature builds, critical bug fixes, and UX improvements. The enhancements span the Smart Explore experience with GPS-based map defaults and intelligent overlays, an interactive itinerary system with drag-and-drop and AI-powered activity replacement, route intelligence upgrades with full-day optimization and transit cost estimates, bug fixes for restaurant selection, modal dismissal, and profile display, and UX improvements for share formatting, ratings transparency, pricing intelligence, and destination weather insights. All changes maintain the existing dark gradient, glassmorphism design language and modular architecture.

## Glossary

- **Explore_Map**: The MapKit-based interactive map in the Explore tab (currently `GlobeView`) that displays city markers and serves as the primary navigation surface
- **Location_Manager**: The iOS CLLocationManager wrapper that requests and provides the user's current GPS coordinates
- **Overlay_Card**: A glassmorphic card rendered on top of the Explore_Map displaying contextual content such as trending destinations or value trips
- **Filter_Pill**: A capsule-shaped toggle button used for filtering explore content by category (Foodie, Adventure, Relaxation, Nightlife)
- **Marker_Cluster**: A grouped map annotation that aggregates multiple nearby city markers into a single element at low zoom levels to reduce visual clutter
- **Itinerary_Editor**: The interactive itinerary management interface (currently `ItineraryView` and `ItineraryViewModel`) supporting reorder, replace, and optimize operations
- **Activity_Slot**: A single time-blocked activity within a day's itinerary, containing name, description, coordinates, duration, and cost
- **Timeline_Bar**: A visual progression indicator showing Morning, Afternoon, and Evening segments for a single day
- **Route_Optimizer**: The backend or client-side service that reorders activities within a day based on geographic proximity and time efficiency
- **Route_Intelligence**: The enhanced route display system showing full-day optimization, transport mode breakdown, and estimated ride-hail costs
- **Restaurant_Selector**: The restaurant recommendation list in `RecommendationsView` that allows users to tap and select restaurants
- **Trips_Modal**: The modal sheet presenting the Saved Trips screen, dismissed via a Close button
- **Profile_View**: The Profile tab screen displaying user information, settings, saved trips, and preferences sections
- **Auth_Profile**: The authenticated user's profile data (name, email) stored in the auth system and Keychain
- **Share_Formatter**: The service that converts trip data from raw JSON into a human-readable text format for sharing
- **Rating_Label**: A UI element displaying a place's rating with source attribution and review count
- **Price_Indicator**: A UI element displaying estimated price ranges for hotels (per night) and restaurants (per person)
- **Destination_Insights**: A section displaying best time to visit and current weather data for a destination
- **Weather_Service**: The backend service that fetches real-time weather data from a weather API for a given location
- **APIClient**: The iOS networking layer (`Services/APIClient.swift`) that makes HTTP requests to the Backend
- **Backend**: The Python/FastAPI server located at `drobe/backend/`

## Requirements

### Requirement 1: GPS-Based Explore Map Default Location

**User Story:** As a traveler, I want the explore map to center on my current location by default, so that I see nearby destinations without manual navigation.

#### Acceptance Criteria

1. WHEN the Explore tab loads for the first time, THE Location_Manager SHALL request the user's current GPS coordinates using CLLocationManager
2. WHEN the user grants location permission, THE Explore_Map SHALL center on the user's current GPS coordinates with a regional zoom level showing nearby cities
3. IF the user denies location permission, THEN THE Explore_Map SHALL center on the last known location stored in UserDefaults
4. IF no last known location is available and location permission is denied, THEN THE Explore_Map SHALL center on a default major city (New York, latitude 40.7128, longitude -74.0060)
5. WHEN the user's location is successfully obtained, THE Location_Manager SHALL persist the coordinates in UserDefaults as the last known location

### Requirement 2: Intelligent Explore Overlays

**User Story:** As a traveler, I want to see curated destination suggestions on the explore map, so that I can discover trending and value destinations relevant to my location.

#### Acceptance Criteria

1. WHEN the Explore_Map loads with a known user location, THE Explore_Map SHALL display up to four Overlay_Card elements: "Trending destinations", "Best value trips from [user city]", "Popular this month", and "Weekend trips"
2. WHEN the user taps an Overlay_Card, THE Explore_Map SHALL navigate to a list of destinations matching that overlay category
3. THE Backend SHALL provide a GET endpoint `/explore/overlays` that accepts latitude and longitude parameters and returns overlay data with category, title, and destination list
4. WHEN the Backend returns overlay data, THE Explore_Map SHALL render each Overlay_Card using glassmorphic styling consistent with the existing design tokens
5. IF the Backend is unreachable, THEN THE Explore_Map SHALL hide the Overlay_Card elements and display only the map with city markers

### Requirement 3: Map Clustering and Zoom Behavior

**User Story:** As a traveler, I want the map to reduce clutter at low zoom levels and reveal detail on zoom-in, so that the explore experience remains readable at all scales.

#### Acceptance Criteria

1. WHILE the Explore_Map is at a zoom level where markers overlap, THE Explore_Map SHALL group nearby markers into Marker_Cluster annotations displaying a count badge
2. WHEN the user zooms in past the clustering threshold, THE Explore_Map SHALL expand Marker_Cluster annotations into individual city markers with city name labels
3. WHILE the Explore_Map is at a low zoom level, THE Explore_Map SHALL display only Marker_Cluster annotations and hide individual city name labels
4. WHEN the user taps a Marker_Cluster, THE Explore_Map SHALL zoom into the cluster region to reveal individual city markers

### Requirement 4: Explore Category Filters

**User Story:** As a traveler, I want to filter explore destinations by category, so that I can find destinations matching my travel interests.

#### Acceptance Criteria

1. THE Explore_Map SHALL display a horizontal row of Filter_Pill buttons above the map: Foodie, Adventure, Relaxation, and Nightlife
2. WHEN the user taps a Filter_Pill, THE Explore_Map SHALL highlight the selected Filter_Pill with the accent gradient and filter visible city markers to destinations matching that category
3. WHEN a Filter_Pill is active, THE Backend SHALL accept a `category` query parameter on the `/search/popular-cities` endpoint and return only cities tagged with that category
4. WHEN the user taps the active Filter_Pill again, THE Explore_Map SHALL deselect the filter and restore all city markers

### Requirement 5: Drag-and-Drop Itinerary Reordering

**User Story:** As a traveler, I want to drag and drop activities to reorder my itinerary, so that I can customize the sequence of my daily plans.

#### Acceptance Criteria

1. WHEN the user long-presses an Activity_Slot card in the Itinerary_Editor, THE Itinerary_Editor SHALL enter drag mode with a visual lift effect on the dragged card
2. WHILE the user drags an Activity_Slot, THE Itinerary_Editor SHALL display a drop indicator showing the target position within the same day
3. WHEN the user drops an Activity_Slot at a new position within the same day, THE Itinerary_Editor SHALL reorder the slots array and update the timeline display
4. WHEN the user drops an Activity_Slot onto a different day header, THE Itinerary_Editor SHALL move the activity from the source day to the target day
5. WHEN any reorder operation completes, THE Itinerary_Editor SHALL recalculate the cost breakdown to reflect the updated itinerary

### Requirement 6: AI-Powered Single Activity Replacement

**User Story:** As a traveler, I want to replace a single activity with an AI-generated alternative that respects time and location constraints, so that I can swap out activities without regenerating the entire itinerary.

#### Acceptance Criteria

1. WHEN the user taps the "Replace" button on an Activity_Slot, THE Itinerary_Editor SHALL send a replacement request to the Backend containing the destination, day number, time slot, current activity name, list of existing activities, and trip vibe
2. WHEN the Backend receives a replacement request, THE Backend SHALL call OpenAI with a prompt that excludes all existing activities and constrains the replacement to the same time slot and geographic area
3. WHEN the Backend returns a replacement Activity_Slot, THE Itinerary_Editor SHALL swap the old activity with the new one in the itinerary, preserving the time slot position
4. WHILE a replacement request is in progress, THE Itinerary_Editor SHALL display a loading overlay with the text "Finding alternative…" and disable additional Replace actions
5. IF the replacement request fails, THEN THE Itinerary_Editor SHALL display an error message and retain the original activity

### Requirement 7: Optimize Day Button

**User Story:** As a traveler, I want to optimize the order of activities in a day based on proximity and time efficiency, so that I minimize travel time between stops.

#### Acceptance Criteria

1. THE Itinerary_Editor SHALL display an "Optimize Day" button in each day section header
2. WHEN the user taps "Optimize Day", THE Route_Optimizer SHALL reorder the activities for that day using a nearest-neighbor algorithm based on geographic coordinates, minimizing total travel distance
3. WHEN the Route_Optimizer completes reordering, THE Itinerary_Editor SHALL update the slots array for that day and animate the position changes
4. WHEN the optimization completes, THE Itinerary_Editor SHALL recalculate travel times between consecutive activities and update the displayed travel time values
5. IF a day contains fewer than three activities, THEN THE "Optimize Day" button SHALL be disabled with reduced opacity

### Requirement 8: Visual Timeline Bar

**User Story:** As a traveler, I want to see a visual timeline showing Morning, Afternoon, and Evening progression for each day, so that I can quickly understand the day's schedule structure.

#### Acceptance Criteria

1. THE Itinerary_Editor SHALL display a Timeline_Bar at the top of each day section showing three segments: Morning, Afternoon, and Evening
2. WHEN activities exist in a time segment, THE Timeline_Bar SHALL fill that segment with the corresponding time slot color (cyan for Morning, blue for Afternoon, purple for Evening)
3. WHEN a time segment has no activities, THE Timeline_Bar SHALL display that segment with a dimmed outline style
4. WHEN the user taps a segment on the Timeline_Bar, THE Itinerary_Editor SHALL scroll to the first activity in that time segment

### Requirement 9: Full-Day Route Optimization

**User Story:** As a traveler, I want to see optimized routing for my entire day rather than per-segment, so that I get the most efficient travel plan.

#### Acceptance Criteria

1. WHEN the Map_Route_View loads for a day, THE Route_Intelligence SHALL calculate routes between all consecutive activities as a single optimized sequence rather than independent segments
2. THE Route_Intelligence SHALL display the total travel time for the entire day in the Route Summary Card
3. THE Route_Intelligence SHALL display a breakdown of walking time versus driving time in the Route Summary Card
4. WHEN a route segment exceeds 30 minutes of walking time, THE Route_Intelligence SHALL automatically calculate and display the driving route alternative for that segment

### Requirement 10: Estimated Ride-Hail and Transit Costs

**User Story:** As a traveler, I want to see estimated Uber costs and public transit options for route segments, so that I can plan my transportation budget.

#### Acceptance Criteria

1. THE Route_Intelligence SHALL display an estimated ride-hail cost range for each route segment that exceeds 15 minutes of walking time
2. THE Route_Intelligence SHALL calculate ride-hail estimates using a base fare plus per-kilometer rate formula appropriate to the destination city
3. THE Route_Intelligence SHALL display a public transit option label for each route segment where transit data is available from MapKit
4. WHEN the user taps a route segment in the stop list, THE Route_Intelligence SHALL show a detail card with walking time, driving time, estimated ride-hail cost, and transit option

### Requirement 11: Restaurant Selection State Fix

**User Story:** As a traveler, I want to tap and select restaurants from the recommendations list, so that my selection is reflected in the itinerary and cost breakdown.

#### Acceptance Criteria

1. WHEN the user taps a restaurant card in the Restaurant_Selector, THE Restaurant_Selector SHALL highlight the tapped card with an accent border and display a checkmark icon
2. WHEN a restaurant is selected, THE Restaurant_Selector SHALL store the selection in the RecommendationsViewModel as `selectedRestaurants`
3. WHEN the user selects a restaurant, THE Restaurant_Selector SHALL persist the selection so that the itinerary generation and cost breakdown reflect the chosen restaurant
4. THE Restaurant_Selector SHALL allow the user to deselect a restaurant by tapping the selected card again, removing the highlight and checkmark

### Requirement 12: Trips Screen Close Button Fix

**User Story:** As a traveler, I want the Close button on the Trips screen to dismiss the modal, so that I can return to the previous screen.

#### Acceptance Criteria

1. WHEN the user taps the "Close" button on the Trips_Modal, THE Trips_Modal SHALL dismiss and return the user to the previous screen
2. THE Trips_Modal SHALL use the SwiftUI `dismiss` environment action to perform the navigation dismissal
3. WHEN the Trips_Modal is presented as a sheet, THE "Close" button SHALL be positioned in the navigation bar cancellation action placement

### Requirement 13: Profile Page User Name and Navigation Fix

**User Story:** As a traveler, I want the Profile page to display my actual name and have functional navigation for all sections, so that the profile screen is complete and usable.

#### Acceptance Criteria

1. WHEN the Profile_View loads, THE Profile_View SHALL display the authenticated user's name from Auth_Profile instead of the hardcoded text "Traveler"
2. IF the Auth_Profile name is not available, THEN THE Profile_View SHALL display the user's email address as a fallback
3. THE Profile_View SHALL provide functional navigation for the Settings section, opening a settings detail screen
4. THE Profile_View SHALL provide functional navigation for the Saved Trips section, navigating to the Saved_Trips_View
5. THE Profile_View SHALL provide functional navigation for the Preferences section, opening a preferences detail screen where the user can set default trip preferences
6. WHEN the AuthService completes login or registration, THE AuthService SHALL store the user's display name in a published property accessible to Profile_View

### Requirement 14: Human-Readable Share Format

**User Story:** As a traveler, I want to share my trip in a clean, readable format, so that recipients can understand the itinerary in iMessage, Email, or Notes without seeing raw JSON.

#### Acceptance Criteria

1. WHEN the user taps the Share button, THE Share_Formatter SHALL generate a human-readable text representation of the trip instead of raw JSON
2. THE Share_Formatter SHALL include a title line in the format "[N]-Day [Destination] [Vibe] Trip" (e.g., "5-Day Barcelona Foodie Trip")
3. THE Share_Formatter SHALL include a day-by-day breakdown with day headers and key activity highlights for each day
4. THE Share_Formatter SHALL include the restaurant recommendation name for each day that has one
5. THE Share_Formatter SHALL produce plain text output that renders correctly in iMessage, Email, and Notes applications without requiring special formatting support
6. WHEN the share text is generated, THE Share_Formatter SHALL present the iOS system share sheet (UIActivityViewController) with the formatted text

### Requirement 15: Ratings Source Transparency

**User Story:** As a traveler, I want to see where ratings come from and how many reviews they are based on, so that I can assess the reliability of place ratings.

#### Acceptance Criteria

1. THE Rating_Label SHALL display a source attribution label below the star rating (e.g., "Aggregated reviews")
2. THE Rating_Label SHALL display subtext indicating the number of reviews (e.g., "Based on 142 reviews")
3. WHEN the Backend returns place recommendations, THE Backend SHALL include `rating_source` and `review_count` fields in each PlaceResult
4. IF the review count is not available from the data source, THEN THE Rating_Label SHALL omit the review count subtext and display only the source label

### Requirement 16: Hotel and Restaurant Pricing Intelligence

**User Story:** As a traveler, I want to see estimated price ranges for hotels and restaurants, so that I can make informed budget decisions.

#### Acceptance Criteria

1. THE Price_Indicator SHALL display an estimated nightly price range for hotel recommendations (e.g., "$150–$300/night")
2. THE Price_Indicator SHALL display an estimated cost per person for restaurant recommendations (e.g., "$15–$60")
3. WHEN the Backend returns place recommendations, THE Backend SHALL include `price_range_min` and `price_range_max` fields in each PlaceResult
4. IF price range data is not available, THEN THE Price_Indicator SHALL display only the price level symbol (e.g., "$$") without a numeric range

### Requirement 17: Destination Insights — Best Time to Visit and Weather

**User Story:** As a traveler, I want to see the best time to visit a destination and current weather conditions, so that I can plan my trip timing.

#### Acceptance Criteria

1. THE Destination_Insights section SHALL display a "Best time to visit" recommendation for the selected destination
2. THE Destination_Insights section SHALL display current weather conditions including high and low temperatures in the user's preferred unit
3. WHEN a destination is selected, THE Weather_Service SHALL fetch real-time weather data from a weather API using the destination's latitude and longitude
4. THE Backend SHALL provide a GET endpoint `/destinations/weather` that accepts latitude and longitude parameters and returns current temperature high, temperature low, condition description, and best time to visit
5. THE Destination_Insights section SHALL be displayed on both the destination modal (City_Card) and the trip planning screen (Preferences_Sheet)
6. IF the Weather_Service is unreachable, THEN THE Destination_Insights section SHALL display a placeholder message "Weather data unavailable" and hide the temperature values

### Requirement 18: Design Consistency Constraints

**User Story:** As a user, I want all new features to maintain the existing dark gradient and glassmorphism visual style, so that the app experience remains cohesive.

#### Acceptance Criteria

1. THE Explore_Map, Itinerary_Editor, and all new UI components SHALL use colors, spacing, and corner radii exclusively from the DesignTokens enum
2. THE Explore_Map, Itinerary_Editor, and all new UI components SHALL apply the glassmorphic modifier for card and overlay backgrounds
3. THE Explore_Map, Itinerary_Editor, and all new UI components SHALL use the accent gradient (cyan-to-blue) for primary action buttons and selected states
4. THE Explore_Map, Itinerary_Editor, and all new UI components SHALL maintain dark gradient backgrounds consistent with `DesignTokens.backgroundPrimary` and `DesignTokens.backgroundSecondary`

### Requirement 19: Technical Architecture Constraints

**User Story:** As a developer, I want all new features to follow modular architecture patterns and persist state across sessions, so that the codebase remains maintainable and the user experience is seamless.

#### Acceptance Criteria

1. THE Backend SHALL abstract all new external API integrations (weather API, ride-hail estimation) behind dedicated service modules in the `backend/services/` directory
2. THE iOS_Client SHALL implement all new features as modular SwiftUI views with dedicated ObservableObject view models
3. THE iOS_Client SHALL persist user preferences, last known location, and selected filters across app sessions using UserDefaults or Keychain as appropriate
4. THE Explore_Map SHALL use MapKit annotation clustering APIs (MKClusterAnnotation) for marker clustering to ensure map performance at scale
5. WHEN the Backend introduces new response fields (rating_source, review_count, price_range_min, price_range_max), THE Backend SHALL maintain backward compatibility by making new fields optional with default values
