const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

const envPath = path.join(__dirname, '.env.local');
const envContent = fs.readFileSync(envPath, 'utf8');
const supabaseUrl = envContent.match(/NEXT_PUBLIC_SUPABASE_URL=(.*)/)[1].trim();
const supabaseKey = envContent.match(/NEXT_PUBLIC_SUPABASE_ANON_KEY=(.*)/)[1].trim();
const supabase = createClient(supabaseUrl, supabaseKey);

async function checkPoints() {
  const { data: points, error } = await supabase
    .from('location_points')
    .select('id, session_id, latitude, longitude, recorded_at')
    .order('recorded_at', { ascending: false })
    .limit(10);
  console.log('Latest 10 Location Points:', points);
}
checkPoints();
