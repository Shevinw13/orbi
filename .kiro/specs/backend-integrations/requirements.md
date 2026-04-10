# Requirements Document

## Introduction

The Orbi travel planning app has a fully built FastAPI backend and SwiftUI iOS client, but many services currently rely on hardcoded data, mock responses, or paid APIs (Google Places) that have no keys configured. This feature wires up real, free-tier backend integrations so the app functions end-to-end: Supabase for persistence, OpenAI for itinerary generation, Nominatim for geocoding/search, Foursquare (or OpenTripMap) for place recommendations, and an optional Upstash Redis (with in-memory fallback) for caching. The iOS client is also updated to reliably connect to the running backend instead of falling back to local stub data.

## Glossary

- **Backend**: The Python/FastAPI server located at `drobe/backend/`
- **iOS_Client**: The SwiftUI application located at `drobe/ios/Orbi/`
- **Supabase_Client**: The `supabase-py` client used by Backend services to read/write the PostgreSQL database hosted on Supabase
- **Migration_Schema**: The SQL file at `drobe/backend/migrations/001_initial_schema.sql` defining tables, indexes, RLS policies, and triggers
- **RLS**: Row-Level Security policies in Supabase/PostgreSQL that restrict data access per user
- **Itinerary_Engine**: The Backend service (`services/itinerary.py`) that calls OpenAI to generate travel itineraries
- **Search_Service**: The Backend service (`services/search.py`) that provides destination autocomplete suggestions
- **Place_Service**: The Backend service (`services/places.py`) that returns hotel and restaurant recommendations
- **Cache_Service**: The Backend service (`services/cache.py`) that provides get/set helpers backed by Redis or an in-memory fallback
- **Nominatim_API**: The free OpenStreetMap geocoding/search API at `https://nominatim.openstreetmap.org`
- **Foursquare_API**: The Foursquare Places API free tier providing venue search for hotels and restaurants
- **OpenTripMap_API**: An alternative free API for points of interest, usable if Foursquare is unavailable
- **Upstash_Redis**: A serverless Redis provider with a free tier, used for caching
- **In_Memory_Cache**: A Python dictionary-based cache fallback used when Redis is unavailable
- **GlobeView**: The SceneKit-based 3D globe in the iOS_Client (`Views/GlobeView.swift`) that displays city markers
- **APIClient**: The iOS_Client networking layer (`Services/APIClient.swift`) that makes HTTP requests to the Backend
- **Settings**: The Pydantic `Settings` class in `backend/config.py` that loads environment variables

## Requirements

### Requirement 1: Supabase Database Connection

**User Story:** As a developer, I want the Backend to connect to a real Supabase project with the migration schema applied, so that user data, trips, and shared trips persist across sessions.

#### Acceptance Criteria

1. WHEN the Backend starts, THE Supabase_Client SHALL connect to the Supabase project using the `SUPABASE_URL` and `SUPABASE_KEY` environment variables from Settings
2. WHEN the Migration_Schema is applied to the Supabase project, THE Supabase_Client SHALL have access to the `users`, `refresh_tokens`, `trips`, and `shared_trips` tables with all indexes and triggers defined in `001_initial_schema.sql`
3. WHILE RLS is enabled on all tables, THE Supabase_Client SHALL use the service-role key for Backend operations that bypass per-user RLS restrictions (inserts on behalf of users during auth flows)
4. IF the Supabase project is unreachable at startup, THEN THE Backend SHALL log a clear error message indicating the connection failure and the expected environment variables
5. WHEN a trip is created via the Backend, THE Supabase_Client SHALL persist the trip row and return the created record with a server-generated UUID and timestamps

### Requirement 2: OpenAI Itinerary Integration

**User Story:** As a traveler, I want the Itinerary_Engine to generate real AI-powered itineraries using OpenAI, so that I receive personalized travel plans.

#### Acceptance Criteria

1. WHEN the `OPENAI_API_KEY` environment variable is set, THE Itinerary_Engine SHALL use the key to authenticate requests to the OpenAI Chat Completions API
2. WHEN a valid itinerary generation request is received, THE Itinerary_Engine SHALL send a prompt to the `gpt-4o-mini` model and parse the structured JSON response into an ItineraryResponse
3. IF the OpenAI API returns an error or times out, THEN THE Itinerary_Engine SHALL raise a RuntimeError with a descriptive message including the HTTP status or timeout detail
4. WHEN a replacement activity is requested, THE Itinerary_Engine SHALL call OpenAI with context about existing activities to avoid duplicates and return a single ActivitySlot
5. IF the OpenAI response contains malformed JSON, THEN THE Itinerary_Engine SHALL raise a RuntimeError indicating the parse failure

### Requirement 3: Nominatim Geocoding and Search

**User Story:** As a traveler, I want to search for destinations using a free geocoding service, so that I get real autocomplete suggestions without requiring a paid Google Places API key.

