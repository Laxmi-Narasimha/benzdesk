
-- Check specific session
SELECT * FROM shift_sessions WHERE id = 'cdf28034-e488-481c-a6b4-99c86a29bff5';

-- Check location points for this session
SELECT count(*) as point_count, min(recorded_at), max(recorded_at) 
FROM location_points 
WHERE session_id = 'cdf28034-e488-481c-a6b4-99c86a29bff5';
