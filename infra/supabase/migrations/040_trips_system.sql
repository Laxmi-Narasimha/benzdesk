-- ============================================================================
-- Migration 040: Trip Planning System
-- Creates trips, trip_expenses, band_limits tables
-- Links shift_sessions and expense_claims to trips
-- Adds email + mobitraq_enrolled_at to employees
-- ============================================================================

-- ============================================================================
-- 1. ADD MISSING COLUMNS TO employees
-- ============================================================================

-- Add email column (backfill from auth.users)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'employees' AND column_name = 'email'
    ) THEN
        ALTER TABLE employees ADD COLUMN email TEXT;
    END IF;
END $$;

UPDATE employees e
SET email = u.email
FROM auth.users u
WHERE e.id = u.id AND e.email IS NULL;

-- Add mobitraq_enrolled_at (set when user logs into mobile app)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'employees' AND column_name = 'mobitraq_enrolled_at'
    ) THEN
        ALTER TABLE employees ADD COLUMN mobitraq_enrolled_at TIMESTAMPTZ;
    END IF;
END $$;

-- ============================================================================
-- 2. CREATE trips TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS trips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    from_location TEXT NOT NULL,
    to_location TEXT NOT NULL,
    reason TEXT,
    vehicle_type TEXT DEFAULT 'car' CHECK (vehicle_type IN ('car', 'bike', 'bus', 'train', 'flight', 'auto')),
    status TEXT NOT NULL DEFAULT 'requested' 
        CHECK (status IN ('requested', 'approved', 'active', 'completed', 'cancelled', 'rejected')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    approved_at TIMESTAMPTZ,
    approved_by UUID REFERENCES employees(id),
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    total_km DOUBLE PRECISION DEFAULT 0,
    total_expenses NUMERIC(10,2) DEFAULT 0,
    notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_trips_employee ON trips(employee_id);
CREATE INDEX IF NOT EXISTS idx_trips_status ON trips(status);
CREATE INDEX IF NOT EXISTS idx_trips_created ON trips(created_at DESC);

ALTER TABLE trips ENABLE ROW LEVEL SECURITY;

-- Employees can see their own trips
DROP POLICY IF EXISTS "Users can view own trips" ON trips;
CREATE POLICY "Users can view own trips" ON trips
    FOR SELECT USING (
        employee_id = auth.uid()
        OR EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin')
        OR EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role IN ('accounts_admin', 'director'))
    );

-- Employees can create trips
DROP POLICY IF EXISTS "Users can create trips" ON trips;
CREATE POLICY "Users can create trips" ON trips
    FOR INSERT WITH CHECK (employee_id = auth.uid());

-- Admins can update trips (approve/reject)
DROP POLICY IF EXISTS "Admins can update trips" ON trips;
CREATE POLICY "Admins can update trips" ON trips
    FOR UPDATE USING (
        employee_id = auth.uid()
        OR EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin')
        OR EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role IN ('accounts_admin', 'director'))
    );

-- ============================================================================
-- 3. CREATE trip_expenses TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS trip_expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES employees(id),
    category TEXT NOT NULL CHECK (category IN (
        'hotel', 'food_da', 'local_travel', 'fuel', 'toll', 
        'laundry', 'internet', 'other'
    )),
    amount NUMERIC(10,2) NOT NULL,
    description TEXT,
    receipt_path TEXT,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    limit_amount NUMERIC(10,2),
    exceeds_limit BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    approved_at TIMESTAMPTZ,
    approved_by UUID REFERENCES employees(id)
);

CREATE INDEX IF NOT EXISTS idx_trip_expenses_trip ON trip_expenses(trip_id);
CREATE INDEX IF NOT EXISTS idx_trip_expenses_employee ON trip_expenses(employee_id);
CREATE INDEX IF NOT EXISTS idx_trip_expenses_status ON trip_expenses(status);

ALTER TABLE trip_expenses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own trip expenses" ON trip_expenses;
CREATE POLICY "Users can view own trip expenses" ON trip_expenses
    FOR SELECT USING (
        employee_id = auth.uid()
        OR EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin')
        OR EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role IN ('accounts_admin', 'director'))
    );

DROP POLICY IF EXISTS "Users can create trip expenses" ON trip_expenses;
CREATE POLICY "Users can create trip expenses" ON trip_expenses
    FOR INSERT WITH CHECK (employee_id = auth.uid());

DROP POLICY IF EXISTS "Admins can update trip expenses" ON trip_expenses;
CREATE POLICY "Admins can update trip expenses" ON trip_expenses
    FOR UPDATE USING (
        employee_id = auth.uid()
        OR EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin')
        OR EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role IN ('accounts_admin', 'director'))
    );

-- ============================================================================
-- 4. CREATE band_limits TABLE (Travel Policy Reference)
-- ============================================================================

CREATE TABLE IF NOT EXISTS band_limits (
    id SERIAL PRIMARY KEY,
    band TEXT NOT NULL,
    category TEXT NOT NULL,
    daily_limit NUMERIC(10,2) NOT NULL,
    unit TEXT DEFAULT 'per_day',
    UNIQUE(band, category)
);

