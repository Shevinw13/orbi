# Requirements Document

## Introduction

This specification defines the comprehensive UI redesign of the Orbi iOS travel planning app. The redesign transforms the existing SwiftUI views to match professional mockups featuring a globe-first interface, dark space aesthetic, glassmorphism overlays, progressive disclosure via bottom sheets, and premium motion design. All backend functionality is already implemented; this spec covers only the iOS UI/UX layer.

## Glossary

- **Globe_View**: The fullscreen interactive 3D Earth rendered via SceneKit, serving as the primary surface of the app
- **Search_Bar**: The floating search input overlay positioned in the top safe area above the globe
- **City_Pin**: A minimal glowing dot rendered on the globe surface representing a selectable city
- **Bottom_Sheet**: A rounded-corner overlay that slides up from the bottom of the screen using progressive disclosure
- **City_Card**: The collapsed bottom sheet (30% height) showing city summary after a city is selected
- **Preferences_Sheet**: The expanded bottom sheet (80% height) for configuring trip parameters before generation
- **Generating_Overlay**: A translucent overlay displayed during itinerary generation with animated feedback
- **Trip_Overview**: The screen displaying a generated itinerary with day selector and activity cards
- **Map_Route_View**: The fullscreen MapKit view showing route polylines and numbered stop markers
- **Recommendations_View**: The tabbed view displaying hotel and restaurant recommendations
- **Saved_Trips_View**: The screen listing previously saved trips in a grid or list layout
- **Tab_Bar**: The floating semi-transparent bottom navigation bar with three tabs (Explore, Trips, Profile)
- **Vibe_Pill**: A capsule-shaped toggle button used for selecting trip vibes (Foodie, Adventure, Relaxed, Nightlife)
- **Glassmorphism**: A visual style combining background blur and translucency for overlay elements
- **Day_Selector**: A horizontal scrollable row of day buttons for navigating between itinerary days
- **Activity_Card**: A vertical list item displaying an activity with image, title, rating, and description

## Requirements

### Requirement 1: Dark Space Theme and Global Design Tokens

**User Story:** As a user, I want the app to have a consistent dark space aesthetic with premium visual styling, so that the experience feels polished and immersive.

#### Acceptance Criteria

1. THE Globe_View SHALL render a dark space gradient background with star particles behind the 3D Earth
2. THE Globe_View SHALL use rounded corners of 16 to 24 points on all card and overlay surfaces throughout the app
3. WHEN an overlay is displayed, THE Globe_View SHALL apply glassmorphism styling using UIBlurEffect with translucency to the overlay background
4. THE Globe_View SHALL use a dark color scheme as the default appearance for all screens
5. THE Tab_Bar SHALL use a semi-transparent background with blur effect consistent with the glassmorphism design language

### Requirement 2: Globe Home Screen Layout

**User Story:** As a user, I want the home screen to be dominated by an interactive 3D globe, so that I can explore destinations visually.

#### Acceptance Criteria

1. THE Globe_View SHALL occupy approximately 90% of the screen area on the home screen
2. THE Search_Bar SHALL float in the top safe area with a height of approximately 44 points, a blur background, and placeholder text "Search destinations…"
3. WHEN the user taps the Search_Bar, THE Search_Bar SHALL open a search modal with autocomplete enabled
4. THE Tab_Bar SHALL float at the bottom of the screen with a height of approximately 70 points, displaying exactly three tabs: Explore (active by default), Trips, and Profile
5. THE Tab_Bar SHALL display icons with small text labels for each tab

### Requirement 3: Globe Interaction and City Selection

**User Story:** As a user, I want to interact with the globe using natural gestures, so that I can explore and select destinations intuitively.

#### Acceptance Criteria

