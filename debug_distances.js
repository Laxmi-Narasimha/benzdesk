const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

// Read .env.local for keys
const envPath = path.join(__dirname, '.env.local');
const envContent = fs.readFileSync(envPath, 'utf8');
const supabaseUrl = envContent.match(/NEXT_PUBLIC_SUPABASE_URL=(.*)/)[1].trim();
const supabaseKey = envContent.match(/NEXT_PUBLIC_SUPABASE_ANON_KEY=(.*)/)[1].trim();

const supabase = createClient(supabaseUrl, supabaseKey);

async function checkDistances() {
  const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });
  const startOfDay = `${today}T00:00:00+05:30`;
  
  console.log(`Checking sessions for today >= ${startOfDay}`);
  const { data: sessions, error: sessErr } = await supabase
    .from('shift_sessions')
    .select('id, employee_id, start_time, total_km, trip_id')
    .gte('start_time', startOfDay)
    .order('start_time', { ascending: false })
    .limit(5);

  if (sessErr) {
    console.error('Session error:', sessErr);
  } else {
    console.log('Today Shift Sessions:', sessions);
  }

  const { data: trips, error: tripsErr } = await supabase
    .from('trips')
    .select('id, employee_id, created_at, from_location, to_location, total_km')
    .gte('created_at', startOfDay)
    .order('created_at', { ascending: false })
    .limit(5);

  if (tripsErr) {
    console.error('Trips error:', tripsErr);
  } else {
    console.log('Today Trips:', trips);
  }
}

checkDistances();
