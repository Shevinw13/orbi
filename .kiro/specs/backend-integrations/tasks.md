# Implementation Plan: Backend Integrations

## Overview

Wire the Orbi backend to real free-tier services (Nominatim, Foursquare/OpenTripMap, Upstash Redis with in-memory fallback) and update the iOS client to load dynamic data. Implementation follows the dependency order: config → cache → search → places → rate limiter → routes → iOS → tests.

## Tasks

- [x] 1. Update Settings and environment configuration
  - [x] 1.1 Update `backend/config.py` Settings class
    - Make `upstash_redis_url` optional with default `""`
    - Make `google_places_api_key` optional with default `""`
    - Add `foursquare_api_key` optional field with default `""`
    - Keep `supabase_url`, `supabase_key`, `openai_api_key`, `jwt_secret` as required (no defaults)
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.6_

  - [x] 1.2 Update `backend/.env.example` with documented variables
    - Add section comments for Required vs Optional variables
    - Add `FOURSQUARE_API_KEY` entry with description
    - Mark `GOOGLE_PLACES_API_KEY` as deprecated/optional
    - Mark `UPSTASH_REDIS_URL` as optional
    - _Requirements: 6.5_

- [x] 2. Implement cache service with in-memory fallback
  - [x] 2.1 Rewrite `backend/services/cache.py`
    - Add `_memory_store: dict[str, tuple[str, float]]` for in-memory cache with TTL
    - Update `get_redis_client()` to return `None` when `upstash_redis_url` is empty
    - Update `get_cached()` to try Redis first, fall back to in-memory on failure or when Redis is unconfigured; enforce TTL eviction on read
    - Update `set_cached()` to try Redis first, fall back to in-memory on failure or when Redis is unconfigured
    - Wrap Redis operations in try/except to log errors and fall back gracefully
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8_

  - [ ]* 2.2 Write property test for cache round-trip (Property 7)
    - **Property 7: Cache Round-Trip**
    - Use Hypothesis to generate arbitrary JSON-serializable values, verify `set_cached` then `get_cached` returns equal value
    - **Validates: Requirements 5.4, 5.5**

  - [ ]* 2.3 Write property test for cache TTL eviction (Property 8)
    - **Property 8: Cache TTL Eviction**
    - Use Hypothesis with mocked `time.time()` to verify entries expire after TTL and are available before TTL
    - **Validates: Requirements 5.3, 5.6**

- [x] 3. Checkpoint - Ensure config and cache changes work
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Replace search service with Nominatim integration
  - [x] 4.1 Rewrite `backend/services/search.py` to use Nominatim
    - Replace Google Places Autocomplete/Details URLs with `https://nominatim.openstreetmap.org/search`
    - Add `User-Agent: Orbi/1.0 (travel-planner)` header to all Nominatim requests
    - Send `format=json`, `addressdetails=1`, `featuretype=city`, `limit=5` params
    - Map Nominatim results to `{name, place_id, latitude, longitude}` dicts
    - Filter results by `type` in `{city, town, administrative, village}` or `class == "place"`
    - Return empty list on error instead of raising RuntimeError
    - Cache results with 24h TTL via `set_cached`
    - Remove all Google Places Autocomplete and Details API references
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

  - [x] 4.2 Add `get_popular_cities()` function to `backend/services/search.py`
    - Define `POPULAR_CITIES` list with 20 curated travel destinations (name, latitude, longitude)
    - Implement `get_popular_cities()` with 7-day TTL caching
    - _Requirements: 8.4, 10.1, 10.2, 10.3_

  - [ ]* 4.3 Write property test for Nominatim result mapping (Property 3)
    - **Property 3: Nominatim Result Mapping**
    - Use Hypothesis to generate Nominatim-shaped dicts, verify mapping produces valid destination suggestions
    - **Validates: Requirements 3.3**

  - [ ]* 4.4 Write property test for Nominatim city type filtering (Property 4)
    - **Property 4: Nominatim City Type Filtering**
    - Use Hypothesis to generate mixed-type result lists, verify only city/town/administrative/village/place-class results pass
    - **Validates: Requirements 3.4**

