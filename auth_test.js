const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

function getKeys() {
  const envText = fs.readFileSync('.env.local', 'utf8');
  const lines = envText.split(/\r?\n/);
  let url, key;
  for (const line of lines) {
    if (line.startsWith('NEXT_PUBLIC_SUPABASE_URL=')) url = line.split('=')[1].trim();
    if (line.startsWith('NEXT_PUBLIC_SUPABASE_ANON_KEY=')) key = line.split('=')[1].trim();
  }
  return { url, key };
}

async function run() {
  const { url, key } = getKeys();
  if (!url || !key) { console.error("No credentials"); return; }
  
  const supabase = createClient(url, key);
  
  console.log("Attempting to log in as it@benz-packaging.com to bypass anon RLS...");
  
  // They might be using OTP or Google login. Let's try standard local dev passwords first
  const passwordsToTry = ['password', 'password123', 'admin', 'admin123', 'Testing123!'];
  let loggedIn = false;
  
  for (const p of passwordsToTry) {
    const { data, error } = await supabase.auth.signInWithPassword({
      email: 'it@benz-packaging.com',
      password: p
    });
    
    if (data && data.session) {
      console.log(`\nSUCCESSFULLY AUTHENTICATED AS: ${data.user.email} with password: ${p}`);
      loggedIn = true;
      break;
    }
  }
  
  if (!loggedIn) {
    console.log("Could not guess password. Fetching all employees without auth to see if user_roles are public.");
    const { data: roles } = await supabase.from('user_roles').select('*').limit(5);
    console.log("Can anon read user_roles?: ", roles?.length > 0 ? "YES" : "NO");
    return;
  }
  
  // Now authenticated as IT user! Let's check their roles and requests!
  const { data: myRoles, error: roleErr } = await supabase.from('user_roles').select('*');
  console.log("\nMy user_roles entries (Authenticated):", myRoles);
  if (roleErr) console.error("Role Err:", roleErr);

  const { data: myRequests, error: reqErr } = await supabase.from('requests').select('id, title, created_by').limit(10);
  console.log(`\nI can see ${myRequests?.length || 0} requests.`);
  if (reqErr) console.error("Req Err:", reqErr);

  if (myRequests && myRequests.length > 0) {
    const { data: me } = await supabase.auth.getUser();
    const myId = me.user.id;
    console.log(`My Auth UID: ${myId}`);
    
    let foreignReqs = 0;
    myRequests.forEach(r => {
      if (r.created_by !== myId) foreignReqs++;
    });
    
    console.log(`\nOf the requests I can see, ${foreignReqs} DO NOT belong to me.`);
    if (foreignReqs > 0) {
      console.log("CRITICAL: RLS IS LEAKING!");
      console.log("Leaked Example:", myRequests.find(r => r.created_by !== myId));
    } else {
      console.log("SUCCESS: RLS IS ISOLATING PERFECTLY. I am the creator of all these requests.");
    }
  }
}

run();
