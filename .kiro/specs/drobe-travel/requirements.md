# Requirements Document

## Introduction

Orbi is a production-ready iOS mobile application for visually immersive travel planning. Users explore destinations via a 3D interactive globe, generate AI-powered itineraries, and discover hotels and restaurants tailored to their preferences. The app uses SwiftUI with SceneKit for the globe, a FastAPI backend hosted on free-tier infrastructure, Supabase (PostgreSQL) for persistence, and OpenAI for itinerary generation. All tooling must be free or free-tier.

## Glossary

- **Globe_View**: The 3D interactive globe rendered via SceneKit that serves as the primary home screen interface.
- **Itinerary_Engine**: The backend service that orchestrates calls to the OpenAI API to generate structured day-by-day travel itineraries.
- **Trip_Planner**: The iOS client module responsible for collecting user preferences (days, hotel filters, restaurant filters, vibe) and submitting them to the backend.
- **Map_Route_View**: The MapKit-based view that displays optimized daily routes between itinerary stops.
- **Place_Service**: The backend service that queries external places APIs (Google Places or free alternative) for hotel, restaurant, and attraction data.
- **Auth_Service**: The backend service handling user authentication via Apple Sign-In, Google OAuth, and JWT token management.
- **Cost_Estimator**: The module that calculates estimated trip costs based on hotel rates, food costs, and activity prices.
- **Cache_Layer**: The Redis-based (Upstash free tier) caching layer that stores repeated API responses to minimize external API calls.
- **Itinerary_View**: The timeline-based UI component that displays a day-by-day itinerary with clickable, editable, and reorderable items.
- **Share_Service**: The service that generates shareable deep links to read-only itinerary views.
- **API_Gateway**: The FastAPI backend that mediates all client-server communication, enforces authentication, and applies rate limiting.
- **User**: A person who has authenticated with the app via Apple Sign-In, Google OAuth, or email.
- **Trip**: A saved travel plan consisting of a destination, preferences, vibe, and generated itinerary.
- **Vibe**: A trip style category (Foodie, Adventure, Relaxed, Nightlife) that influences activity selection and pacing.
- **RLS**: Row-Level Security, a Supabase/PostgreSQL feature ensuring users can only access their own data rows.

## Requirements

### Requirement 1: 3D Globe Interface

**User Story:** As a User, I want to explore destinations on an interactive 3D globe, so that I can visually discover and select travel destinations.

#### Acceptance Criteria

1. THE Globe_View SHALL render a textured 3D Earth globe using SceneKit as the primary home screen.
2. WHEN the User performs a pan gesture on the Globe_View, THE Globe_View SHALL rotate the globe smoothly in the direction of the gesture.
3. WHEN the User performs a pinch gesture on the Globe_View, THE Globe_View SHALL zoom in or out with smooth animation.
4. WHEN the User taps a city marker on the Globe_View, THE Globe_View SHALL animate a smooth zoom into that location and open the destination selection flow.
5. WHILE the Globe_View is animating a zoom transition, THE Globe_View SHALL disable additional tap interactions until the animation completes.

### Requirement 2: Destination Search

**User Story:** As a User, I want to search for destinations by name, so that I can quickly find a city without browsing the globe.

#### Acceptance Criteria

1. THE Trip_Planner SHALL display a search bar overlaying the Globe_View.
2. WHEN the User types at least 2 characters into the search bar, THE Trip_Planner SHALL display autocomplete suggestions within 300ms of the last keystroke.
3. WHEN the User selects an autocomplete suggestion, THE Globe_View SHALL animate to the selected city and open the destination selection flow.
4. IF no matching destinations are found for the search query, THEN THE Trip_Planner SHALL display a "No destinations found" message.

### Requirement 3: Trip Preferences Input

**User Story:** As a User, I want to specify my trip preferences, so that the generated itinerary matches my travel style and budget.

#### Acceptance Criteria

1. WHEN the User selects a destination, THE Trip_Planner SHALL present a preferences form collecting: number of days (1–14), hotel price range ($–$$$$), optional hotel vibe (luxury, boutique, budget), restaurant price range ($–$$$$), and optional cuisine type.
2. THE Trip_Planner SHALL validate that the number of days is an integer between 1 and 14 inclusive.
3. IF the User submits preferences with an invalid number of days, THEN THE Trip_Planner SHALL display a validation error and prevent submission.
4. WHEN the User selects a Vibe (Foodie, Adventure, Relaxed, Nightlife), THE Trip_Planner SHALL include the Vibe in the itinerary generation request.
5. WHEN the User submits valid preferences, THE Trip_Planner SHALL send the preferences to the API_Gateway for itinerary generation.

### Requirement 4: Itinerary Generation

**User Story:** As a User, I want an AI-generated day-by-day itinerary, so that I have a structured travel plan without manual research.