1. THE Globe_View SHALL support drag-to-rotate with inertia, applying smooth deceleration after the user releases a spin gesture
2. THE Globe_View SHALL support pinch-to-zoom between defined minimum and maximum zoom levels
3. WHEN the user taps on the globe surface, THE Globe_View SHALL select the nearest city and trigger a snap-to-city animation
4. WHEN a city is selected via tap, THE Globe_View SHALL provide haptic feedback using UIImpactFeedbackGenerator
5. THE Globe_View SHALL render realistic satellite-style textures on the Earth surface with lighting that reacts to globe rotation
6. THE Globe_View SHALL use ease-in-out or spring animation curves for all globe transitions with a duration between 0.8 and 1.5 seconds

### Requirement 4: City Pin Display

**User Story:** As a user, I want to see city markers on the globe, so that I can identify available destinations.

#### Acceptance Criteria

1. THE City_Pin SHALL render as a minimal glowing dot on the globe surface
2. WHEN the user zooms in slightly, THE City_Pin SHALL become visible with a fade-in transition
3. WHEN the user taps a City_Pin, THE City_Pin SHALL animate a scale-up effect and trigger the City_Card bottom sheet

### Requirement 5: City Selected Bottom Sheet (Collapsed)

**User Story:** As a user, I want to see a summary of a selected city in a compact bottom sheet, so that I can quickly decide whether to plan a trip there.

#### Acceptance Criteria

1. WHEN the user taps a city on the globe, THE Bottom_Sheet SHALL slide up from the bottom to approximately 30% of the screen height
2. WHEN the City_Card appears, THE Globe_View SHALL zoom slightly into the selected city location
3. THE City_Card SHALL display the city name, country, rating, and a hero image preview
4. THE City_Card SHALL include a "Plan Trip" call-to-action button
5. THE City_Card SHALL have rounded top corners, a blur background, and a slight shadow
6. WHEN the user taps outside the City_Card or swipes it down, THE City_Card SHALL dismiss and the globe SHALL return to its previous zoom level

### Requirement 6: Plan Trip Preferences Sheet (Expanded)

**User Story:** As a user, I want to configure my trip preferences in an expanded bottom sheet, so that I can customize the itinerary generation.

#### Acceptance Criteria

1. WHEN the user taps "Plan Trip" on the City_Card, THE Preferences_Sheet SHALL expand the bottom sheet to approximately 80% of the screen height
2. THE Preferences_Sheet SHALL display a trip length selector supporting values from 1 to 14 days using a stepper or horizontal picker
3. THE Preferences_Sheet SHALL display hotel preference controls using a segmented control or slider with options $, $$, $$$, and $$$$
4. THE Preferences_Sheet SHALL display Vibe_Pill buttons for Foodie, Adventure, Relaxed, and Nightlife options
5. WHEN a Vibe_Pill is selected, THE Vibe_Pill SHALL display a filled gradient style; WHEN unselected, THE Vibe_Pill SHALL display an outline style
6. THE Preferences_Sheet SHALL display a full-width "Generate Itinerary" button with a blue-to-green gradient background
7. THE Preferences_Sheet SHALL use spring animation with a response of 0.3 to 0.5 seconds when expanding from the collapsed City_Card state

### Requirement 7: Generating State Overlay

**User Story:** As a user, I want visual feedback while my itinerary is being generated, so that I know the app is working.

#### Acceptance Criteria

1. WHILE the itinerary is being generated, THE Generating_Overlay SHALL display centered text "Generating your itinerary…" over the globe
2. WHILE the itinerary is being generated, THE Generating_Overlay SHALL display a subtle glow pulse animation
3. WHILE the itinerary is being generated, THE Globe_View SHALL remain visible in the background behind the overlay
4. THE Generating_Overlay SHALL use a translucent dark background consistent with the glassmorphism design language

### Requirement 8: Trip Overview Screen

**User Story:** As a user, I want to view my generated itinerary organized by day with activity details, so that I can review and navigate my trip plan.

#### Acceptance Criteria

