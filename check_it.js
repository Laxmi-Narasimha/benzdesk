const fs = require('fs');
const https = require('https');

const env = fs.readFileSync('.env.local', 'utf8');
const urlMatch = env.match(/NEXT_PUBLIC_SUPABASE_URL=(.+)/);
const keyMatch = env.match(/SUPABASE_SERVICE_ROLE_KEY=(.+)/);

if (!urlMatch || !keyMatch) { console.error('No keys'); process.exit(1); }

const url = urlMatch[1].trim();
const key = keyMatch[1].trim();

async function run() {
  try {
    const empRes = await fetch(`${url}/rest/v1/employees?email=eq.it@benz-packaging.com&select=id,email,name,role`, {
      headers: { 'apikey': key, 'Authorization': `Bearer ${key}` }
    });
    const emps = await empRes.json();
    console.log("IT employee record:", emps);
    
    if (emps.length > 0) {
      const rRes = await fetch(`${url}/rest/v1/user_roles?user_id=eq.${emps[0].id}&select=*`, {
        headers: { 'apikey': key, 'Authorization': `Bearer ${key}` }
      });
      console.log("IT user_roles:", await rRes.json());
    }
  } catch (e) {
    console.error("Fetch failed", e);
  }
}
run();