#### Acceptance Criteria

1. WHEN the API_Gateway receives a valid itinerary generation request, THE Itinerary_Engine SHALL call the OpenAI API with the destination, number of days, vibe, and preferences to generate a structured itinerary.
2. THE Itinerary_Engine SHALL return an itinerary structured as an array of days, where each day contains Morning, Afternoon, Evening time slots and an optional restaurant recommendation.
3. THE Itinerary_Engine SHALL generate activities that are geographically optimized to minimize travel time between consecutive stops within each day.
4. THE Itinerary_Engine SHALL include a mix of top attractions and local experiences in the generated itinerary.
5. WHEN a Vibe is specified, THE Itinerary_Engine SHALL tailor activity selection, restaurant choices, and daily pacing to match the selected Vibe.
6. IF the OpenAI API call fails, THEN THE Itinerary_Engine SHALL return an error response with a descriptive message and the Trip_Planner SHALL display a user-friendly fallback message.
7. THE Itinerary_Engine SHALL include estimated travel time in minutes between consecutive itinerary items within each day.
8. THE Itinerary_Engine SHALL avoid generating schedules where consecutive activities require more than 60 minutes of travel time between them.

### Requirement 5: Interactive Itinerary View

**User Story:** As a User, I want to view and interact with my itinerary in a timeline format, so that I can review and customize my travel plan.

#### Acceptance Criteria

1. THE Itinerary_View SHALL display the generated itinerary as a vertical timeline grouped by day.
2. WHEN the User taps an itinerary item, THE Itinerary_View SHALL open a detail view showing the activity name, description, location on a map, and estimated duration.
3. WHEN the User long-presses and drags an itinerary item, THE Itinerary_View SHALL allow reordering of items within the same day using smooth drag-and-drop animation.
4. WHEN the User drags an itinerary item to a different day section, THE Itinerary_View SHALL move that item to the target day.
5. WHEN the User taps a "Replace" action on an itinerary item, THE Itinerary_Engine SHALL generate an alternative activity for that time slot.
6. WHEN the User taps an "Add" action on a day, THE Itinerary_View SHALL allow the User to add a custom activity to that day.
7. WHEN the User taps a "Remove" action on an itinerary item, THE Itinerary_View SHALL remove that item from the day.

### Requirement 6: Map Route Mode

**User Story:** As a User, I want to see my daily itinerary plotted on a map with routes, so that I can visualize travel paths and distances.

#### Acceptance Criteria

1. WHEN the User selects a day from the itinerary, THE Map_Route_View SHALL display all activities for that day as pins on an Apple MapKit map.
2. THE Map_Route_View SHALL draw an optimized route path connecting the day's activities in chronological order.
3. THE Map_Route_View SHALL display estimated walking or driving time and distance between each consecutive pair of stops.
4. WHEN the User taps a pin on the Map_Route_View, THE Map_Route_View SHALL display the activity name and scheduled time.

### Requirement 7: Hotel and Restaurant Recommendations

**User Story:** As a User, I want to see curated hotel and restaurant recommendations based on my preferences, so that I can choose where to stay and eat.

#### Acceptance Criteria

1. WHEN the User's preferences are submitted, THE Place_Service SHALL query the external places API and return the top 3 hotels matching the User's price range and optional vibe filter.
2. WHEN the User's preferences are submitted, THE Place_Service SHALL query the external places API and return the top 3 restaurants matching the User's price range and optional cuisine filter.
3. THE Place_Service SHALL return each recommendation with: name, rating, price level, and an image URL.
4. WHEN the User taps a "Refresh" button on the hotel or restaurant list, THE Place_Service SHALL return the next best 3 options excluding previously shown results.
5. IF the external places API returns no results matching the filters, THEN THE Place_Service SHALL return results with relaxed filters and indicate that filters were broadened.

### Requirement 8: Trip Cost Estimator

**User Story:** As a User, I want to see an estimated total trip cost, so that I can budget my travel expenses.

#### Acceptance Criteria

1. WHEN an itinerary is generated and a hotel is selected, THE Cost_Estimator SHALL calculate the estimated hotel cost as the nightly rate multiplied by the number of days.
2. THE Cost_Estimator SHALL estimate daily food cost based on the selected restaurant price range.
3. THE Cost_Estimator SHALL estimate activity costs based on available pricing data for each itinerary item.
4. THE Cost_Estimator SHALL display a total estimated trip cost and a per-day cost breakdown.
5. WHEN the User modifies the itinerary or changes hotel selection, THE Cost_Estimator SHALL recalculate and update the cost estimate.

### Requirement 9: Save Itineraries

**User Story:** As a User, I want to save my trip itineraries, so that I can access them later.

#### Acceptance Criteria