1. THE Trip_Overview SHALL display a header containing the trip name (e.g., "Paris Trip") and trip dates
2. THE Day_Selector SHALL render as a horizontal scrollable row of day buttons (Day 1, Day 2, etc.)
3. WHEN the user taps a day in the Day_Selector, THE Trip_Overview SHALL display the activities for that selected day
4. THE Activity_Card SHALL display each activity in a vertical list with an image, title, rating, and short description
5. THE Activity_Card SHALL include an inline mini map showing the route to the next stop
6. THE Trip_Overview SHALL use the dark theme with rounded card corners of 16 to 24 points consistent with the global design tokens

### Requirement 9: Map Route View

**User Story:** As a user, I want to see all my daily stops on a fullscreen map with routes connecting them, so that I can understand the geography of my itinerary.

#### Acceptance Criteria

1. THE Map_Route_View SHALL display a fullscreen MapKit view
2. THE Map_Route_View SHALL render a route polyline in blue or gradient style connecting all stops in order
3. THE Map_Route_View SHALL display numbered markers (1, 2, 3…) at each stop location
4. WHEN the user taps a numbered marker, THE Map_Route_View SHALL open a place detail view for that stop
5. THE Map_Route_View SHALL display a Route Summary Card at the bottom showing total distance and total time
6. THE Map_Route_View SHALL include a scrollable stop list displaying place name, rating, and distance to the next stop

### Requirement 10: Hotels and Restaurants View

**User Story:** As a user, I want to browse hotel and restaurant recommendations in a tabbed interface, so that I can find places that match my preferences.

#### Acceptance Criteria

1. THE Recommendations_View SHALL display tabs labeled Itinerary, Hotels, and Restaurants
2. THE Recommendations_View SHALL display each list item with an image, name, rating, and price level
3. THE Recommendations_View SHALL include a "Refresh" button that fetches the next 3 options when tapped
4. THE Recommendations_View SHALL use the dark theme with glassmorphism-styled tab bar and card backgrounds consistent with the global design tokens

### Requirement 11: Saved Trips Screen

**User Story:** As a user, I want to view my saved trips in an organized layout, so that I can quickly find and revisit past trip plans.

#### Acceptance Criteria

1. THE Saved_Trips_View SHALL display saved trips in a grid or list layout
2. THE Saved_Trips_View SHALL display each trip item with a city image, trip name, and dates
3. THE Saved_Trips_View SHALL use the dark theme with rounded card corners consistent with the global design tokens
4. WHEN the user taps a saved trip, THE Saved_Trips_View SHALL navigate to the Trip_Overview for that trip

### Requirement 12: Premium Motion and Animation

**User Story:** As a user, I want smooth, premium-feeling animations throughout the app, so that interactions feel responsive and polished.

#### Acceptance Criteria

1. THE Globe_View SHALL apply ease-in-out or spring timing curves to all animated transitions
2. WHEN a Bottom_Sheet slides up or expands, THE Bottom_Sheet SHALL use a spring animation with damping fraction between 0.7 and 0.9
3. WHEN the globe rotates via drag gesture, THE Globe_View SHALL apply inertia-based deceleration after the gesture ends
4. WHEN a City_Pin is tapped, THE City_Pin SHALL animate with a scale-up spring effect before triggering the bottom sheet
5. THE Generating_Overlay SHALL use a repeating glow pulse animation with ease-in-out timing

### Requirement 13: Floating Tab Bar Redesign

**User Story:** As a user, I want a minimal floating navigation bar, so that the globe remains the primary visual focus.

#### Acceptance Criteria

1. THE Tab_Bar SHALL render as a floating element with rounded corners, positioned above the bottom safe area
2. THE Tab_Bar SHALL use a semi-transparent background with blur effect
3. THE Tab_Bar SHALL display exactly three tabs: Explore, Trips, and Profile with icons and small labels
4. WHEN a tab is selected, THE Tab_Bar SHALL highlight the selected tab with the app accent color
5. THE Tab_Bar SHALL have a height of approximately 70 points
