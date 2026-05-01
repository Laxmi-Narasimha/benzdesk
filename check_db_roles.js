const fs = require('fs');
const https = require('https');

function getKeys() {
  const envText = fs.readFileSync('.env.local', 'utf8');
  const lines = envText.split(/\r?\n/);
  let url, key;
  for (const line of lines) {
    if (line.startsWith('NEXT_PUBLIC_SUPABASE_URL=')) url = line.split('=')[1].trim();
    if (line.startsWith('SUPABASE_SERVICE_ROLE_KEY=')) key = line.split('=')[1].trim();
    if (line.startsWith('NEXT_PUBLIC_SUPABASE_ANON_KEY=')) {
      if (!key) key = line.split('=')[1].trim(); // Fallback to anon key if no service key
    }
  }
  return { url, key };
}

async function run() {
  const { url, key } = getKeys();
  if (!url || !key) { console.log("Missing keys"); return; }
  
  // Use global fetch
  console.log(`Checking IT user on ${url}...`);
  try {
    const res = await fetch(`${url}/rest/v1/employees?email=eq.it@benz-packaging.com&select=*`, {
      headers: { 'apikey': key, 'Authorization': `Bearer ${key}` }
    });
    const emps = await res.json();
    console.log("Employees table output for IT user:", JSON.stringify(emps, null, 2));
    
    if (emps.length > 0) {
      const uRes = await fetch(`${url}/rest/v1/user_roles?user_id=eq.${emps[0].id}&select=*`, {
        headers: { 'apikey': key, 'Authorization': `Bearer ${key}` }
      });
      const roles = await uRes.json();
      console.log("user_roles table output for IT user:", JSON.stringify(roles, null, 2));
    }
  } catch (err) {
    console.error(err);
  }
}

run();
