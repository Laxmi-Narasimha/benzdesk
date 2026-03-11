-- ============================================================================
-- Migration 042: Elegant Redesign DB Fixes
-- Fixes new user sync, travel policy band limits, and expense categories
-- ============================================================================

-- 1. UPDATE EMPLOYEE CREATION TRIGGER TO AUTO-SET MOBITRAQ ENROLLMENT

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Create employee record from auth user data
  INSERT INTO public.employees (id, name, phone, email, role, mobitraq_enrolled_at)
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'name',
      NEW.raw_user_meta_data->>'full_name',
      split_part(NEW.email, '@', 1),
      'Employee'
    ),
    COALESCE(NEW.phone, NEW.raw_user_meta_data->>'phone'),
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'role', 'employee'),
    NOW() -- Auto enroll new users in mobitraq
  )
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    phone = COALESCE(EXCLUDED.phone, employees.phone),
    email = EXCLUDED.email,
    mobitraq_enrolled_at = COALESCE(employees.mobitraq_enrolled_at, NOW()),
    updated_at = NOW();
  
  -- Initialize employee state for real-time tracking
  INSERT INTO public.employee_states (employee_id)
  VALUES (NEW.id)
  ON CONFLICT (employee_id) DO NOTHING;
  
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Log error but don't fail auth
    RAISE WARNING 'Failed to create employee for user %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;


-- 2. REVISE BAND LIMITS ACCORDING TO ACTUAL POLICY

DELETE FROM public.band_limits;

INSERT INTO public.band_limits (band, category, daily_limit, unit) VALUES
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
    ('agm', 'local_travel', 99999, 'actuals'),
    ('gm', 'local_travel', 99999, 'actuals'),
    ('plant_head', 'local_travel', 99999, 'actuals'),
    ('vp', 'local_travel', 99999, 'actuals'),
    ('director', 'local_travel', 99999, 'actuals'),

    -- Fuel Car per km
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
    
    -- Fuel Bike per km
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

    -- Laundry (max 300/day if >3 nights)
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
    ('director', 'laundry', 300, 'per_day');


-- 3. FIX CHECK CONSTRAINT ON TRIP_EXPENSES

ALTER TABLE public.trip_expenses DROP CONSTRAINT IF EXISTS trip_expenses_category_check;

ALTER TABLE public.trip_expenses ADD CONSTRAINT trip_expenses_category_check CHECK (category IN (
    'hotel', 'food_da', 'local_travel', 'fuel_car', 'fuel_bike', 'laundry', 'internet', 'toll', 'other'
));