1. WHEN the User taps "Save Trip," THE Trip_Planner SHALL persist the trip to the database including: destination, preferences, selected hotel, selected restaurants, full itinerary with routes, and vibe.
2. THE Trip_Planner SHALL display a list of saved trips on a "My Trips" screen.
3. WHEN the User selects a saved trip, THE Trip_Planner SHALL load the full itinerary, map routes, and selected places.
4. WHEN the User deletes a saved trip, THE Trip_Planner SHALL remove the trip and all associated data from the database.
5. THE API_Gateway SHALL enforce that each User can only read, update, and delete trips owned by that User.

### Requirement 10: Trip Sharing

**User Story:** As a User, I want to share my itinerary with others via a link, so that friends and family can view my travel plan.

#### Acceptance Criteria

1. WHEN the User taps "Share Trip," THE Share_Service SHALL generate a unique deep link URL for the trip.
2. WHEN a recipient opens the shared deep link, THE Share_Service SHALL display a read-only view of the itinerary including the timeline, map routes, and selected places.
3. THE Share_Service SHALL allow access to shared trips without requiring the recipient to have an account.
4. THE Share_Service SHALL prevent modification of the itinerary through the shared link.

### Requirement 11: User Authentication

**User Story:** As a User, I want to sign in securely, so that my trips and data are private and accessible only to me.

#### Acceptance Criteria

1. THE Auth_Service SHALL support Apple Sign-In as a required authentication method.
2. THE Auth_Service SHALL support Google OAuth as an optional authentication method.
3. WHEN a User successfully authenticates, THE Auth_Service SHALL issue a JWT access token and a refresh token.
4. THE Auth_Service SHALL store User passwords hashed using bcrypt with a minimum cost factor of 10.
5. WHEN a JWT access token expires, THE Auth_Service SHALL allow the client to obtain a new access token using a valid refresh token.
6. IF an invalid or expired token is provided with a request, THEN THE API_Gateway SHALL return a 401 Unauthorized response.
7. THE Auth_Service SHALL create a User record in the database upon first successful authentication.

### Requirement 12: Data Security

**User Story:** As a User, I want my data to be secure and private, so that no one else can access my personal information or trips.

#### Acceptance Criteria

1. THE API_Gateway SHALL enforce HTTPS for all client-server communication.
2. THE API_Gateway SHALL store all API keys and secrets in server-side environment variables, not in client code.
3. THE database SHALL enforce Row-Level Security (RLS) policies ensuring each User can only access rows where the user_id matches the authenticated User's ID.
4. THE API_Gateway SHALL implement rate limiting of 100 requests per minute per authenticated User.
5. IF a User attempts to access a trip owned by a different User, THEN THE API_Gateway SHALL return a 403 Forbidden response.
6. THE database SHALL encrypt sensitive User data at rest using Supabase's built-in encryption.

### Requirement 13: API Response Caching

**User Story:** As a User, I want fast responses when querying popular destinations, so that the app feels responsive and snappy.

#### Acceptance Criteria

1. WHEN the Place_Service receives a query for hotels or restaurants, THE Cache_Layer SHALL check for a cached response matching the query parameters before calling the external API.
2. WHEN a cached response exists and is less than 24 hours old, THE Cache_Layer SHALL return the cached response without calling the external API.
3. WHEN no cached response exists or the cache has expired, THE Cache_Layer SHALL call the external API, store the response in cache, and return the result.
4. WHEN the Itinerary_Engine receives a generation request matching a previously cached itinerary (same destination, days, vibe, and preferences), THE Cache_Layer SHALL return the cached itinerary.

### Requirement 14: Error Handling and Resilience

**User Story:** As a User, I want the app to handle errors gracefully, so that I have a smooth experience even when things go wrong.

#### Acceptance Criteria

1. IF the external places API is unavailable, THEN THE Place_Service SHALL return a user-friendly error message and the Trip_Planner SHALL display a retry option.
2. IF the OpenAI API is unavailable, THEN THE Itinerary_Engine SHALL return a user-friendly error message and the Trip_Planner SHALL display a retry option.
3. IF a network request fails due to connectivity issues, THEN THE Trip_Planner SHALL display an offline indicator and retry the request when connectivity is restored.
4. THE API_Gateway SHALL return structured error responses with an error code and a human-readable message for all failure cases.

### Requirement 15: Performance

**User Story:** As a User, I want the app to load quickly and animate smoothly, so that the experience feels premium.

#### Acceptance Criteria

1. THE Globe_View SHALL maintain a minimum frame rate of 30 frames per second during rotation and zoom gestures on devices supporting the app.
2. WHEN the User submits trip preferences, THE API_Gateway SHALL return the generated itinerary within 15 seconds.
3. THE Trip_Planner SHALL display a loading indicator with progress feedback while the itinerary is being generated.
4. THE Itinerary_View SHALL render the full itinerary timeline within 500ms of receiving the data.
