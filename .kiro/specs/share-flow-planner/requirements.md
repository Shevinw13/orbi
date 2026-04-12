# Requirements Document

## Introduction

Enhance the existing share/export flow in the Orbi iOS travel app to support lightweight planner functionality. The feature adds two optional input fields ("Planned by" and "Add notes") to the share flow and conditionally displays this data in the shared itinerary view. All additions are optional, minimal, and confined to the share flow — no changes to the core consumer experience, Explore screen, itinerary generation, or navigation structure.

## Glossary

- **Share_Flow**: The sequence of screens and actions triggered when a user taps the "Share" or "Export" action from the itinerary screen in TripResultView.
- **Share_Sheet**: The intermediate view presented before the system UIActivityViewController, where optional planner inputs are collected.
- **Shared_Itinerary_View**: The read-only view (SharedTripView) displayed to recipients who open a shared trip link.
- **Share_Formatter**: The utility (ShareFormatter) responsible for formatting trip data into a human-readable plain-text string for sharing.
- **Planned_By_Field**: An optional text input in the Share_Sheet where the user can enter a name or business name.
- **Notes_Field**: An optional multi-line text input in the Share_Sheet where the user can add freeform notes about the trip.
- **Session**: The lifetime of the current app launch, from foreground activation to termination or background suspension.
- **Saved_Trip_Detail_View**: The modal view (SavedTripDetailView in SavedTripsView.swift) displayed when a user taps a saved trip card in the Trips tab, responsible for rendering the full trip data including itinerary, cost, and metadata.
- **SavedTripsViewModel**: The view model (SavedTripsViewModel in SavedTripsView.swift) responsible for loading the trip list and individual trip data from the backend.
- **Weather_View_Model**: The view model (WeatherViewModel in DestinationInsightsView.swift) responsible for fetching weather data from the backend given latitude and longitude coordinates.
- **Destination_Insights_View**: The view (DestinationInsightsView in DestinationInsightsView.swift) that displays weather and destination insight data within the CityCardView on the Explore screen.
- **Day_Section_Header**: The horizontal header row rendered for each day in the itinerary, implemented as `daySectionHeader` in both InlineDaySectionView (TripResultView.swift) and ItineraryView (ItineraryView.swift).
- **Why_This_Plan_Card**: The glassmorphic card at the top of the itinerary tab that displays the AI-generated reasoning text explaining the itinerary plan.

## Requirements

### Requirement 1: Share Sheet Presentation

**User Story:** As a traveler, I want the share action to present an intermediate sheet with optional inputs, so that I can add personal context before sharing.

#### Acceptance Criteria

1. WHEN the user taps the "Share" action in TripResultView, THE Share_Flow SHALL present the Share_Sheet as a modal sheet before invoking UIActivityViewController.
2. THE Share_Sheet SHALL display the trip title at the top of the sheet.
3. THE Share_Sheet SHALL include a "Share" button that triggers UIActivityViewController with the formatted trip text.
4. THE Share_Sheet SHALL include a "Cancel" button that dismisses the sheet without sharing.

### Requirement 2: Planned By Field

**User Story:** As a traveler, I want to optionally add my name or business name to a shared itinerary, so that recipients know who planned the trip.

#### Acceptance Criteria

1. THE Share_Sheet SHALL display a single-line text input labeled "Planned by (optional)".
2. THE Planned_By_Field SHALL accept free-form text up to 100 characters.
3. THE Planned_By_Field SHALL NOT be required to complete the share action.
4. WHEN the user enters a value in the Planned_By_Field, THE Share_Flow SHALL persist that value for the duration of the Session.
5. WHEN the user opens the Share_Sheet again within the same Session, THE Planned_By_Field SHALL display the previously entered value.

### Requirement 3: Notes Field

**User Story:** As a traveler, I want to optionally add notes to a shared itinerary, so that I can provide helpful context like booking reminders or timing tips.

#### Acceptance Criteria

1. THE Share_Sheet SHALL display a multi-line text input labeled "Add notes (optional)".
2. THE Notes_Field SHALL display placeholder text such as "e.g. Book dinner in advance, Best time to visit is sunset".
3. THE Notes_Field SHALL accept free-form text up to 500 characters.
4. THE Notes_Field SHALL NOT be required to complete the share action.
5. THE Notes_Field SHALL expand vertically to accommodate entered text up to 4 visible lines.