- [x] 5. Replace places service with Foursquare/OpenTripMap
  - [x] 5.1 Rewrite `backend/services/places.py` for Foursquare and OpenTripMap
    - Add `_use_foursquare()` check based on `settings.foursquare_api_key`
    - Implement `_fetch_foursquare()` with Foursquare Places API v3 (`/v3/places/search`), using category IDs for lodging (19014) and restaurants (13000)
    - Implement `_fetch_opentripmap()` with OpenTripMap radius endpoint, using kinds `accomodations` / `foods`
    - Implement `_parse_foursquare_result()` and `_parse_opentripmap_result()` to map venue data to `PlaceResult`
    - Update `_search_places()` to call Foursquare or OpenTripMap based on key availability
    - Keep existing sort-by-rating, top-3, excluded_ids filtering, and filter-broadening logic
    - Cache results with 24h TTL
    - Remove all Google Places Nearby Search and Google photo URL references
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 4.9_

  - [ ]* 5.2 Write property test for place results sorting (Property 5)
    - **Property 5: Place Results Sorted by Rating, Top 3**
    - Use Hypothesis to generate lists of PlaceResult-like dicts, verify at most 3 returned in descending rating order
    - **Validates: Requirements 4.4**

  - [ ]* 5.3 Write property test for excluded IDs filtering (Property 6)
    - **Property 6: Excluded IDs Filtering**
    - Use Hypothesis to generate results and excluded_ids sets, verify no excluded IDs appear in output
    - **Validates: Requirements 4.5**

  - [ ]* 5.4 Write property test for venue-to-PlaceResult mapping (Property 10)
    - **Property 10: Venue-to-PlaceResult Mapping**
    - Use Hypothesis to generate Foursquare/OpenTripMap venue dicts, verify mapping produces valid PlaceResult fields
    - **Validates: Requirements 4.3**

- [x] 6. Update rate limiter for resilience without Redis
  - [x] 6.1 Update `backend/middleware/rate_limit.py`
    - Import updated `get_redis_client` that may return `None`
    - Add `_memory_counters: dict[str, tuple[int, float]]` for in-memory rate limiting
    - When `get_redis_client()` returns `None`, use in-memory counter with window-based expiry
    - Wrap Redis operations in try/except; on error, allow request through and log warning
    - _Requirements: 11.1, 11.2, 11.3_

- [x] 7. Checkpoint - Ensure backend services compile and tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Add routes and health endpoint updates
  - [x] 8.1 Add `/search/popular-cities` route to `backend/routes/search.py`
    - Add `GET /popular-cities` endpoint that calls `get_popular_cities()` from the search service
    - Return `{"results": [...]}` JSON response
    - _Requirements: 10.1, 10.4_

  - [x] 8.2 Update `backend/middleware/jwt_auth.py` to make popular-cities public
    - Add `/search/popular-cities` to `PUBLIC_PATH_PREFIXES` or add specific path check so the endpoint is accessible without auth
    - _Requirements: 10.4_

  - [x] 8.3 Update `/health` endpoint in `backend/main.py`
    - Add cache backend status (Redis connected vs in-memory) to health response
    - Add Supabase connectivity check (or note connection status)
    - _Requirements: 12.1_

- [ ] 9. iOS client updates
  - [x] 9.1 Update `ios/Orbi/Views/GlobeView.swift` to load dynamic city markers
    - Add `loadPopularCities()` async function that calls `GET /search/popular-cities` via APIClient (no auth required)
    - On success, replace the hardcoded `popularCities` array with backend response
    - On failure, fall back to existing hardcoded `CityMarker.popularCities`
    - Update `addCityMarkers(to:)` and `addLabelOverlays(to:)` to use the dynamically loaded cities
    - _Requirements: 8.1, 8.2, 8.3_

  - [x] 9.2 Verify `ios/Orbi/Services/SearchService.swift` fallback behavior
    - Confirm `searchDestinations()` calls `GET /search/destinations?q=` and falls back to `localCities` on error
    - No structural changes needed — existing fallback logic is correct
    - _Requirements: 7.1, 7.2, 7.3_

- [x] 10. Checkpoint - Ensure all backend and iOS changes compile
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 11. Property tests for itinerary and settings
  - [ ]* 11.1 Write property test for itinerary prompt completeness (Property 1)
    - **Property 1: Itinerary Prompt Completeness**
    - Use Hypothesis to generate random `ItineraryRequest` values, verify `_build_prompt()` output contains destination, num_days, vibe, and JSON schema
    - **Validates: Requirements 2.2**

  - [ ]* 11.2 Write property test for replace activity prompt (Property 2)
    - **Property 2: Replace Activity Prompt Includes Existing Activities**
    - Use Hypothesis to generate `ReplaceActivityRequest` with non-empty `existing_activities`, verify all activity names appear in prompt
    - **Validates: Requirements 2.4**

  - [ ]* 11.3 Write property test for Settings required fields (Property 9)
    - **Property 9: Settings Required Fields Validation**
    - Use Hypothesis to omit each required field from `{supabase_url, supabase_key, openai_api_key, jwt_secret}`, verify `ValidationError` is raised naming the missing field
    - **Validates: Requirements 6.4, 6.6**

- [x] 12. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Property tests use Hypothesis (add `hypothesis>=6.0` to `requirements.txt`)
- Implementation order follows dependency chain: config → cache → search → places → rate limiter → routes → iOS
- The itinerary service (`itinerary.py`) needs no code changes — it works once `OPENAI_API_KEY` is set
- Supabase connection is already wired in `auth.py`, `trips.py`, `share.py` — just needs a real project with the migration applied
