# Implementation Plan: UI Redesign

## Overview

Transform the Orbi iOS app from its current light-themed UI to a premium dark-space aesthetic with glassmorphism, floating tab bar, and progressive-disclosure bottom sheets. Foundational utilities are built first, then the globe/home screen, overlay sheets, and finally the inner screens.

## Tasks

- [x] 1. Create foundational design tokens and glassmorphic modifier
  - [x] 1.1 Create `Utilities/DesignTokens.swift`
    - Define the `DesignTokens` enum with all color constants (`backgroundPrimary`, `backgroundSecondary`, `surfaceGlass`, `surfaceGlassBorder`, `accentCyan`, `accentBlue`, `accentGradient`, `textPrimary`, `textSecondary`, `textTertiary`)
    - Define spacing constants (`spacingXS` through `spacingXL`)
    - Define corner radii (`radiusSM` 12, `radiusMD` 16, `radiusLG` 24, `radiusXL` 28)
    - Define animation curves (`sheetSpring`, `globeTransition`, `pinScale`)
    - Define size constants (`tabBarHeight` 70, `searchBarHeight` 44, `cityCardFraction` 0.30, `preferencesSheetFraction` 0.80)
    - _Requirements: 1.2, 1.4, 1.5, 12.1, 12.2_

  - [x] 1.2 Create `Utilities/GlassmorphicModifier.swift`
    - Implement `GlassmorphicModifier` ViewModifier applying `.ultraThinMaterial` + `surfaceGlass` background + clipped rounded rect + `surfaceGlassBorder` stroke
    - Add `View.glassmorphic(cornerRadius:)` extension method with default `radiusLG`
    - _Requirements: 1.3, 1.5_

  - [ ]* 1.3 Write unit tests for DesignTokens
    - Assert token values are within expected ranges (radii 12–28, animation durations 0.3–1.5s, tab bar height 70, search bar height 44)
    - _Requirements: 1.2, 1.4_

- [x] 2. Checkpoint
  - Ensure all tests pass, ask the user if questions arise.

- [x] 3. Redesign GlobeView.swift — dark space background, star particles, and city pins
  - [x] 3.1 Add star particle layer to `GlobeScene.create()`
    - Create a `SCNNode` with small white sphere geometries (or a particle system) at random positions behind the earth to simulate a star field
    - Increase earth emission intensity slightly for a brighter, richer look
    - _Requirements: 1.1, 3.5_

  - [x] 3.2 Restyle city pin markers to glowing cyan dots
    - Change pin material `diffuse` and `emission` to `DesignTokens.accentCyan` UIColor equivalent
    - Add fade-in visibility based on camera zoom level (hidden when `camera.position.z > 3.0`, visible when closer)
    - _Requirements: 4.1, 4.2_

  - [x] 3.3 Add pin tap scale-up animation and haptic feedback
    - In `handleTap`, animate the tapped pin node with a scale-up spring effect (`DesignTokens.pinScale`) before triggering city selection
    - Add `UIImpactFeedbackGenerator(style: .medium).impactOccurred()` on pin tap
    - _Requirements: 3.4, 4.3, 12.4_

  - [x] 3.4 Update snap-to-city animation timing
    - Change `animateZoomToCity` to use `DesignTokens.globeTransition` duration (1.2s ease-in-out)
    - Ensure drag-to-rotate applies inertia-based deceleration after gesture ends
    - _Requirements: 3.1, 3.3, 3.6, 12.3_

  - [x] 3.5 Restyle 2D city label overlays with glassmorphic pill background
    - Replace plain text shadow labels with a small pill-shaped container using blur + translucent fill matching the glassmorphism style
    - _Requirements: 4.1, 1.3_

- [x] 4. Redesign ContentView.swift — floating tab bar
  - [x] 4.1 Replace standard `TabView` with custom `ZStack`-based layout
    - Render selected tab content fullscreen
    - Add `FloatingTabBar` private struct with 3 tab buttons (Explore globe icon, Trips suitcase icon, Profile person icon) with small text labels
    - Apply `.glassmorphic(cornerRadius: DesignTokens.radiusXL)` to the tab bar
    - Set tab bar height to `DesignTokens.tabBarHeight` (70pt), padded from bottom safe area
    - Highlight selected tab with `DesignTokens.accentCyan`
    - Add `.preferredColorScheme(.dark)` to the root view
    - _Requirements: 2.4, 2.5, 13.1, 13.2, 13.3, 13.4, 13.5, 1.4_

- [x] 5. Redesign ContentView.swift — CityCardView bottom sheet (~30%)
  - [x] 5.1 Restyle CityCardView with glassmorphic dark theme
    - Replace `.fill(.white)` background with `.glassmorphic()` modifier
    - Update all text colors to `DesignTokens.textPrimary` / `.textSecondary`
    - Update "Plan Trip" button to use `DesignTokens.accentGradient`
    - Add hero image placeholder (gradient or city image)
    - Add rating display and country label
    - Use `DesignTokens.radiusXL` for rounded top corners
    - Apply dark shadow `Color.black.opacity(0.4)`
    - Animate slide-up with `DesignTokens.sheetSpring`
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 12.2_

