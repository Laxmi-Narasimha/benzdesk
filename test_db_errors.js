const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

const supabaseUrl = 'https://igrudnilqwmlgvmgneng.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlncnVkbmlscXdtbGd2bWduZW5nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc2OTY4ODEsImV4cCI6MjA4MzI3Mjg4MX0.k0up7lc8-fnKm7x_tYxdAhM4wF5juhJuCC8WYf0H8dQ';
const supabase = createClient(supabaseUrl, supabaseAnonKey);

async function testErrors() {
  console.log("Logging in as laxmi (Admin)...");
  const { data: authData, error: authErr } = await supabase.auth.signInWithPassword({
    email: 'laxmi@benzpackaging.com',
    password: 'password123'
  });

  if (authErr) {
    console.error("Auth Error:", authErr.message);
    return;
  }

  // Test 1: Update request status
  console.log("\\n--- Testing Request Update ---");
  const { data: reqs } = await supabase.from('requests').select('id, status').limit(1);
  if (reqs && reqs.length > 0) {
    const reqId = reqs[0].id;
    console.log(`Updating request ${reqId} from ${reqs[0].status} to 'approved'`);
    const { error: reqErr } = await supabase.from('requests').update({ status: 'approved' }).eq('id', reqId);
    if (reqErr) {
      console.error("Request Update Error:", reqErr);
    } else {
      console.log("Request updated successfully.");
    }
  }

  // Test 2: Update employee band
  console.log("\\n--- Testing Employee Update ---");
  const { data: emps } = await supabase.from('employees').select('id, name, band, role').eq('name', 'laxmi').limit(1);
  if (emps && emps.length > 0) {
    const emp = emps[0];
    console.log(`Updating employee ${emp.name} (role: ${emp.role}) to band 'manager'`);
    const { error: empErr } = await supabase.from('employees').update({ band: 'manager', role: emp.role }).eq('id', emp.id);
    if (empErr) {
      console.error("Employee Update Error:", empErr);
    } else {
      console.log("Employee updated successfully.");
    }
  }
}

testErrors();