### Requirement 4: Share Flow UX Constraints

**User Story:** As a traveler, I want the share flow to remain fast and frictionless, so that optional fields do not slow down my sharing experience.

#### Acceptance Criteria

1. THE Share_Sheet SHALL allow the user to tap "Share" without entering any optional field values.
2. THE Share_Sheet SHALL present the optional fields as subtle enhancements using the existing DesignTokens color palette and glassmorphic styling.
3. THE Share_Sheet SHALL NOT introduce additional navigation steps, tabs, or sections beyond the single sheet.
4. THE Share_Sheet SHALL NOT use terminology such as "Client", "Planner tools", or "Professional mode".

### Requirement 5: Share Output Format

**User Story:** As a traveler, I want the shared text to include my name and notes when provided, so that recipients see the full context I intended.

#### Acceptance Criteria

1. THE Share_Formatter SHALL include the trip title, day-by-day itinerary breakdown, and total estimated cost in the formatted output.
2. WHEN the Planned_By_Field contains a value, THE Share_Formatter SHALL include a "Planned by [value]" line below the trip title.
3. WHEN the Planned_By_Field is empty, THE Share_Formatter SHALL NOT include a "Planned by" line in the output.
4. WHEN the Notes_Field contains a value, THE Share_Formatter SHALL include a "Notes:" section with the entered text after the trip title block.
5. WHEN the Notes_Field is empty, THE Share_Formatter SHALL NOT include a "Notes" section in the output.
6. THE Share_Formatter SHALL produce clean, readable, non-JSON plain text structured for easy consumption.

### Requirement 6: Shared Itinerary View — Planned By Display

**User Story:** As a trip recipient, I want to see who planned the trip, so that I know the source of the itinerary.

#### Acceptance Criteria

1. WHEN the shared trip data includes a non-empty "planned by" value, THE Shared_Itinerary_View SHALL display "Planned by [value]" below the destination title.
2. THE Shared_Itinerary_View SHALL render the "Planned by" text in a subtitle style smaller than the destination title, using DesignTokens.textSecondary color.
3. WHEN the shared trip data does not include a "planned by" value, THE Shared_Itinerary_View SHALL NOT display a "Planned by" label or placeholder.

### Requirement 7: Shared Itinerary View — Notes Display

**User Story:** As a trip recipient, I want to see any notes the planner added, so that I can follow their recommendations.

#### Acceptance Criteria

1. WHEN the shared trip data includes non-empty notes, THE Shared_Itinerary_View SHALL display a "Notes" section near the top of the itinerary content.
2. THE Shared_Itinerary_View SHALL render the "Notes" section with a "Notes" heading and the full note text below it.
3. WHEN the shared trip data does not include notes, THE Shared_Itinerary_View SHALL NOT display a "Notes" section, heading, or empty placeholder.
4. THE Shared_Itinerary_View SHALL NOT display visual gaps or empty space where the notes section would appear when notes are absent.

### Requirement 8: Backend Shared Trip Data Extension

**User Story:** As a system operator, I want the shared trip data model to support optional planner metadata, so that the Shared_Itinerary_View can conditionally render it.

#### Acceptance Criteria

1. THE SharedTripResponse model SHALL include an optional "planned_by" string field.
2. THE SharedTripResponse model SHALL include an optional "notes" string field.
3. WHEN the share link is created, THE Share_Flow SHALL pass the "planned_by" and "notes" values to the backend if provided.
4. WHEN the "planned_by" or "notes" values are empty or not provided, THE backend SHALL store null for those fields.
5. WHEN resolving a share link, THE backend SHALL return the "planned_by" and "notes" fields in the SharedTripResponse.

### Requirement 9: No Core Experience Impact

**User Story:** As a product owner, I want the share flow enhancements to have zero impact on the core app experience, so that existing users are not disrupted.

#### Acceptance Criteria

1. THE Share_Flow enhancements SHALL NOT modify the Explore screen, itinerary generation logic, or navigation structure.
2. THE Share_Flow enhancements SHALL NOT introduce new navigation elements, feature flags, or mode toggles.
3. THE Share_Flow enhancements SHALL NOT alter the existing TripResultView layout or behavior beyond replacing the direct UIActivityViewController invocation with the Share_Sheet presentation.

