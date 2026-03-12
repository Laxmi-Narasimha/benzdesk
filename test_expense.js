const { Client } = require('pg');

async function testExpenseTrigger() {
  const connectionString = "postgresql://postgres.igrudnilqwmlgvmgneng:Mobipackaging111!@aws-0-ap-south-1.pooler.supabase.com:6543/postgres";
  const client = new Client({ connectionString });
  
  try {
    await client.connect();
    console.log("Connected to Supabase DB directly.");

    console.log("Running migration manually via test_expense.js...");
    const fs = require('fs');
    const sql = fs.readFileSync('infra/supabase/migrations/20261231000001_sync_requests_to_mobile_notifications.sql', 'utf8');
    await client.query(sql);
    console.log("Migration executed successfully!");

  } catch (e) {
      console.error(e);
  } finally {
      await client.end();
  }
}

testExpenseTrigger();
