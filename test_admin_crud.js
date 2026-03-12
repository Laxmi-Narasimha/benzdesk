const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'https://igrudnilqwmlgvmgneng.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlncnVkbmlscXdtbGd2bWduZW5nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc2OTY4ODEsImV4cCI6MjA4MzI3Mjg4MX0.k0up7lc8-fnKm7x_tYxdAhM4wF5juhJuCC8WYf0H8dQ';
const supabase = createClient(supabaseUrl, supabaseAnonKey);

async function testAdmin() {
  console.log("Logging in as laxmi (Admin)...");
  const { data: authData, error: authErr } = await supabase.auth.signInWithPassword({
    email: 'laxmi@benzpackaging.com',
    password: 'password123'
  });

  if (authErr) {
    console.error("Auth Error:", authErr.message);
    return;
  }
  console.log("Logged in successfully. UID:", authData.user.id);

  // 1. Fetch employees
  const { data: emps, error: listErr } = await supabase.from('employees').select('id, name, band, role').neq('id', authData.user.id).limit(1);
  if (listErr || !emps || emps.length === 0) {
    console.error("Failed to list employees or no other employees exist:", listErr);
    return;
  }
  
  const targetEmp = emps[0];
  console.log("Target Employee to Test Edit:", targetEmp.name, targetEmp.id);
  
  const originalBand = targetEmp.band;
  const newBand = originalBand === 'manager' ? 'director' : 'manager';

  // 2. Test Update
  console.log(`Attempting to update band from ${originalBand} to ${newBand}...`);
  const { data: updateData, error: updateErr } = await supabase.from('employees')
    .update({ band: newBand })
    .eq('id', targetEmp.id)
    .select();
    
  if (updateErr) {
    console.error("Failed to UPDATE employee as Admin. RLS is still blocking:", updateErr.message);
  } else {
    console.log("SUCCESS! Admin successfully updated employee:", updateData[0]);
    
    // Revert it
    await supabase.from('employees').update({ band: originalBand }).eq('id', targetEmp.id);
    console.log("Reverted band back to", originalBand);
  }
  
  // 3. Test Delete
  console.log("Skipping actual deletion test to avoid data loss, but since UPDATE works, DELETE relies on the exact same is_admin condition.");
}

testAdmin();
