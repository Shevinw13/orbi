-- 001_initial_schema.sql
-- Orbi: Initial database schema and RLS policies
-- Validates: Requirements 12.3, 12.5, 12.6, 9.5

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- TABLES
-- ============================================================

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email TEXT,
    name TEXT,
    auth_provider TEXT NOT NULL,
    apple_sub TEXT,
    google_sub TEXT,
    password_hash TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trips (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    destination TEXT NOT NULL,
    destination_lat_lng TEXT,
    num_days INTEGER NOT NULL,
    vibe TEXT,
    preferences JSONB,
    itinerary JSONB,
    selected_hotel_id TEXT,
    selected_restaurants JSONB,
    cost_breakdown JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE shared_trips (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trip_id UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    share_id TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ
);

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX idx_trips_user_id ON trips(user_id);
CREATE INDEX idx_shared_trips_share_id ON shared_trips(share_id);
CREATE INDEX idx_users_apple_sub ON users(apple_sub) WHERE apple_sub IS NOT NULL;
CREATE INDEX idx_users_google_sub ON users(google_sub) WHERE google_sub IS NOT NULL;

-- ============================================================
-- ROW-LEVEL SECURITY
-- ============================================================

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE refresh_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared_trips ENABLE ROW LEVEL SECURITY;

-- Users: can only read/update their own profile
CREATE POLICY users_select ON users
    FOR SELECT USING (auth.uid() = id);

CREATE POLICY users_update ON users
    FOR UPDATE USING (auth.uid() = id);

-- Refresh tokens: users can only access their own tokens
CREATE POLICY refresh_tokens_select ON refresh_tokens
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY refresh_tokens_insert ON refresh_tokens
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY refresh_tokens_delete ON refresh_tokens
    FOR DELETE USING (auth.uid() = user_id);

-- Trips: users can only CRUD their own trips (Req 9.5, 12.5)
CREATE POLICY trips_select ON trips
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY trips_insert ON trips
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY trips_update ON trips
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY trips_delete ON trips
    FOR DELETE USING (auth.uid() = user_id);

-- Shared trips: readable by anyone without auth (Req 10.3)
CREATE POLICY shared_trips_select ON shared_trips
    FOR SELECT USING (true);

CREATE POLICY shared_trips_insert ON shared_trips
    FOR INSERT WITH CHECK (auth.uid() = (SELECT user_id FROM trips WHERE trips.id = trip_id));

-- ============================================================
-- UPDATED_AT TRIGGER
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER set_trips_updated_at
    BEFORE UPDATE ON trips
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
