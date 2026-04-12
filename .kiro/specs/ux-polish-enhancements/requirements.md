# Requirements Document

## Introduction

This specification covers a targeted UX polish and enhancement pass for the Orbi iOS travel app. The goal is to improve usability, clarity, trust, and perceived intelligence across 13 existing feature areas without introducing new core systems or increasing architectural complexity. The tech stack is Swift/SwiftUI (iOS) and Python/FastAPI (backend).

## Glossary

- **Orbi_App**: The Orbi iOS travel application built with Swift/SwiftUI
- **Interest_Builder**: The trip configuration UI where users select vibes, trip length, and preferences before generating an itinerary (PreferencesOverlay and DestinationFlowView)
- **Vibe_Chip**: A pill-shaped UI element representing a trip vibe option (Foodie, Adventure, Relaxed, Nightlife)
- **Family_Friendly_Toggle**: A new boolean toggle enabling family-safe itinerary filtering
- **City_Selection_Card**: The glassmorphic card (CityCardView) displayed when a user selects a city on the globe, showing city info and a "Plan Trip" button
- **Weather_Module**: The DestinationInsightsView component that displays weather data within the City_Selection_Card
- **Profile_Page**: The Profile tab (ProfileTab) displaying user info, navigation links, and sign-out
- **Pricing_Display**: UI elements showing hotel and restaurant cost information in PlaceCard and itinerary views
- **Itinerary_View**: The view (ItineraryView / InlineDaySectionView) displaying the generated day-by-day travel plan
- **Itinerary_Engine**: The backend service (itinerary.py) that generates AI-powered itineraries via OpenAI
- **Bookmark_Icon**: A persistent save/unsave toggle icon replacing the current Save button in TripResultView
- **Replace_Item_Service**: The backend endpoint (POST /trips/replace-item) and associated logic for swapping an itinerary activity
- **Trips_Tab**: The "Trips" tab in the bottom navigation showing saved trips (SavedTripsView)
- **Export_Formatter**: The ShareFormatter utility that converts itinerary data into shareable plain text
- **Activity_Tag**: A subtle label (e.g., "Popular", "Hidden gem") applied to itinerary items
- **Loading_Overlay**: The GeneratingOverlay view displayed while an itinerary is being generated
- **Haptic_Feedback**: iOS tactile feedback using UIImpactFeedbackGenerator and UINotificationFeedbackGenerator
- **Cost_Breakdown_View**: The CostBreakdownView displaying estimated trip costs
- **Auth_Service**: The AuthService singleton managing user authentication state and session
- **Globe_Map**: The ClusterMapView (MKMapView UIViewRepresentable) displayed on the Explore screen using satelliteFlyover map type
- **Globe_Glow_Layer**: A SwiftUI gradient overlay rendered behind the Globe_Map to create a soft ambient halo effect
- **Globe_Rotation**: A slow continuous camera heading animation applied to the Globe_Map MKMapCamera
- **Search_Bar**: The SearchBarView floating search overlay with glassmorphic styling and debounced autocomplete
- **Guidance_Text**: A single-line instructional label displayed above the Search_Bar to orient users
- **Globe_Tap_Feedback**: A subtle visual ripple or pulse animation triggered when the user taps the Globe_Map background

## Requirements

### Requirement 1: Interest Builder Vibe Chip Cleanup

**User Story:** As a traveler, I want vibe selection only within the trip configuration card so that the Explore screen header remains uncluttered.

#### Acceptance Criteria

1. THE Orbi_App SHALL display Vibe_Chip elements only within the Interest_Builder trip configuration card (PreferencesOverlay), not in the Explore screen header (GlobeView filter pills row)
2. WHEN the Interest_Builder displays Vibe_Chip elements, THE Orbi_App SHALL wrap Vibe_Chip elements to multiple lines when horizontal space is insufficient for a single row
3. THE Orbi_App SHALL render each Vibe_Chip with full untruncated text, consistent horizontal padding of 16 points, and vertical padding of 9 points
4. THE Orbi_App SHALL maintain a minimum spacing of 8 points between adjacent Vibe_Chip elements in both horizontal and vertical directions

### Requirement 2: Family Friendly Toggle

**User Story:** As a family traveler, I want to enable a family-friendly mode so that generated itineraries prioritize safe, family-appropriate activities.

#### Acceptance Criteria

1. THE Interest_Builder SHALL display a Family_Friendly_Toggle below the vibe selection section
2. WHEN the Family_Friendly_Toggle is enabled, THE Itinerary_Engine SHALL reduce nightlife and adult venue recommendations and prioritize family-safe locations such as parks, museums, zoos, and cultural centers
3. WHEN the Family_Friendly_Toggle is enabled, THE Itinerary_Engine SHALL include the family-friendly constraint in the itinerary generation prompt
4. THE Family_Friendly_Toggle SHALL default to the disabled state

