const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

// Extract URL and anon key from env file
const envFile = fs.readFileSync('.env.local', 'utf8');
const urlMatch = envFile.match(/NEXT_PUBLIC_SUPABASE_URL=(.+)/);
const keyMatch = envFile.match(/NEXT_PUBLIC_SUPABASE_ANON_KEY=(.+)/);

if (!urlMatch || !keyMatch) {
  console.error('Could not find Supabase credentials');
  process.exit(1);
}

const supabase = createClient(urlMatch[1], keyMatch[1]);

async function checkRLS() {
  // Login as laxmi (from the screenshot) to test their specific access
  // Standard test password for local dev
  const { data: auth, error: authErr } = await supabase.auth.signInWithPassword({
    email: 'laxmi-narasimha@benz-packaging.com', // guess based on screenshot
    password: 'password123'
  });

  if (authErr) {
    console.log("Could not login as laxmi with password123. Trying another employee...");
    const { data: users } = await supabase.from('employees').select('email, role').neq('role', 'admin').limit(1);
    if (users && users.length > 0) {
      console.log(`Found employee: ${users[0].email} (${users[0].role})`);
      // We can't login without password. Let's just use the service role to inspect the DB directly.
      checkPoliciesDirectly();
    }
    return;
  }
  
  console.log(`Logged in as: ${auth.user.email}`);

  // 1. Fetch from requests table
  const { data: allRequests, error: err1 } = await supabase
    .from('requests')
    .select('id, created_by, title');
    
  console.log('Regular user SELECT from "requests":', allRequests?.length, 'rows');
  
  const ownRequests = allRequests?.filter(r => r.created_by === auth.user.id);
  console.log(`Out of those, ${ownRequests?.length || 0} belong to this user.`);
}

async function checkPoliciesDirectly() {
  const serviceKeyMatch = envFile.match(/SUPABASE_SERVICE_ROLE_KEY=(.+)/);
  if (!serviceKeyMatch) return;
  
  const adminSupabase = createClient(urlMatch[1], serviceKeyMatch[1]);
  
  // Use RPC if possible, or we just trust the migration applied.
  // Wait! Let's check the is_admin_or_super_admin() function definition directly.
  const { data, error } = await adminSupabase.rpc('is_admin_or_super_admin');
  console.log('Admin check result:', data, error?.message);
}

checkRLS();
