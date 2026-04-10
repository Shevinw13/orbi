from pydantic_settings import BaseSettings
from dotenv import load_dotenv
from pathlib import Path

# Load .env from the backend directory regardless of working directory
_env_path = Path(__file__).parent / ".env"
load_dotenv(_env_path)


class Settings(BaseSettings):
    """Server-side configuration loaded from environment variables.

    Required: supabase_url, supabase_key, openai_api_key, jwt_secret
    Optional: upstash_redis_url, google_places_api_key, foursquare_api_key
    """

    # Required
    supabase_url: str
    supabase_key: str
    openai_api_key: str
    jwt_secret: str

    # Optional — free-tier services with fallbacks
    upstash_redis_url: str = ""
    google_places_api_key: str = ""  # deprecated, kept for backward compat
    foursquare_api_key: str = ""     # Foursquare free tier

    model_config = {"env_file": str(Path(__file__).parent / ".env"), "extra": "ignore"}


settings = Settings()