### Requirement 3: City Selection Weather Fix

**User Story:** As a traveler, I want to see actual weather data on the city card so that I can make informed travel decisions.

#### Acceptance Criteria

1. WHEN weather data is available, THE Weather_Module SHALL display the current temperature (high and low) and weather condition with an icon and text label
2. IF the weather API request fails, THEN THE Weather_Module SHALL hide the weather section entirely instead of displaying error text
3. THE City_Selection_Card SHALL NOT display the text "Weather data unavailable" or any error message to the user

### Requirement 4: Profile Page Cleanup

**User Story:** As a user, I want a minimal and functional profile page so that I can quickly access my trips and account actions.

#### Acceptance Criteria

1. THE Profile_Page SHALL display the authenticated user name retrieved from Auth_Service.displayName, falling back to Auth_Service.userId if displayName is nil
2. THE Profile_Page SHALL NOT display the static text "Traveler" when a user name or user ID is available
3. THE Profile_Page SHALL contain exactly three navigation sections: "Saved Trips" linking to SavedTripsView, "My Trips" linking to the Trips_Tab, and "Sign Out" clearing the session via Auth_Service.signOut and returning to the onboarding screen
4. THE Profile_Page SHALL remove the "Settings", "Preferences", "Notifications", and "Appearance" placeholder navigation links

### Requirement 5: Hotel Pricing Display

**User Story:** As a traveler, I want to see numeric hotel pricing so that I can understand actual costs without ambiguous dollar-sign symbols.

#### Acceptance Criteria

1. THE Pricing_Display SHALL show hotel prices in the format "$XXX / night avg" where XXX is a numeric dollar amount
2. THE Pricing_Display SHALL NOT display standalone dollar-sign symbols ($, $$, $$$) for hotel pricing
3. WHEN real pricing data is available from the Place_Service, THE Pricing_Display SHALL use the actual nightly rate
4. IF real pricing data is unavailable, THEN THE Pricing_Display SHALL display an intelligent estimate based on the selected price range tier ($80 for budget, $150 for mid-range, $250 for premium)

### Requirement 6: Restaurant Pricing Display

**User Story:** As a traveler, I want to see numeric restaurant pricing so that I can understand meal costs at a glance.

#### Acceptance Criteria

1. THE Pricing_Display SHALL show restaurant prices in the format "$XX–$XX per person" where XX values represent a numeric price range
2. THE Pricing_Display SHALL NOT display standalone dollar-sign symbols ($, $$, $$$) for restaurant pricing
3. WHEN priceRangeMin and priceRangeMax data is available from the Place_Service, THE Pricing_Display SHALL use those actual values
4. IF price range data is unavailable, THEN THE Pricing_Display SHALL display an intelligent estimate based on the restaurant price range tier ($10–$20 for budget, $20–$40 for mid-range, $40–$80 for premium)

### Requirement 7: Itinerary Auto-Optimization

**User Story:** As a traveler, I want my itinerary automatically optimized upon generation so that I do not need to manually optimize each day.

#### Acceptance Criteria

1. WHEN the Itinerary_Engine generates a new itinerary, THE Itinerary_View SHALL automatically apply the nearest-neighbor route optimization to each day containing 3 or more activities
2. THE Itinerary_View SHALL display microcopy text "Optimized for minimal travel time and best experience flow" at the top of the itinerary

### Requirement 8: Apple Maps Deep Link

**User Story:** As a traveler, I want to open my itinerary route in Apple Maps so that I can navigate between activities.

#### Acceptance Criteria

1. THE Itinerary_View SHALL display an "Open in Apple Maps" button for each day section
2. WHEN the user taps the "Open in Apple Maps" button, THE Orbi_App SHALL construct a deep link URL containing all activity coordinates for that day and open Apple Maps with the route

### Requirement 9: Itinerary Reasoning Section

**User Story:** As a traveler, I want to understand why my itinerary was planned a certain way so that I trust the recommendations.

#### Acceptance Criteria

1. THE Itinerary_View SHALL display a "Why This Plan" section containing 1 to 2 lines of reasoning text explaining the itinerary logic
2. THE Itinerary_Engine SHALL generate the reasoning text based on the selected vibe and optimization criteria (e.g., "Optimized for minimal travel time and top-rated foodie spots")

### Requirement 10: Bookmark Save UX

**User Story:** As a traveler, I want to save and unsave trips with a single tap on a bookmark icon so that saving feels instant and intuitive.

#### Acceptance Criteria

