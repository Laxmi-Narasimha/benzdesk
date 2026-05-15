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
  
  try {
    // We are looking for the 'Trip Expense Claim' with title containing '02814243'
    const res = await fetch(`${url}/rest/v1/requests?select=id,title,created_by,category&title=ilike.*02814243*`, {
      headers: { 'apikey': key, 'Authorization': `Bearer ${key}` }
    });
    const requests = await res.json();
    console.log("Found requests matching '02814243':", JSON.stringify(requests, null, 2));
    
  } catch (err) {
    console.error(err);
  }
}

run();
