-- ============================================================
-- Add Address Column to Location Points
-- Enables admin verification of employee locations by address
-- ============================================================

-- Add address column to location_points table
ALTER TABLE location_points 
ADD COLUMN IF NOT EXISTS address TEXT;

-- Add index for address searches
CREATE INDEX IF NOT EXISTS idx_location_address ON location_points(address) WHERE address IS NOT NULL;

-- Add address columns to shift_sessions for start/end locations
ALTER TABLE shift_sessions 
ADD COLUMN IF NOT EXISTS start_address TEXT,
ADD COLUMN IF NOT EXISTS end_address TEXT;

-- Add address to employee_states for last known location
ALTER TABLE employee_states 
ADD COLUMN IF NOT EXISTS last_address TEXT;

-- Comment on columns
COMMENT ON COLUMN location_points.address IS 'Reverse geocoded address for the location point';
COMMENT ON COLUMN shift_sessions.start_address IS 'Address where the shift started';
COMMENT ON COLUMN shift_sessions.end_address IS 'Address where the shift ended';
COMMENT ON COLUMN employee_states.last_address IS 'Last known address of the employee';
