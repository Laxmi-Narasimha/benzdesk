-- ============================================================================
-- Migration 047: Fix Sync Trigger Descriptions for Trip Expenses
-- Makes the request title and description human-readable instead of raw data.
-- Includes employee name, trip route, category label, and session link.
-- ============================================================================

-- Replace the sync trigger function with one that generates proper titles/descriptions
CREATE OR REPLACE FUNCTION public.trigger_sync_trip_expense_to_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_emp_name TEXT;
    v_trip_from TEXT;
    v_trip_to TEXT;
    v_trip_vehicle TEXT;
    v_cat_label TEXT;
    v_title TEXT;
    v_desc TEXT;
    v_session_start TEXT;
    v_session_end TEXT;
    v_session_km NUMERIC;
BEGIN
    -- Get employee name
    SELECT name INTO v_emp_name FROM employees WHERE id = NEW.employee_id;
    
    -- Get trip details
    SELECT from_location, to_location, vehicle_type
    INTO v_trip_from, v_trip_to, v_trip_vehicle
    FROM trips WHERE id = NEW.trip_id;

    -- Get session addresses if linked
    IF NEW.session_id IS NOT NULL THEN
        SELECT start_address, end_address, total_km
        INTO v_session_start, v_session_end, v_session_km
        FROM sessions WHERE id = NEW.session_id;
    END IF;
    
    -- Map category to human label
    v_cat_label := CASE NEW.category
        WHEN 'food_da' THEN 'Food DA'
        WHEN 'hotel' THEN 'Hotel'
        WHEN 'local_travel' THEN 'Local Travel'
        WHEN 'fuel_car' THEN 'Fuel (Car)'
        WHEN 'fuel_bike' THEN 'Fuel (Bike)'
        WHEN 'laundry' THEN 'Laundry'
        WHEN 'toll' THEN 'Toll/Parking'
        WHEN 'internet' THEN 'Internet'
        ELSE COALESCE(INITCAP(REPLACE(NEW.category, '_', ' ')), 'Other')
    END;
    
    -- Build title: "Fuel (Car) - Gurgaon → Manesar" or "Hotel Expense"
    IF v_trip_from IS NOT NULL AND v_trip_to IS NOT NULL THEN
        v_title := v_cat_label || ' — ' || v_trip_from || ' → ' || v_trip_to;
    ELSE
        v_title := v_cat_label || ' Expense';
    END IF;
    
    -- Build description
    v_desc := v_emp_name || ' submitted a ' || v_cat_label || ' expense of ₹' || NEW.amount;
    
    IF v_trip_from IS NOT NULL THEN
        v_desc := v_desc || chr(10) || 'Trip: ' || v_trip_from || ' → ' || v_trip_to;
        IF v_trip_vehicle IS NOT NULL THEN
            v_desc := v_desc || ' (' || INITCAP(v_trip_vehicle) || ')';
        END IF;
    END IF;
    
    IF NEW.description IS NOT NULL AND NEW.description != '' THEN
        v_desc := v_desc || chr(10) || NEW.description;
    END IF;

    IF NEW.session_id IS NOT NULL THEN
        v_desc := v_desc || chr(10) || 'GPS Session: ' || COALESCE(v_session_start, 'Start') || ' → ' || COALESCE(v_session_end, 'End');
        IF v_session_km IS NOT NULL THEN
            v_desc := v_desc || ' (' || v_session_km || ' km)';
        END IF;
        v_desc := v_desc || chr(10) || 'Session ID: ' || NEW.session_id;
    END IF;
    
    INSERT INTO requests (
        id, created_at, created_by, title, description, category, status, priority
    ) VALUES (
        NEW.id,
        NEW.created_at,
        NEW.employee_id,
        v_title,
        v_desc,
        'expense_claim',
        'open',
        4
    ) ON CONFLICT (id) DO NOTHING;
    
    RETURN NEW;
END;
$$;

-- Also update the expense_claims sync to generate proper descriptions
CREATE OR REPLACE FUNCTION public.trigger_sync_expense_claim_to_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_emp_name TEXT;
    v_title TEXT;
    v_desc TEXT;
BEGIN
    IF NEW.status != 'draft' THEN
        -- Get employee name
        SELECT name INTO v_emp_name FROM employees WHERE id = NEW.employee_id;
        
        v_title := 'Expense Claim — ₹' || NEW.total_amount;
        v_desc := COALESCE(v_emp_name, 'Employee') || ' submitted an expense claim of ₹' || NEW.total_amount;
        
        IF NEW.notes IS NOT NULL AND NEW.notes != '' THEN
            v_desc := v_desc || chr(10) || NEW.notes;
        END IF;
        
        INSERT INTO requests (
            id, created_at, created_by, title, description, category, status, priority
        ) VALUES (
            NEW.id,
            NEW.created_at,
            NEW.employee_id,
            v_title,
            v_desc,
            'expense_claim',
            'open',
            4
        ) ON CONFLICT (id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

-- Update existing trip expense requests with proper titles (backfill fix)
UPDATE requests r
SET
    title = COALESCE(
        (SELECT 
            CASE te.category
                WHEN 'food_da' THEN 'Food DA'
                WHEN 'hotel' THEN 'Hotel'
                WHEN 'local_travel' THEN 'Local Travel'
                WHEN 'fuel_car' THEN 'Fuel (Car)'
                WHEN 'fuel_bike' THEN 'Fuel (Bike)'
                WHEN 'laundry' THEN 'Laundry'
                WHEN 'toll' THEN 'Toll/Parking'
                WHEN 'internet' THEN 'Internet'
                ELSE INITCAP(REPLACE(te.category, '_', ' '))
            END
            || COALESCE(' — ' || t.from_location || ' → ' || t.to_location, ' Expense')
        FROM trip_expenses te
        LEFT JOIN trips t ON t.id = te.trip_id
        WHERE te.id = r.id),
        r.title
    ),
    description = COALESCE(
        (SELECT 
            COALESCE(e.name, 'Employee') || ' submitted a '
            || CASE te.category
                WHEN 'food_da' THEN 'Food DA'
                WHEN 'hotel' THEN 'Hotel'
                WHEN 'fuel_car' THEN 'Fuel (Car)'
                WHEN 'fuel_bike' THEN 'Fuel (Bike)'
                ELSE INITCAP(REPLACE(te.category, '_', ' '))
            END
            || ' expense of ₹' || te.amount
            || COALESCE(chr(10) || 'Trip: ' || t.from_location || ' → ' || t.to_location, '')
            || COALESCE(chr(10) || te.description, '')
        FROM trip_expenses te
        LEFT JOIN trips t ON t.id = te.trip_id
        LEFT JOIN employees e ON e.id = te.employee_id
        WHERE te.id = r.id),
        r.description
    )
WHERE r.id IN (SELECT id FROM trip_expenses);

-- Also fix existing expense_claims request titles
UPDATE requests r
SET
    title = COALESCE(
        (SELECT 'Expense Claim — ₹' || ec.total_amount
        FROM expense_claims ec
        WHERE ec.id = r.id),
        r.title
    ),
    description = COALESCE(
        (SELECT 
            COALESCE(e.name, 'Employee') || ' submitted an expense claim of ₹' || ec.total_amount
            || COALESCE(chr(10) || ec.notes, '')
        FROM expense_claims ec
        LEFT JOIN employees e ON e.id = ec.employee_id
        WHERE ec.id = r.id),
        r.description
    )
WHERE r.id IN (SELECT id FROM expense_claims);