1. THE TripResultView SHALL display a bookmark icon in the top-right toolbar area replacing the current Save button and label
2. WHEN the user taps the Bookmark_Icon on an unsaved trip, THE Orbi_App SHALL save the trip, fill the bookmark icon, and provide subtle visual confirmation without displaying a modal dialog
3. WHEN the user taps the Bookmark_Icon on a saved trip, THE Orbi_App SHALL remove the trip from saved trips and return the bookmark icon to its unfilled state
4. THE Orbi_App SHALL persist the bookmark save state across app restarts by storing the saved trip ID
5. WHEN the TripResultView loads, THE Orbi_App SHALL check if the current trip destination and parameters match a previously saved trip and display the filled bookmark icon accordingly

### Requirement 11: Replace Item Logic Validation

**User Story:** As a traveler, I want replacement activities to be contextually relevant so that swapped items feel intentional and well-matched.

#### Acceptance Criteria

1. WHEN the user requests a replacement activity, THE Replace_Item_Service SHALL return an activity that matches the currently selected vibe
2. WHEN the user requests a replacement activity, THE Replace_Item_Service SHALL return an activity that fits within the same time slot (Morning, Afternoon, or Evening)
3. WHEN the user requests a replacement activity, THE Replace_Item_Service SHALL return an activity that is geographically nearby (within 60 minutes travel time) to adjacent activities in the same day
4. THE Replace_Item_Service SHALL include the geographic coordinates of adjacent activities in the replacement prompt to ensure proximity

### Requirement 12: Trips Tab Empty State

**User Story:** As a new user, I want to see a helpful empty state on the Trips tab so that I know how to get started.

#### Acceptance Criteria

1. WHILE the user has no saved trips, THE Trips_Tab SHALL display the text "No trips yet" with a call-to-action button labeled "Plan your first trip"
2. WHEN the user taps the "Plan your first trip" button, THE Orbi_App SHALL navigate the user to the Explore tab
3. WHILE the user has no saved trips, THE Trips_Tab SHALL display an example suggestion text (e.g., "Try a weekend in Atlanta") below the call-to-action
4. THE Trips_Tab SHALL NOT display a blank screen when no trips exist

### Requirement 13: Export Share Upgrade

**User Story:** As a traveler, I want to share a clean, readable trip summary so that recipients can easily understand my travel plan.

#### Acceptance Criteria

1. THE Export_Formatter SHALL produce output containing the trip title in the format "{numDays}-Day {destination} {vibe} Trip"
2. THE Export_Formatter SHALL include key activities listed by day with activity names and time slots
3. THE Export_Formatter SHALL include the total estimated cost at the bottom of the output
4. THE Export_Formatter SHALL format output as clean, human-readable plain text without JSON structures or code formatting
5. THE Export_Formatter SHALL include restaurant recommendations per day when available

### Requirement 14: Activity Confidence Tags

**User Story:** As a traveler, I want to see subtle confidence labels on itinerary items so that I can gauge the quality and character of each activity.

#### Acceptance Criteria

1. THE Itinerary_View SHALL display Activity_Tag labels on itinerary items where applicable, using tags such as "Popular", "Highly rated", "Hidden gem", and "Family-friendly"
2. WHEN the Family_Friendly_Toggle is enabled, THE Itinerary_View SHALL display the "Family-friendly" tag on activities identified as family-safe
3. THE Activity_Tag SHALL use minimal styling (small badge or caption-sized text) that does not clutter the itinerary layout
4. THE Itinerary_Engine SHALL include a confidence or category tag field in the activity slot response data

### Requirement 15: Loading Experience Upgrade

**User Story:** As a traveler, I want staged loading messages during itinerary generation so that I feel informed about the progress.

#### Acceptance Criteria

1. WHILE the itinerary is being generated, THE Loading_Overlay SHALL display staged messages in sequence: "Finding top spots…", "Optimizing your route…", "Finalizing your itinerary…"
2. THE Loading_Overlay SHALL transition between staged messages at intervals of approximately 3 seconds each
3. THE Loading_Overlay SHALL apply horizontal padding of at least 16 points to all text content to prevent text from touching screen edges
4. THE Loading_Overlay SHALL display text that is fully readable without truncation on all supported iPhone screen sizes

### Requirement 16: Haptics Integration

**User Story:** As a traveler, I want subtle haptic feedback on key interactions so that the app feels responsive and polished.

#### Acceptance Criteria

1. WHEN the Itinerary_Engine successfully generates an itinerary, THE Orbi_App SHALL trigger a UINotificationFeedbackGenerator success haptic
2. WHEN the user taps the Bookmark_Icon to save or remove a trip, THE Orbi_App SHALL trigger a UIImpactFeedbackGenerator with light intensity
3. WHEN the user replaces an itinerary item successfully, THE Orbi_App SHALL trigger a UIImpactFeedbackGenerator with light intensity
4. THE Orbi_App SHALL NOT trigger haptic feedback more than once per user-initiated action to avoid excessive or repetitive feedback

### Requirement 17: Cost Estimation Clarity

