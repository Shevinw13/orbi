-- Migration: Add planned_by and notes columns to shared_trips table
-- Requirements: 8.1, 8.2

ALTER TABLE shared_trips ADD COLUMN IF NOT EXISTS planned_by text;
ALTER TABLE shared_trips ADD COLUMN IF NOT EXISTS notes text;
