-- Migration 052: Add per-employee compensation rates

ALTER TABLE employees 
ADD COLUMN IF NOT EXISTS bike_rate_per_km DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS car_rate_per_km DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS daily_allowance DECIMAL(10, 2) NOT NULL DEFAULT 0.00;
