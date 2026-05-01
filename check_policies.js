const { createClient } = require('@supabase/supabase-js');

// Initialize with environment variables or default local credentials
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || 'http://127.0.0.1:54321';
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

async function checkPolicies() {
  try {
    // Run direct postgres query on the local DB using the psql command string
    const { execSync } = require('child_process');
    const output = execSync('npx supabase db psql -c "SELECT policyname, permissive, roles, cmd, qual, with_check FROM pg_policies WHERE tablename = \'requests\';"').toString();
    console.log(output);
  } catch (error) {
    console.error("Error executing query:", error.message);
  }
}

checkPolicies();
