const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

// Extract URL and anon key from env file
const envFile = fs.readFileSync('.env.local', 'utf8');
const urlMatch = envFile.match(/NEXT_PUBLIC_SUPABASE_URL=(.+)/);
const keyMatch = envFile.match(/NEXT_PUBLIC_SUPABASE_ANON_KEY=(.+)/);

if (!urlMatch || !keyMatch) {
  console.error('Could not find Supabase credentials in .env.local');
  process.exit(1);
}

const supabase = createClient(urlMatch[1], keyMatch[1]);

async function checkConfig() {
  console.log('Querying requests...');
  
  // 1. Fetch random requests to see if we get them all
  const { data: allRequests, error: err1 } = await supabase
    .from('requests')
    .select('id, created_by, title')
    .limit(5);
    
  console.log('Direct requests query (anon/not logged in):', allRequests?.length, 'rows');
  if (err1) console.error(err1);

  // 2. Fetch requests_with_creator
  const { data: viewRequests, error: err2 } = await supabase
    .from('requests_with_creator')
    .select('id, created_by, title')
    .limit(5);
    
  console.log('View requests query (anon):', viewRequests?.length, 'rows');
  if (err2) console.error(err2);
}

checkConfig();