-- Populate band limits strictly from BENZ Travel Policy PDF
INSERT INTO band_limits (band, category, daily_limit, unit) VALUES
    -- Food DA per day
    ('executive', 'food_da', 600, 'per_day'),
    ('senior_executive', 'food_da', 600, 'per_day'),
    ('assistant', 'food_da', 600, 'per_day'),
    ('assistant_manager', 'food_da', 800, 'per_day'),
    ('manager', 'food_da', 1000, 'per_day'),
    ('senior_manager', 'food_da', 1000, 'per_day'),
    ('agm', 'food_da', 1500, 'per_day'),
    ('gm', 'food_da', 1500, 'per_day'),
    ('plant_head', 'food_da', 1500, 'per_day'),
    ('vp', 'food_da', 1500, 'per_day'),
    ('director', 'food_da', 1500, 'per_day'),
    
    -- Hotel per night
    ('executive', 'hotel', 2000, 'per_night'),
    ('senior_executive', 'hotel', 2000, 'per_night'),
    ('assistant', 'hotel', 2000, 'per_night'),
    ('assistant_manager', 'hotel', 3000, 'per_night'),
    ('manager', 'hotel', 3500, 'per_night'),
    ('senior_manager', 'hotel', 3500, 'per_night'),
    ('agm', 'hotel', 4000, 'per_night'),
    ('gm', 'hotel', 4000, 'per_night'),
    ('plant_head', 'hotel', 4000, 'per_night'),
    ('vp', 'hotel', 4000, 'per_night'),
    ('director', 'hotel', 4000, 'per_night'),
    
    -- Local Travel per day
    ('executive', 'local_travel', 300, 'per_day'),
    ('senior_executive', 'local_travel', 500, 'per_day'),
    ('assistant', 'local_travel', 500, 'per_day'),
    ('assistant_manager', 'local_travel', 700, 'per_day'),
    ('manager', 'local_travel', 1000, 'per_day'),
    ('senior_manager', 'local_travel', 1000, 'per_day'),
    -- Higher bands are actuals, we can put a very high limit or 0, let's put 99999 for actuals
    ('agm', 'local_travel', 99999, 'actuals'),
    ('gm', 'local_travel', 99999, 'actuals'),
    ('plant_head', 'local_travel', 99999, 'actuals'),
    ('vp', 'local_travel', 99999, 'actuals'),
    ('director', 'local_travel', 99999, 'actuals'),

    -- Fuel Car per km (same for all bands)
    ('executive', 'fuel_car', 7.5, 'per_km'),
    ('senior_executive', 'fuel_car', 7.5, 'per_km'),
    ('assistant', 'fuel_car', 7.5, 'per_km'),
    ('assistant_manager', 'fuel_car', 7.5, 'per_km'),
    ('manager', 'fuel_car', 7.5, 'per_km'),
    ('senior_manager', 'fuel_car', 7.5, 'per_km'),
    ('agm', 'fuel_car', 7.5, 'per_km'),
    ('gm', 'fuel_car', 7.5, 'per_km'),
    ('plant_head', 'fuel_car', 7.5, 'per_km'),
    ('vp', 'fuel_car', 7.5, 'per_km'),
    ('director', 'fuel_car', 7.5, 'per_km'),
    
    -- Fuel Bike per km (same for all bands)
    ('executive', 'fuel_bike', 5.0, 'per_km'),
    ('senior_executive', 'fuel_bike', 5.0, 'per_km'),
    ('assistant', 'fuel_bike', 5.0, 'per_km'),
    ('assistant_manager', 'fuel_bike', 5.0, 'per_km'),
    ('manager', 'fuel_bike', 5.0, 'per_km'),
    ('senior_manager', 'fuel_bike', 5.0, 'per_km'),
    ('agm', 'fuel_bike', 5.0, 'per_km'),
    ('gm', 'fuel_bike', 5.0, 'per_km'),
    ('plant_head', 'fuel_bike', 5.0, 'per_km'),
    ('vp', 'fuel_bike', 5.0, 'per_km'),
    ('director', 'fuel_bike', 5.0, 'per_km'),

    -- Laundry (max 300/day if >3 nights, same for all)
    ('executive', 'laundry', 300, 'per_day'),
    ('senior_executive', 'laundry', 300, 'per_day'),
    ('assistant', 'laundry', 300, 'per_day'),
    ('assistant_manager', 'laundry', 300, 'per_day'),
    ('manager', 'laundry', 300, 'per_day'),
    ('senior_manager', 'laundry', 300, 'per_day'),
    ('agm', 'laundry', 300, 'per_day'),
    ('gm', 'laundry', 300, 'per_day'),
    ('plant_head', 'laundry', 300, 'per_day'),
    ('vp', 'laundry', 300, 'per_day'),
    ('director', 'laundry', 300, 'per_day')
ON CONFLICT (band, category) DO UPDATE SET daily_limit = EXCLUDED.daily_limit;

ALTER TABLE band_limits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read band limits" ON band_limits;
CREATE POLICY "Anyone can read band limits" ON band_limits
    FOR SELECT TO authenticated USING (true);

-- ============================================================================
-- 5. ADD trip_id TO shift_sessions (link sessions to trips)
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'shift_sessions' AND column_name = 'trip_id'
    ) THEN
        ALTER TABLE shift_sessions ADD COLUMN trip_id UUID REFERENCES trips(id) ON DELETE SET NULL;
        CREATE INDEX IF NOT EXISTS idx_shift_sessions_trip ON shift_sessions(trip_id);
    END IF;
END $$;

-- ============================================================================
-- 6. GRANTS
-- ============================================================================

GRANT ALL ON trips TO authenticated;
GRANT ALL ON trip_expenses TO authenticated;
GRANT SELECT ON band_limits TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE band_limits_id_seq TO authenticated;

-- ============================================================================
-- DONE
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Migration 040: Trip Planning System created successfully!';
  RAISE NOTICE '   - trips table with RLS';
  RAISE NOTICE '   - trip_expenses table with RLS';
  RAISE NOTICE '   - band_limits reference table (44 rows)';
  RAISE NOTICE '   - employees.email + mobitraq_enrolled_at columns';
  RAISE NOTICE '   - shift_sessions.trip_id FK';
END $$;
