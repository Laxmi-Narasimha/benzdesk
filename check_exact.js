const fs = require('fs');
const https = require('https');

function getKeys() {
  const envText = fs.readFileSync('.env.local', 'utf8');
  const lines = envText.split(/\r?\n/);
  let url, key;
  for (const line of lines) {
    if (line.startsWith('NEXT_PUBLIC_SUPABASE_URL=')) url = line.split('=')[1].trim();
    if (line.startsWith('SUPABASE_SERVICE_ROLE_KEY=')) key = line.split('=')[1].trim();
    if (!key && line.startsWith('NEXT_PUBLIC_SUPABASE_ANON_KEY=')) key = line.split('=')[1].trim();
  }
  return { url, key };
}

async function run() {
  const { url, key } = getKeys();
  if (!url || !key) return;
  
  const IT_USER_ID = "28c2920d-6bd3-4696-b630-981fb4431f8e";
  
  try {
    // Look up the specific requests from the screenshot using the descriptions/titles
    const res = await fetch(`${url}/rest/v1/requests?description=ilike.*02814243*&select=id,title,created_by,description`, {
      headers: { 'apikey': key, 'Authorization': `Bearer ${key}` }
    });
    
    const res2 = await fetch(`${url}/rest/v1/requests?description=ilike.*e7d44ed1*&select=id,title,created_by,description`, {
      headers: { 'apikey': key, 'Authorization': `Bearer ${key}` }
    });
    
    const reqs1 = await res.json();
    const reqs2 = await res2.json();
    
    console.log(`IT User ID: ${IT_USER_ID}`);
    const checkReqs = [...reqs1, ...reqs2];
    
    checkReqs.forEach(r => {
      const isIT = r.created_by === IT_USER_ID;
      console.log(`\nRequest: ${r.title}\nID found in Desc: ${r.description.substring(0, 50)}\nCreated By: ${r.created_by}\nIs IT User? ${isIT ? 'YES !!!' : 'NO'}`);
    });
    
  } catch (err) {
    console.error(err);
  }
}

run();
