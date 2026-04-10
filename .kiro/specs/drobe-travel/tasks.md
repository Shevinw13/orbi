# Implementation Plan: Orbi

## Overview

Full-stack implementation of the Orbi iOS app (SwiftUI + SceneKit) with a FastAPI Python backend, Supabase PostgreSQL, Upstash Redis caching, OpenAI itinerary generation, and Google Places integration. Tasks are ordered so each step builds on the previous, starting with backend infrastructure, then iOS client, then integration and wiring.

## Tasks

- [x] 1. Set up backend project structure and configuration
  - [x] 1.1 Initialize FastAPI project with directory structure, dependencies (fastapi, uvicorn, httpx, pyjwt, bcrypt, redis, supabase-py), and environment variable loading
    - Create `backend/` directory with `main.py`, `requirements.txt`, `.env.example`
    - Create sub-packages: `services/`, `models/`, `middleware/`, `routes/`
    - Configure environment variables for SUPABASE_URL, SUPABASE_KEY, UPSTASH_REDIS_URL, OPENAI_API_KEY, GOOGLE_PLACES_API_KEY, JWT_SECRET
    - _Requirements: 12.2_

  - [x] 1.2 Set up Supabase database schema and RLS policies
    - Create SQL migration file with `users`, `refresh_tokens`, `trips`, `shared_trips` tables per the design ERD
    - Apply RLS policies: users can only access their own rows, shared_trips readable by anyone
    - _Requirements: 12.3, 12.5, 12.6, 9.5_

  - [x] 1.3 Set up Upstash Redis connection utility
    - Create a Redis client wrapper using `redis-py` with Upstash connection string
    - Implement `get_cached`, `set_cached` helpers with TTL support
    - _Requirements: 13.1, 13.2, 13.3_

- [x] 2. Implement authentication service
  - [x] 2.1 Implement Auth_Service with Apple Sign-In and Google OAuth token validation
    - Validate Apple identity tokens against Apple's JWKS endpoint
    - Validate Google ID tokens against Google's tokeninfo endpoint
    - Create user record on first authentication
    - Issue JWT access token (15 min) and refresh token (30 days)
    - Store refresh token hashed with bcrypt (cost factor 10+)
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.7_

  - [x] 2.2 Implement JWT middleware and token refresh endpoint
    - Create `JWTAuthMiddleware` that validates Bearer tokens on all routes except `/auth/*` and `/share/*`
    - Implement `POST /auth/refresh` to issue new access tokens from valid refresh tokens
    - Return 401 for invalid/expired tokens
    - _Requirements: 11.5, 11.6, 12.1_

  - [x] 2.3 Implement rate limiting middleware
    - Create `RateLimitMiddleware` tracking requests per user_id in Redis
    - Enforce 100 requests/minute per authenticated user
    - Return 429 when limit exceeded
    - _Requirements: 12.4_

  - [ ]* 2.4 Write unit tests for Auth_Service and middleware
    - Test JWT generation and validation
    - Test token refresh flow
    - Test rate limiting counter logic
    - _Requirements: 11.1, 11.2, 11.3, 11.5, 11.6, 12.4_

- [x] 3. Implement Itinerary Engine
  - [x] 3.1 Implement Itinerary_Engine with OpenAI integration
    - Construct prompt from destination, days, vibe, and preferences
    - Parse structured JSON response into itinerary model
    - Validate geographic proximity (≤60 min travel between consecutive items)
    - Cache generated itineraries in Redis keyed by `(destination, days, vibe, preferences_hash)` with 24h TTL
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.7, 4.8, 13.4_

  - [x] 3.2 Implement replace-activity endpoint
    - `POST /trips/replace-item` calls OpenAI to generate an alternative activity for a specific time slot
    - Maintain context of existing activities to avoid duplicates
    - _Requirements: 5.5_

  - [x] 3.3 Implement error handling for OpenAI API failures
    - Return structured error response with descriptive message on API failure
    - _Requirements: 4.6, 14.2, 14.4_

  - [ ]* 3.4 Write unit tests for Itinerary_Engine
    - Test prompt construction
    - Test response parsing and validation
    - Test cache hit/miss behavior
    - Test error handling on API failure
    - _Requirements: 4.1, 4.2, 4.6, 13.4_

