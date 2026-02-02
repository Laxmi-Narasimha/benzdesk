
const { createClient } = require('@supabase/supabase-js');

// Config
const SUPABASE_URL = 'https://igrudnilqwmlgvmgneng.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlncnVkbmlscXdtbGd2bWduZW5nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc2OTY4ODEsImV4cCI6MjA4MzI3Mjg4MX0.k0up7lc8-fnKm7x_tYxdAhM4wF5juhJuCC8WYf0H8dQ';

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

async function diagnose() {
    console.log('--- BenzMobiTraq Data Diagnosis ---\n');

    try {
        // 1. Check Specific Session from User Log
        const targetSessionId = 'cdf28034-e488-481c-a6b4-99c86a29bff5';
        console.log(`Checking Target Session: ${targetSessionId}...`);

        const { data: session, error: sessionError } = await supabase
            .from('shift_sessions')
            .select('*')
            .eq('id', targetSessionId)
            .maybeSingle();

        if (sessionError) {
            console.error('Error fetching session:', sessionError);
        } else if (!session) {
            console.log('Session NOT found in database yet.');
        } else {
            console.log('Session Found:', {
                id: session.id,
                status: session.status,
                start_time: session.start_time,
                total_km: session.total_km
            });

            // Check points for this session
            const { count, error: pointsError } = await supabase
                .from('location_points')
                .select('*', { count: 'exact', head: true })
                .eq('session_id', targetSessionId);

            if (pointsError) {
                console.error('Error fetching points:', pointsError);
            } else {
                console.log(`Location Points for Session: ${count}`);
            }
        }

        console.log('\n--------------------------------\n');

        // 2. Check for Stuck/Stale Sessions
        console.log('Checking for Stuck Active Sessions (> 12 hours)...');
        const twelveHoursAgo = new Date(Date.now() - 12 * 60 * 60 * 1000).toISOString();

        const { data: stuckSessions, error: stuckError } = await supabase
            .from('shift_sessions')
            .select('id, employee_id, start_time, status')
            .eq('status', 'active')
            .lt('start_time', twelveHoursAgo);

        if (stuckError) {
            console.error('Error checking stuck sessions:', stuckError);
        } else {
            if (stuckSessions.length === 0) {
                console.log('No stuck sessions found.');
            } else {
                console.log(`Found ${stuckSessions.length} stuck sessions:`);
                stuckSessions.forEach(s => console.log(`- ID: ${s.id}, Started: ${s.start_time}`));
            }
        }

    } catch (err) {
        console.error('Unexpected error:', err);
    }
}

async function recalculateForSession(sessionId) {
    console.log(`  -> Attempting recalculation for ${sessionId}...`);

    // Fetch all points
    const { data: points, error } = await supabase
        .from('location_points')
        .select('latitude, longitude, recorded_at')
        .eq('session_id', sessionId)
        .order('recorded_at', { ascending: true });

    if (error || !points) return console.error('Failed to fetch points');

    let totalDist = 0;
    for (let i = 1; i < points.length; i++) {
        totalDist += getDistanceFromLatLonInKm(
            points[i - 1].latitude, points[i - 1].longitude,
            points[i].latitude, points[i].longitude
        );
    }

    console.log(`  -> Calculated Distance: ${totalDist.toFixed(2)} km`);

    // Attempt update (Might fail due to RLS if we are Anon)
    /* 
       NOTE: We likely cannot WRITE to shift_sessions with Anon key unless RLS allows it.
       If this fails, we confirm the issue is lack of permissions for the script,
       and the user MUST run the SQL in their dashboard.
    */
    const { error: updateError } = await supabase
        .from('shift_sessions')
        .update({ total_km: totalDist })
        .eq('id', sessionId);

    if (updateError) {
        console.error('  -> Update Failed (Expected if RLS blocks Anon):', updateError.message);
        console.log('  -> ACTION: Please run migration 023_backfill_session_km.sql in Supabase Dashboard.');
    } else {
        console.log('  -> Update SUCCESS!');
    }
}

function getDistanceFromLatLonInKm(lat1, lon1, lat2, lon2) {
    var R = 6371; // Radius of the earth in km
    var dLat = deg2rad(lat2 - lat1);  // deg2rad below
    var dLon = deg2rad(lon2 - lon1);
    var a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2)
        ;
    var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    var d = R * c; // Distance in km
    return d;
}

function deg2rad(deg) {
    return deg * (Math.PI / 180)
}

diagnose();
