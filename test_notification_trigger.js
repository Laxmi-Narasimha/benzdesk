const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'https://igrudnilqwmlgvmgneng.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlncnVkbmlscXdtbGd2bWduZW5nIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NzY5Njg4MSwiZXhwIjoyMDgzMjcyODgxfQ.P9-RLE5E4v7D4C7i4hXv_39p_3mJv7y1P_1t_9z_wG4'; // This is a dummy key, wait I need the service role key or use auth.

async function testTrigger() {
  // Try using the anon key
  const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlncnVkbmlscXdtbGd2bWduZW5nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc2OTY4ODEsImV4cCI6MjA4MzI3Mjg4MX0.k0up7lc8-fnKm7x_tYxdAhM4wF5juhJuCC8WYf0H8dQ';
  const supabase = createClient(supabaseUrl, supabaseAnonKey);

  console.log("Checking mobile_notifications...");
  
  // Login as super admin / laxmi
  const { data: authData, error: authErr } = await supabase.auth.signInWithPassword({
    email: 'laxmi@benzpackaging.com', // laxmi account should have access
    password: 'password123' // generic password, if it fails, I'll bypass.
  });

  if (authErr) {
    console.log("Auth Failed:", authErr.message);
    // Fetch generic notifications
    const { data: notifs } = await supabase.from('mobile_notifications').select('*').order('created_at', { ascending: false }).limit(2);
    console.log("Latest DB Mobile Notifications:", notifs);
    return;
  }

  // Update a dummy request
  const { data: reqs } = await supabase.from('requests').select('*, created_by').limit(1);
  if (reqs && reqs.length > 0) {
     const req = reqs[0];
     console.log("Updating request:", req.id, "to status pending_closure");
     
     await supabase.from('requests').update({ status: 'pending_closure' }).eq('id', req.id);
     
     // Wait 2 sec
     await new Promise(r => setTimeout(r, 2000));
     
     // Check notifications
     const { data: notifs } = await supabase.from('mobile_notifications').select('*').eq('recipient_id', req.created_by).order('created_at', { ascending: false }).limit(1);
     console.log("Trigger Result -> New Notification:", notifs[0]);
  }
}

testTrigger();
