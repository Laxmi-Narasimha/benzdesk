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
    const res = await fetch(`${url}/rest/v1/requests?select=id,title,category,created_by,created_at&order=created_at.desc&limit=10`, {
      headers: { 'apikey': key, 'Authorization': `Bearer ${key}` }
    });
    const requests = await res.json();
    
    console.log(`IT User ID: ${IT_USER_ID}`);
    console.log("\nLast 10 Requests:");
    requests.forEach(r => {
      const isOwned = r.created_by === IT_USER_ID;
      console.log(`- ${r.title} (${r.category}) | Creator: ${r.created_by} | Owned by IT User? ${isOwned ? 'YES' : 'NO'}`);
    });
    
  } catch (err) {
    console.error(err);
  }
}

run();
