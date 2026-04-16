-- 006_shared_itineraries.sql
-- Explore Shared Itineraries: new table + trips attribution columns
-- Requirements: 9.1, 9.2, 9.3, 9.4, 6.2, 6.3

-- ============================================================
-- SHARED ITINERARIES TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS shared_itineraries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source_trip_id UUID REFERENCES trips(id) ON DELETE SET NULL,
    title TEXT NOT NULL CHECK (char_length(title) <= 100),
    description TEXT NOT NULL CHECK (char_length(description) <= 500),
    destination TEXT NOT NULL,
    destination_lat_lng TEXT,
    budget_level INTEGER NOT NULL CHECK (budget_level BETWEEN 1 AND 5),
    cover_photo_url TEXT NOT NULL,
    tags TEXT[] DEFAULT '{}',
    num_days INTEGER NOT NULL CHECK (num_days >= 1),
    itinerary JSONB NOT NULL,
    save_count INTEGER NOT NULL DEFAULT 0,
    is_featured BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_shared_itineraries_destination ON shared_itineraries(destination);
CREATE INDEX IF NOT EXISTS idx_shared_itineraries_budget_level ON shared_itineraries(budget_level);
CREATE INDEX IF NOT EXISTS idx_shared_itineraries_save_count ON shared_itineraries(save_count DESC);
CREATE INDEX IF NOT EXISTS idx_shared_itineraries_is_featured ON shared_itineraries(is_featured) WHERE is_featured = true;
CREATE INDEX IF NOT EXISTS idx_shared_itineraries_user_id ON shared_itineraries(user_id);

-- ============================================================
-- UPDATED_AT TRIGGER (reuses existing function)
-- ============================================================

CREATE TRIGGER set_shared_itineraries_updated_at
    BEFORE UPDATE ON shared_itineraries
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- TRIPS TABLE: attribution columns for copied itineraries
-- ============================================================

ALTER TABLE trips ADD COLUMN IF NOT EXISTS copied_from_shared_id UUID REFERENCES shared_itineraries(id) ON DELETE SET NULL;
ALTER TABLE trips ADD COLUMN IF NOT EXISTS original_creator_username TEXT;

-- ============================================================
-- ROW-LEVEL SECURITY
-- ============================================================

ALTER TABLE shared_itineraries ENABLE ROW LEVEL SECURITY;

-- Public read access (no auth required for browsing)
CREATE POLICY shared_itineraries_select ON shared_itineraries
    FOR SELECT USING (true);

-- Only the owner can insert
CREATE POLICY shared_itineraries_insert ON shared_itineraries
    FOR INSERT WITH CHECK (user_id = user_id);


-- ============================================================
-- RPC: Atomic save_count increment
-- ============================================================

CREATE OR REPLACE FUNCTION increment_save_count(row_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE shared_itineraries
    SET save_count = save_count + 1
    WHERE id = row_id;
END;
$$ LANGUAGE plpgsql;