- [x] 4. Implement Place Service and Cost Estimator
  - [x] 4.1 Implement Place_Service with Google Places API integration
    - `GET /places/hotels` and `GET /places/restaurants` endpoints
    - Query by location, radius, type, price level; return top 3 sorted by rating
    - Track excluded place IDs per session for refresh functionality
    - Relax filters and indicate broadening if no results match
    - Cache responses in Redis with 24h TTL
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 13.1, 13.2, 13.3_

  - [x] 4.2 Implement Cost_Estimator module
    - Pure computation: hotel_cost = nightly_rate × num_days, food_cost = daily_estimate × num_days ($ = $30, $$ = $60, $$$ = $100), activity_cost = sum of individual costs
    - Return total and per-day breakdown
    - _Requirements: 8.1, 8.2, 8.3, 8.4_

  - [x] 4.3 Implement error handling for Places API failures
    - Return user-friendly error message with retry guidance
    - _Requirements: 14.1, 14.4_

  - [ ]* 4.4 Write unit tests for Place_Service and Cost_Estimator
    - Test cost calculation logic with various price ranges
    - Test filter relaxation behavior
    - Test cache integration
    - _Requirements: 7.1, 7.5, 8.1, 8.2, 8.3_

- [x] 5. Implement Trip CRUD and Share Service
  - [x] 5.1 Implement Trip CRUD endpoints
    - `POST /trips` (save), `GET /trips` (list), `GET /trips/{id}` (load), `DELETE /trips/{id}` (delete)
    - Enforce user ownership via JWT user_id matching; return 403 for unauthorized access
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 12.5_

  - [x] 5.2 Implement Share_Service
    - `POST /trips/{id}/share` generates UUID-based share link
    - `GET /share/{share_id}` returns read-only trip data without auth
    - Strip sensitive user data from shared responses
    - _Requirements: 10.1, 10.2, 10.3, 10.4_

  - [x] 5.3 Implement destination autocomplete endpoint
    - `GET /search/destinations` returns matching city suggestions
    - _Requirements: 2.2_

  - [ ]* 5.4 Write unit tests for Trip CRUD and Share_Service
    - Test ownership enforcement
    - Test share link generation and retrieval
    - Test read-only constraint on shared trips
    - _Requirements: 9.5, 10.1, 10.3, 10.4, 12.5_

- [x] 6. Checkpoint - Backend complete
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Set up iOS project structure
  - [x] 7.1 Create Xcode project with SwiftUI app lifecycle
    - Set up project with SwiftUI App entry point
    - Create folder structure: `Views/`, `Models/`, `Services/`, `Utilities/`
    - Add SceneKit and MapKit framework imports
    - _Requirements: 1.1_

  - [x] 7.2 Implement API client service
    - Create `APIClient` using `URLSession` async/await
    - Handle JWT token storage in Keychain, automatic token refresh on 401
    - Structured error handling with user-friendly messages
    - _Requirements: 11.5, 11.6, 14.3, 14.4_

  - [x] 7.3 Implement authentication views and flow
    - Apple Sign-In button using `AuthenticationServices` framework
    - Google Sign-In integration
    - Token persistence and auto-login on app launch
    - _Requirements: 11.1, 11.2, 11.3_

- [x] 8. Implement 3D Globe View
  - [x] 8.1 Create Globe_View with SceneKit
    - Render textured Earth sphere using `SCNSphere` with high-res Earth texture
    - Position camera for initial globe overview
    - Target 30+ FPS during interactions
    - _Requirements: 1.1, 15.1_

  - [x] 8.2 Implement globe gesture handling
    - Pan gesture → rotate `SCNNode` smoothly
    - Pinch gesture → adjust camera distance with smooth animation
    - Animation lock flag to disable taps during zoom transitions
    - _Requirements: 1.2, 1.3, 1.5_

  - [x] 8.3 Implement city markers and tap detection
    - Render city markers as `SCNNode` children positioned via lat/lng → 3D coordinate conversion
    - Tap detection via `SCNHitTestResult` to identify tapped markers
    - Animate smooth zoom into tapped location and open destination selection flow
    - _Requirements: 1.4, 1.5_

  - [ ]* 8.4 Write unit tests for coordinate conversion and gesture state
    - Test lat/lng to 3D coordinate conversion accuracy
    - Test animation lock flag behavior
    - _Requirements: 1.2, 1.4, 1.5_

