-- Lock down all tables with RLS
-- Only the service_role key (used by our backend) bypasses RLS
-- The anon key and any direct Supabase REST access gets NOTHING

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE refresh_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared_trips ENABLE ROW LEVEL SECURITY;

-- Drop any existing permissive policies
DROP POLICY IF EXISTS users_select ON users;
DROP POLICY IF EXISTS users_update ON users;
DROP POLICY IF EXISTS refresh_tokens_select ON refresh_tokens;
DROP POLICY IF EXISTS refresh_tokens_insert ON refresh_tokens;
DROP POLICY IF EXISTS refresh_tokens_delete ON refresh_tokens;
DROP POLICY IF EXISTS trips_select ON trips;
DROP POLICY IF EXISTS trips_insert ON trips;
DROP POLICY IF EXISTS trips_update ON trips;
DROP POLICY IF EXISTS trips_delete ON trips;
DROP POLICY IF EXISTS shared_trips_select ON shared_trips;
DROP POLICY IF EXISTS shared_trips_insert ON shared_trips;

-- Create DENY-ALL policies for the anon role
-- This means: nobody can access anything via the public Supabase API
-- Our backend uses the service_role key which bypasses RLS entirely

CREATE POLICY deny_all_users ON users FOR ALL USING (false);
CREATE POLICY deny_all_refresh_tokens ON refresh_tokens FOR ALL USING (false);
CREATE POLICY deny_all_trips ON trips FOR ALL USING (false);
CREATE POLICY deny_all_shared_trips ON shared_trips FOR ALL USING (false);

-- Revoke direct access from anon and authenticated roles
REVOKE ALL ON users FROM anon;
REVOKE ALL ON refresh_tokens FROM anon;
REVOKE ALL ON trips FROM anon;
REVOKE ALL ON shared_trips FROM anon;