#### Acceptance Criteria

1. WHEN a destination search query is received, THE Search_Service SHALL send a request to the Nominatim_API at `https://nominatim.openstreetmap.org/search` with the query, `format=json`, and `addressdetails=1` parameters
2. THE Search_Service SHALL include a descriptive `User-Agent` header (e.g., `Orbi/1.0`) in all Nominatim_API requests, as required by the Nominatim usage policy
3. WHEN the Nominatim_API returns results, THE Search_Service SHALL map each result to a destination suggestion containing `name`, `place_id`, `latitude`, and `longitude`
4. WHEN the Nominatim_API returns results, THE Search_Service SHALL filter results to prioritize cities, towns, and administrative regions by using the `featuretype=city` parameter or filtering by `type` and `class` fields
5. IF the Nominatim_API is unreachable or returns an error, THEN THE Search_Service SHALL return an empty list and log the error
6. THE Search_Service SHALL cache Nominatim_API results in the Cache_Service with a 24-hour TTL to reduce repeated requests
7. THE Search_Service SHALL remove all references to the Google Places Autocomplete API and Google Places Details API


### Requirement 4: Free Place Recommendations (Foursquare or OpenTripMap)

**User Story:** As a traveler, I want hotel and restaurant recommendations from a free API, so that the app provides real venue data without requiring a paid Google Places subscription.

#### Acceptance Criteria

1. WHEN a hotel search request is received, THE Place_Service SHALL query the Foursquare_API (or OpenTripMap_API) for lodging venues near the specified latitude/longitude within the given radius
2. WHEN a restaurant search request is received, THE Place_Service SHALL query the Foursquare_API (or OpenTripMap_API) for restaurant venues near the specified latitude/longitude, filtered by cuisine type when provided
3. WHEN results are returned from the external API, THE Place_Service SHALL map each venue to a PlaceResult containing `place_id`, `name`, `rating`, `price_level`, `image_url`, `latitude`, and `longitude`
4. THE Place_Service SHALL sort results by rating in descending order and return the top 3 venues
5. WHEN `excluded_ids` are provided in the query, THE Place_Service SHALL filter out venues with matching IDs before selecting the top 3
6. IF the initial filtered results are empty, THEN THE Place_Service SHALL relax the price and keyword filters, re-query, and set `filters_broadened` to true in the response
7. THE Place_Service SHALL cache API results in the Cache_Service with a 24-hour TTL
8. THE Place_Service SHALL remove all references to the Google Places Nearby Search API and Google photo URLs
9. WHEN a `FOURSQUARE_API_KEY` environment variable is set, THE Place_Service SHALL use the Foursquare_API; WHERE the key is absent, THE Place_Service SHALL fall back to the OpenTripMap_API which requires no authentication

### Requirement 5: Cache Service with In-Memory Fallback

**User Story:** As a developer, I want the Cache_Service to use Upstash Redis when available and fall back to an in-memory cache when Redis is not configured, so that caching works in all environments.

#### Acceptance Criteria

1. WHEN the `UPSTASH_REDIS_URL` environment variable is set and valid, THE Cache_Service SHALL connect to Upstash_Redis and use it for all get/set operations
2. WHERE the `UPSTASH_REDIS_URL` environment variable is empty or not set, THE Cache_Service SHALL use the In_Memory_Cache for all get/set operations
3. THE In_Memory_Cache SHALL store key-value pairs in a Python dictionary with TTL enforcement, evicting entries that have exceeded their TTL on read
4. WHEN `set_cached` is called, THE Cache_Service SHALL serialize the value to JSON and store it with the specified TTL in either Upstash_Redis or In_Memory_Cache
5. WHEN `get_cached` is called for a key that exists and has not expired, THE Cache_Service SHALL return the deserialized value
6. WHEN `get_cached` is called for a key that does not exist or has expired, THE Cache_Service SHALL return None
7. IF the Redis connection fails during a get or set operation, THEN THE Cache_Service SHALL log the error and fall back to the In_Memory_Cache for that operation
8. THE Settings class SHALL make `UPSTASH_REDIS_URL` an optional field with a default of empty string, so the Backend starts without Redis configured

### Requirement 6: Settings Configuration Update

**User Story:** As a developer, I want the Settings class to support optional API keys and new free-tier service keys, so that the Backend starts with only the required credentials.

#### Acceptance Criteria

1. THE Settings class SHALL make `google_places_api_key` an optional field with a default of empty string, since Google Places is being replaced
2. THE Settings class SHALL make `upstash_redis_url` an optional field with a default of empty string
3. THE Settings class SHALL add a `foursquare_api_key` optional field with a default of empty string
4. THE Settings class SHALL require `supabase_url`, `supabase_key`, `openai_api_key`, and `jwt_secret` as mandatory fields (no defaults)
5. WHEN the `.env.example` file is updated, THE Backend SHALL document all environment variables with clear descriptions indicating which are required and which are optional
6. IF a required environment variable is missing at startup, THEN THE Settings class SHALL raise a validation error with the name of the missing variable


