from pydantic_settings import BaseSettings
from dotenv import load_dotenv

load_dotenv()


class Settings(BaseSettings):
    """Server-side configuration loaded from environment variables.

    All API keys and secrets are stored here, never exposed to the client.
    (Requirement 12.2)
    """

    supabase_url: str
    supabase_key: str
    upstash_redis_url: str
    openai_api_key: str
    google_places_api_key: str
    jwt_secret: str

    model_config = {"env_file": ".env", "extra": "ignore"}


settings = Settings()
