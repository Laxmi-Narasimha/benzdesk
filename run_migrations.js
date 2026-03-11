const { Client } = require('pg');
const fs = require('fs');

async function run() {
  const connectionString = "postgresql://postgres.igrudnilqwmlgvmgneng:Mobipackaging111!@aws-0-ap-south-1.pooler.supabase.com:6543/postgres";
  const client = new Client({ connectionString });
  
  try {
    await client.connect();
    console.log("Connected to Supabase.");

    const sql042 = fs.readFileSync('infra/supabase/migrations/042_elegant_redesign_db_fixes.sql', 'utf8');
    console.log("Running 042_elegant_redesign_db_fixes.sql...");
    await client.query(sql042);
    console.log("042_elegant_redesign_db_fixes.sql applied successfully.");

  } catch (err) {
    console.error("Error executing migrations:", err);
  } finally {
    await client.end();
    console.log("Disconnected.");
  }
}

run();