### Requirement 10: Saved Itinerary Display on Trip Open

**User Story:** As a traveler, I want to open a saved trip from the Trips tab and see the full itinerary rendered with days, activities, map, and cost, so that I can review my previously planned trip.

#### Acceptance Criteria

1. WHEN the user taps a saved trip card in the Trips tab, THE SavedTripsViewModel SHALL load the full TripResponse including the itinerary, cost breakdown, and metadata from the backend via `GET /trips/{id}`.
2. WHEN the TripResponse contains a non-null itinerary field, THE Saved_Trip_Detail_View SHALL decode the itinerary data into an ItineraryResponse and render the full day-by-day itinerary view with activity slots, timeline indicators, and restaurant rows.
3. WHEN the TripResponse contains a non-null costBreakdown field, THE Saved_Trip_Detail_View SHALL decode the cost data and display the cost breakdown section.
4. IF the TripResponse itinerary field is null, THEN THE Saved_Trip_Detail_View SHALL display a "No itinerary data available" message instead of a blank screen.
5. IF the TripResponse fails to load from the backend, THEN THE Saved_Trip_Detail_View SHALL display an error message with a retry option.
6. THE Saved_Trip_Detail_View SHALL display the destination title, trip duration, and vibe in the header section.

### Requirement 11: Weather Display on City Selection

**User Story:** As a traveler, I want to see current weather data when I select a city on the Explore screen, so that I can factor weather into my travel planning.

#### Acceptance Criteria

1. WHEN a city is selected on the Explore screen and the CityCardView appears, THE Destination_Insights_View SHALL trigger a weather data fetch using the selected city's latitude and longitude coordinates.
2. WHEN the Weather_View_Model receives valid latitude and longitude values, THE Weather_View_Model SHALL call the `/destinations/weather` endpoint with those coordinates.
3. WHEN the weather API returns a successful response, THE Destination_Insights_View SHALL display the current weather condition, high and low temperatures, and best time to visit.
4. IF the weather API call fails or returns an error, THEN THE Destination_Insights_View SHALL hide the weather section without displaying an error to the user.
5. WHEN the CityCardView is initialized with a city, THE Destination_Insights_View SHALL receive the city's latitude and longitude as non-zero coordinate values.

### Requirement 12: Day Section Header Cleanup

**User Story:** As a traveler, I want the day header row in the itinerary to be clean and uncluttered, so that I can read the day information without visual noise or truncation.

#### Acceptance Criteria

1. THE Day_Section_Header in InlineDaySectionView (TripResultView.swift) SHALL display only the following elements in order: calendar icon, "Day N" text, a spacer, "Apple Maps" button, and activity count text.
2. THE Day_Section_Header in ItineraryView (ItineraryView.swift) SHALL display only the following elements in order: calendar icon, "Day N" text, a spacer, "Apple Maps" button, and activity count text.
3. THE Day_Section_Header SHALL NOT include a standalone "Map" button, as the "Apple Maps" button provides equivalent map functionality.
4. THE Day_Section_Header SHALL NOT include an "Optimize" button, as itineraries are auto-optimized on load via the ItineraryViewModel initializer.
5. THE Day_Section_Header SHALL render all visible elements without text truncation or overlapping at standard device widths (375pt and above).
6. THE Day_Section_Header SHALL maintain consistent horizontal spacing between the "Apple Maps" button and the activity count text.

### Requirement 13: Why This Plan Reasoning Text Display

**User Story:** As a traveler, I want to read the full reasoning text in the "Why This Plan" card, so that I understand the logic behind my generated itinerary.

#### Acceptance Criteria

1. WHEN the itinerary contains a non-empty reasoningText value, THE Why_This_Plan_Card in TripResultView SHALL display the full reasoning text without truncation.
2. WHEN the itinerary contains a non-empty reasoningText value, THE Why_This_Plan_Card in ItineraryView SHALL display the full reasoning text without truncation.
3. THE Why_This_Plan_Card SHALL NOT apply a lineLimit modifier to the reasoning text, allowing the card to expand vertically to fit the content.
4. THE Why_This_Plan_Card SHALL continue to display the "Optimized for minimal travel time and best experience flow" subtitle below the reasoning text.