- [x] 6. Redesign ContentView.swift — PreferencesOverlay bottom sheet (~80%)
  - [x] 6.1 Restyle PreferencesOverlay with glassmorphic dark theme
    - Apply `.glassmorphic(cornerRadius: DesignTokens.radiusXL)` background
    - Restyle vibe pills: selected uses `DesignTokens.accentGradient` fill, unselected uses outline with `surfaceGlassBorder`
    - Dark-style trip length and hotel preference controls
    - "Generate Itinerary" button with full-width `DesignTokens.accentGradient`
    - Spring animation from collapsed to expanded using `DesignTokens.sheetSpring`
    - All text white/secondary white
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 12.2_

- [x] 7. Redesign ContentView.swift — GeneratingOverlay
  - [x] 7.1 Restyle GeneratingOverlay with translucent dark background and glow pulse
    - Background: `Color.black.opacity(0.5)` so globe remains visible
    - Center content: city name + "Generating your itinerary…" text in white
    - Add pulsing glow effect: `Circle` with cyan radial gradient, opacity animating 0.3↔0.8 on repeat with `.easeInOut`
    - Cyan-tinted `ProgressView`
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 12.5_

- [x] 8. Checkpoint
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Redesign SearchBarView.swift — floating glassmorphic search
  - [x] 9.1 Restyle search bar and suggestions dropdown
    - Apply `.glassmorphic(cornerRadius: DesignTokens.radiusMD)` to the search bar background
    - Set height to `DesignTokens.searchBarHeight` (44pt)
    - Placeholder text "Search destinations…" in `DesignTokens.textTertiary`
    - Icons white with 0.6 opacity
    - Suggestions dropdown: `.glassmorphic()` background with dark-themed rows
    - _Requirements: 2.1, 2.2, 2.3_

- [x] 10. Redesign ItineraryView.swift and TripResultView.swift — trip overview
  - [x] 10.1 Apply dark theme to TripResultView
    - Set background to `DesignTokens.backgroundPrimary`
    - Restyle tab picker with glassmorphic segmented control
    - Header: trip name + dates in `DesignTokens.textPrimary`
    - _Requirements: 8.1, 8.6_

  - [x] 10.2 Add horizontal day selector to ItineraryView / InlineDaySectionView
    - Implement horizontal `ScrollView` of pill buttons for day navigation
    - Selected day uses `DesignTokens.accentGradient` fill; unselected uses glass outline
    - _Requirements: 8.2, 8.3_

  - [x] 10.3 Restyle activity cards with dark glassmorphic styling
    - Each activity card uses `.glassmorphic(cornerRadius: DesignTokens.radiusMD)`
    - Display image thumbnail, title, rating stars, description
    - Keep timeline dot + line pattern with cyan/blue/purple for time slots
    - _Requirements: 8.4, 8.5, 8.6_

- [x] 11. Redesign MapRouteView.swift — gradient polyline, numbered markers, route summary
  - [x] 11.1 Update polyline to blue/gradient style and add numbered markers
    - Change polyline renderer stroke color to `DesignTokens.accentBlue` (or gradient if using `MKGradientPolylineRenderer`)
    - Replace default `MKMarkerAnnotationView` with custom numbered circle annotation views (1, 2, 3…)
    - _Requirements: 9.2, 9.3_

  - [x] 11.2 Add glassmorphic route summary card and stop list
    - Add a glassmorphic card at the bottom showing total distance + total time
    - Add scrollable horizontal stop list showing place name, rating, distance to next
    - _Requirements: 9.4, 9.5, 9.6_

- [x] 12. Redesign RecommendationsView.swift — glassmorphic tabs and cards
  - [x] 12.1 Restyle recommendations with dark glassmorphic theme
    - Tab bar: glassmorphic segmented control with "Itinerary", "Hotels", "Restaurants" labels
    - Place cards: dark glassmorphic cards with image, name, rating, price level
    - Refresh button: styled with glass background
    - All text white primary/secondary
    - _Requirements: 10.1, 10.2, 10.3, 10.4_

- [x] 13. Redesign SavedTripsView.swift — dark grid layout
  - [x] 13.1 Restyle saved trips with dark grid layout
    - Replace `List` with 2-column `LazyVGrid` using glassmorphic cards
    - Each card: city image placeholder (gradient), trip name, dates
    - Background: `DesignTokens.backgroundPrimary`
    - Card corners: `DesignTokens.radiusMD`
    - Tap navigates to Trip Overview
    - _Requirements: 11.1, 11.2, 11.3, 11.4_

- [x] 14. Redesign LoginView.swift — cyan accent update
  - [x] 14.1 Update LoginView accent from orange to cyan
    - Change radial glow from orange to cyan
    - Update globe icon gradient to cyan
    - Add glassmorphic outline style to sign-in buttons
    - Keep existing dark background
    - _Requirements: 1.4_

- [x] 15. Final checkpoint
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- No backend or data model changes are needed — this is purely a view-layer redesign
- All existing view models, API integrations, and navigation patterns are preserved