### Requirement 7: iOS Search Service — Live Backend Search

**User Story:** As a traveler using the iOS app, I want the search bar to return real destination suggestions from the Backend (powered by Nominatim), so that I can find any city in the world.

#### Acceptance Criteria

1. WHEN the user types a search query, THE iOS_Client SearchService SHALL send a GET request to `/search/destinations?q=<query>` via the APIClient
2. WHEN the Backend returns results, THE iOS_Client SearchService SHALL display the destination suggestions with name, latitude, and longitude
3. IF the Backend is unreachable, THEN THE iOS_Client SearchService SHALL fall back to filtering the local city list and display those results
4. THE iOS_Client SearchService SHALL debounce search requests so that a request is sent only after the user pauses typing for 300 milliseconds

### Requirement 8: iOS GlobeView — Dynamic City Markers

**User Story:** As a traveler, I want the 3D globe to display popular city markers loaded from a curated data source rather than a hardcoded list, so that the globe content can be updated without an app release.

#### Acceptance Criteria

1. WHEN the GlobeView loads, THE iOS_Client SHALL attempt to fetch a list of popular cities from the Backend endpoint `GET /search/popular-cities`
2. IF the Backend returns a list of cities, THEN THE GlobeView SHALL use those cities for 3D pin markers and 2D label overlays instead of the hardcoded `popularCities` array
3. IF the Backend is unreachable, THEN THE GlobeView SHALL fall back to the existing hardcoded `popularCities` array
4. WHEN the Backend endpoint `GET /search/popular-cities` is called, THE Search_Service SHALL return a curated list of 15-25 popular travel destinations with name, latitude, and longitude

### Requirement 9: iOS APIClient — Backend Connectivity

**User Story:** As a developer, I want the iOS APIClient to reliably connect to the running Backend, so that the app uses real data instead of falling back to local stubs.

#### Acceptance Criteria

1. WHILE in DEBUG mode, THE APIClient SHALL use `http://localhost:8000` as the base URL for Backend requests
2. THE APIClient SHALL include the Bearer token from Keychain in the Authorization header for all authenticated requests
3. WHEN the Backend returns a 401 status, THE APIClient SHALL attempt to refresh the access token using the stored refresh token and retry the original request once
4. IF the token refresh fails, THEN THE APIClient SHALL throw an `unauthorized` error so the iOS_Client can prompt the user to sign in again
5. WHEN the Backend returns a 429 status, THE APIClient SHALL throw a `rateLimited` error with a user-friendly message

### Requirement 10: Backend Popular Cities Endpoint

**User Story:** As a developer, I want a Backend endpoint that returns a curated list of popular travel cities, so that the GlobeView and other UI components can load city data dynamically.

#### Acceptance Criteria

1. WHEN a GET request is made to `/search/popular-cities`, THE Backend SHALL return a JSON array of city objects each containing `name`, `latitude`, and `longitude`
2. THE Backend SHALL return between 15 and 25 cities in the popular cities list
3. THE Backend SHALL cache the popular cities response in the Cache_Service with a 7-day TTL
4. THE `/search/popular-cities` endpoint SHALL be accessible without authentication (public endpoint)


### Requirement 11: Rate Limiter Resilience

**User Story:** As a developer, I want the rate limiter middleware to work with both Redis and the in-memory fallback, so that rate limiting functions regardless of whether Upstash Redis is configured.

#### Acceptance Criteria

1. WHEN Upstash_Redis is available, THE RateLimitMiddleware SHALL use Redis INCR/EXPIRE for per-user request counting
2. WHERE Upstash_Redis is unavailable, THE RateLimitMiddleware SHALL use the In_Memory_Cache or a simple in-memory counter to enforce rate limits
3. IF the cache backend raises an error during rate limit checking, THEN THE RateLimitMiddleware SHALL allow the request through and log the error, rather than blocking the user

### Requirement 12: End-to-End Integration Verification

**User Story:** As a developer, I want to verify that all integrations work together, so that I can confirm the app functions end-to-end from iOS client to real backend services.

#### Acceptance Criteria

1. WHEN the Backend starts with a valid `.env` file, THE Backend SHALL pass the `/health` endpoint check and log successful connections to Supabase and cache
2. WHEN the iOS_Client sends a search query to the Backend, THE Backend SHALL return real Nominatim_API results (or cached results) to the iOS_Client
3. WHEN the iOS_Client requests an itinerary, THE Backend SHALL call OpenAI and return a valid ItineraryResponse to the iOS_Client
4. WHEN the iOS_Client requests hotel or restaurant recommendations, THE Backend SHALL return real Foursquare_API (or OpenTripMap_API) results to the iOS_Client
