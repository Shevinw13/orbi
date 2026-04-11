from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from backend.config import settings  # noqa: F401 – validates env vars on startup
from backend.middleware.jwt_auth import JWTAuthMiddleware
from backend.middleware.rate_limit import RateLimitMiddleware
from backend.routes.auth import router as auth_router
from backend.routes.itinerary import router as itinerary_router
from backend.routes.cost import router as cost_router
from backend.routes.places import router as places_router
from backend.routes.trips import router as trips_router
from backend.routes.share import share_write_router, share_read_router
from backend.routes.search import router as search_router
from backend.routes.explore import router as explore_router
from backend.routes.weather import router as weather_router

app = FastAPI(
    title="Orbi API",
    version="0.1.0",
    description="Backend API for the Orbi iOS app",
)

# CORS – allow iOS client and local development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # tighten to iOS bundle / domain in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Rate limiting – added before JWT so it runs *after* JWT in request flow
# (Starlette executes the last-added middleware first on incoming requests)
app.add_middleware(RateLimitMiddleware)

# JWT authentication – outermost after CORS, sets request.state.user_id
app.add_middleware(JWTAuthMiddleware)

# --- Routers ---
app.include_router(auth_router)
app.include_router(itinerary_router)
app.include_router(places_router)
app.include_router(cost_router)
app.include_router(trips_router)
app.include_router(share_write_router)
app.include_router(share_read_router)
app.include_router(search_router)
app.include_router(explore_router)
app.include_router(weather_router)


@app.get("/health")
async def health_check():
    from backend.services.cache import get_redis_client

    # Cache backend status
    redis_client = get_redis_client()
    if redis_client is not None:
        try:
            redis_client.ping()
            cache_status = "redis_connected"
        except Exception:
            cache_status = "redis_error_inmemory_fallback"
    else:
        cache_status = "in_memory"

    # Supabase connectivity check
    try:
        from supabase import create_client
        client = create_client(settings.supabase_url, settings.supabase_key)
        supabase_status = "configured"
    except Exception:
        supabase_status = "error"

    return {
        "status": "ok",
        "cache_backend": cache_status,
        "supabase": supabase_status,
    }
