-- Missing categories breaking mobile fuel expense logs
ALTER TABLE IF EXISTS public.expense_items 
    DROP CONSTRAINT IF EXISTS expense_items_category_check;

ALTER TABLE IF EXISTS public.expense_items
    ADD CONSTRAINT expense_items_category_check CHECK (
        category IN (
            'local_conveyance', 'fuel', 'toll', 'outstation_travel',
            'food_da', 'food', 'accommodation', 'laundry',
            'internet', 'mobile',
            'petty_cash', 'advance_request', 'stationary', 'medical',
            'travel_allowance', 'transport_expense', 'mobile_internet',
            'other', 'fuel_bike', 'fuel_car'
        )
    );