const { Client } = require('pg');
const fs = require('fs');

async function run() {
  const connectionString = "postgresql://postgres:Mobipackaging111!@db.igrudnilqwmlgvmgneng.supabase.co:5432/postgres";
  const client = new Client({ connectionString });
  
  try {
    await client.connect();
    console.log("Connected to Supabase.");

    const sqlFix = fs.readFileSync('infra/supabase/migrations/20261231000001_sync_requests_to_mobile_notifications.sql', 'utf8');
    console.log("Running 20261231000001_sync_requests_to_mobile_notifications.sql...");
    await client.query(sqlFix);
    console.log("20260312104500_sync_requests_to_mobile_notifications.sql applied successfully.");

  } catch (err) {
    console.error("Error executing migrations:", err);
  } finally {
    await client.end();
    console.log("Disconnected.");
  }
}

run();