- [x] 9. Implement Trip Planner and Search
  - [x] 9.1 Create search bar with debounced autocomplete
    - Overlay search bar on Globe_View
    - Debounce input at 300ms, trigger autocomplete after 2+ characters
    - Display suggestions list; show "No destinations found" on empty results
    - On selection, animate globe to city and open destination flow
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [x] 9.2 Create Trip Preferences form
    - SwiftUI form collecting: days (1–14), hotel price range, hotel vibe, restaurant price range, cuisine type, vibe selection
    - Validate days as integer 1–14; show validation error on invalid input
    - Submit preferences to API_Gateway; show loading indicator with progress feedback
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 15.2, 15.3_

  - [ ]* 9.3 Write unit tests for preferences validation
    - Test days range validation (boundary: 0, 1, 14, 15)
    - Test debounce timing
    - _Requirements: 3.2, 3.3, 2.2_

- [x] 10. Implement Itinerary View
  - [x] 10.1 Create Itinerary_View with day-grouped timeline
    - Vertical ScrollView with LazyVStack grouped by day sections
    - Render within 500ms of data receipt
    - _Requirements: 5.1, 15.4_

  - [x] 10.2 Implement item detail view
    - Sheet presentation with activity name, description, map snippet, estimated duration
    - _Requirements: 5.2_

  - [x] 10.3 Implement drag-and-drop reordering
    - `.onDrag` / `.onDrop` modifiers for within-day reordering
    - Cross-day movement via drop target detection on day section headers
    - _Requirements: 5.3, 5.4_

  - [x] 10.4 Implement Replace, Add, and Remove actions
    - Replace: call backend replace-item endpoint and swap activity
    - Add: allow custom activity entry for a day
    - Remove: delete item from day
    - Trigger cost recalculation on any modification
    - _Requirements: 5.5, 5.6, 5.7, 8.5_

  - [ ]* 10.5 Write unit tests for itinerary manipulation
    - Test reorder logic
    - Test add/remove operations
    - _Requirements: 5.3, 5.6, 5.7_

- [x] 11. Implement Map Route View
  - [x] 11.1 Create Map_Route_View with MapKit
    - Display activity pins for selected day using `Map` view with `Annotation`
    - Draw route polylines between consecutive stops using `MKDirections`
    - Show walking/driving time and distance per segment
    - Pin tap displays activity name and scheduled time
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

- [x] 12. Implement Hotel/Restaurant Recommendations and Cost Display
  - [x] 12.1 Create hotel and restaurant recommendation views
    - Display top 3 hotels and top 3 restaurants with name, rating, price level, image
    - Refresh button to load next 3 options excluding previously shown
    - Show indication when filters were broadened
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

  - [x] 12.2 Create cost breakdown display
    - Show total estimated trip cost and per-day breakdown
    - Auto-recalculate when itinerary or hotel selection changes
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

- [x] 13. Implement Save and Share Features
  - [x] 13.1 Implement Save Trip flow
    - "Save Trip" button persists trip with destination, preferences, hotel, restaurants, itinerary, vibe
    - "My Trips" screen lists saved trips
    - Load full itinerary, map routes, and places on trip selection
    - Delete trip with confirmation
    - _Requirements: 9.1, 9.2, 9.3, 9.4_

  - [x] 13.2 Implement Share Trip flow
    - "Share Trip" button generates and copies share link
    - Handle incoming deep links to display read-only itinerary view
    - _Requirements: 10.1, 10.2, 10.3, 10.4_

- [x] 14. Implement offline handling and error resilience on iOS
  - [x] 14.1 Add network connectivity monitoring and retry logic
    - Display offline indicator when network is unavailable
    - Auto-retry failed requests when connectivity is restored
    - Show retry option on Places API and OpenAI API errors
    - _Requirements: 14.1, 14.2, 14.3_

- [x] 15. Checkpoint - Full integration
  - Ensure all tests pass, ask the user if questions arise.

- [x] 16. Final wiring and end-to-end validation
  - [x] 16.1 Wire all iOS views into navigation flow
    - Connect Globe_View → Search → Preferences → Itinerary_View → Map_Route_View → Save/Share
    - Ensure tab bar or navigation stack handles My Trips, Globe, and Settings
    - _Requirements: 1.1, 1.4, 2.3, 3.5_

  - [ ]* 16.2 Write integration tests for critical flows
    - Test auth → generate itinerary → save trip → load trip flow
    - Test share link generation and read-only access
    - _Requirements: 9.1, 9.3, 10.1, 10.2, 11.1, 11.3_

- [x] 17. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Backend tasks (1–6) should be completed before iOS client tasks (7–14) to enable integration testing
- All infrastructure uses free-tier services: Supabase, Upstash Redis, Render/Railway for hosting