**User Story:** As a traveler, I want clear labeling on cost estimates so that I understand the numbers are approximations.

#### Acceptance Criteria

1. THE Cost_Breakdown_View SHALL display the label "Estimated total cost" above the total cost figure
2. THE Cost_Breakdown_View SHALL display a disclaimer text "Based on average prices" below the total cost section
3. THE Cost_Breakdown_View SHALL use the label "Estimated Total" consistently (not "Total" without qualification)


### Requirement 18: Globe Visual Enhancement (Brightness and Depth)

**User Story:** As a traveler, I want the globe on the Explore screen to feel illuminated and visually rich so that the map feels inviting rather than dark and flat.

#### Acceptance Criteria

1. THE Globe_Glow_Layer SHALL render a radial gradient halo behind the Globe_Map using diffused blue, purple, and teal tones with opacity no greater than 0.35
2. THE Globe_Glow_Layer SHALL remain visually consistent with the DesignTokens dark theme (backgroundPrimary and backgroundSecondary color palette)
3. THE Globe_Glow_Layer SHALL NOT produce harsh edges or overly bright regions that compete with map content or UI overlays
4. THE Globe_Map SHALL display faint static light-point overlays representing city locations at low opacity (no greater than 0.2) to add visual depth without cluttering the map surface
5. THE Orbi_App SHALL increase the landmass edge contrast on the Globe_Map by applying a subtle overlay or adjusted map styling that improves geographic feature visibility while preserving the satelliteFlyover aesthetic

### Requirement 19: Subtle Globe Motion

**User Story:** As a traveler, I want the globe to feel alive with gentle motion so that the Explore screen does not appear static or lifeless.

#### Acceptance Criteria

1. WHILE no user interaction is occurring on the Globe_Map, THE Globe_Rotation SHALL continuously animate the MKMapCamera heading at a rate no faster than 2 degrees per second
2. WHEN the user touches or drags the Globe_Map, THE Globe_Rotation SHALL pause immediately and resume 3 seconds after the last touch event ends
3. THE Globe_Rotation SHALL NOT cause visible jitter, frame drops, or increase CPU usage above baseline idle levels
4. THE Globe_Rotation SHALL NOT interfere with city annotation tap targets, zoom controls, or search interactions

### Requirement 20: Search Bar Visual Emphasis

**User Story:** As a traveler, I want the search bar to be the most prominent interactive element on the Explore screen so that I immediately know how to start planning.

#### Acceptance Criteria

1. THE Globe_Map container SHALL reduce its vertical size by 10 to 15 percent relative to the current layout to allocate more visual weight to the Search_Bar area
2. THE Search_Bar SHALL use a background opacity higher than the current glassmorphic surface (at least 0.15 compared to the current surfaceGlass value of 0.08) to increase contrast against the dark background
3. THE Search_Bar SHALL display a subtle shadow with blur radius between 6 and 10 points and opacity no greater than 0.3 to create visual elevation above the Globe_Map
4. THE Search_Bar SHALL remain the visually dominant interactive element on the Explore screen, positioned above the Globe_Map content

### Requirement 21: User Guidance Text

**User Story:** As a first-time user, I want a short guidance prompt above the search bar so that I understand what action to take on the Explore screen.

#### Acceptance Criteria

1. THE Guidance_Text SHALL display a single line of text above the Search_Bar with content such as "Where do you want to go?" or "Search cities, countries, or experiences"
2. THE Guidance_Text SHALL use DesignTokens.textSecondary color and a font size no larger than subheadline weight to maintain subtle styling
3. THE Guidance_Text SHALL remain limited to one line and SHALL NOT wrap to multiple lines on any supported iPhone screen size
4. WHEN the Search_Bar text field receives focus, THE Guidance_Text SHALL fade out with an opacity animation duration of 0.2 seconds
5. WHEN the Search_Bar text field loses focus and the query is empty, THE Guidance_Text SHALL fade back in with an opacity animation duration of 0.2 seconds

### Requirement 22: Globe Tap Feedback

**User Story:** As a traveler, I want subtle visual feedback when I tap the globe so that the map feels interactive and responsive.

#### Acceptance Criteria

1. WHEN the user taps the Globe_Map background (not on a city annotation or UI control), THE Globe_Tap_Feedback SHALL display a circular ripple animation originating from the tap point
2. THE Globe_Tap_Feedback ripple SHALL expand from 0 to 80 points in diameter over 0.4 seconds and fade from 0.3 opacity to 0 opacity using DesignTokens.accentCyan color
3. THE Globe_Tap_Feedback SHALL complete within 0.5 seconds and SHALL NOT block or delay other touch interactions
4. THE Globe_Tap_Feedback SHALL NOT trigger when the user taps on a city annotation, cluster annotation, zoom control, filter pill, or overlay card
