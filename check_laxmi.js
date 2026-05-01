const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

// Extract URL and service key from local config files if not in env
// In local supabase development, anon key and service key are usually standard
const supabaseUrl = 'http://127.0.0.1:54321';
// This is the default local service role key used by Supabase CLI
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRlZmF1bHQiLCJyb2xlIjoic2VydmljZV9yb2xlIiwiaWF0IjoxNjE2MDcxMjAwLCJleHAiOjE5MzE2NDcyMDB9.Vn3gI_29FpP2xS4C2T-5C4n36O5Tpx-A_2H5oA_2H5o'; 


async function checkLaxmiView() {
  const supabase = createClient(supabaseUrl, serviceKey);
  
  // Find laxmi's user ID
  const { data: users, error: uErr } = await supabase.from('employees').select('id, email, name, role').ilike('name', '%laxmi%');
  if (uErr) { console.error("Error fetching employee:", uErr); return; }
  if (!users || users.length === 0) {
    console.log("Could not find Laxmi in employees table.");
    return;
  }
  
  const laxmi = users[0];
  console.log(`Checking DB for: ${laxmi.name} (${laxmi.email}) [Role: ${laxmi.role}] ID: ${laxmi.id}`);

  // Check laxmi's user_roles!
  const { data: roles, error: rErr } = await supabase.from('user_roles').select('*').eq('user_id', laxmi.id);
  if (rErr) console.error("Error fetching roles:", rErr);
  console.log('Laxmi user_roles entries:', roles);
  
  // Check the admin bypass function result specifically for this user id
  // Since we are service role we can't easily impersonate for RPC, but we can check the tables the RPC checks
}

checkLaxmiView();
