// Apply migration 033 directly to Supabase
// Run: node apply_033.js

const fs = require('fs');
const path = require('path');

// Read env file
const envPath = path.join(__dirname, '.env.local');
const envContent = fs.readFileSync(envPath, 'utf8');
const envVars = {};
envContent.split('\n').forEach(line => {
    const [key, ...vals] = line.split('=');
    if (key && !key.startsWith('#')) {
        envVars[key.trim()] = vals.join('=').trim();
    }
});

const SUPABASE_URL = envVars['NEXT_PUBLIC_SUPABASE_URL'];
const SERVICE_KEY = envVars['SUPABASE_SERVICE_ROLE_KEY'] || envVars['NEXT_PUBLIC_SUPABASE_ANON_KEY'];

const SQL = `
-- Allow admins and directors to delete comments
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'request_comments' 
        AND policyname = 'Admins can delete comments'
    ) THEN
        EXECUTE 'CREATE POLICY "Admins can delete comments"
          ON request_comments
          FOR DELETE
          USING (has_any_role(ARRAY[''accounts_admin'', ''director'']::app_role[]))';
    END IF;
END$$;

-- Allow admins and directors to delete attachment records
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'request_attachments' 
        AND policyname = 'Admins can delete attachments'
    ) THEN
        EXECUTE 'CREATE POLICY "Admins can delete attachments"
          ON request_attachments
          FOR DELETE
          USING (has_any_role(ARRAY[''accounts_admin'', ''director'']::app_role[]))';
    END IF;
END$$;

-- Allow requesters to delete their own uploaded attachments
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'request_attachments' 
        AND policyname = 'Uploaders can delete own attachments'
    ) THEN
        EXECUTE 'CREATE POLICY "Uploaders can delete own attachments"
          ON request_attachments
          FOR DELETE
          USING (uploaded_by = auth.uid())';
    END IF;
END$$;
`;

async function applyMigration() {
    console.log('Applying migration 033 to:', SUPABASE_URL);

    // Use the REST endpoint for SQL queries  
    const projectRef = SUPABASE_URL.replace('https://', '').replace('.supabase.co', '');

    // Try the management API approach
    const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'apikey': SERVICE_KEY,
            'Authorization': `Bearer ${SERVICE_KEY}`,
        },
        body: JSON.stringify({ query: SQL }),
    });

    if (!response.ok) {
        const text = await response.text();
        console.log('REST API response:', text);
        console.log('\nPlease apply the following SQL manually in your Supabase Dashboard SQL Editor:');
        console.log('https://supabase.com/dashboard/project/' + projectRef + '/sql/new');
        console.log('\n--- COPY THIS SQL ---\n');
        console.log(fs.readFileSync('./supabase/migrations/033_admin_delete_policies.sql', 'utf8'));
        console.log('\n--- END SQL ---');
    } else {
        console.log('Migration applied successfully!');
    }
}

applyMigration().catch(err => {
    console.error('Error:', err.message);
    const SUPABASE_URL_val = SUPABASE_URL || '';
    const projectRef = SUPABASE_URL_val.replace('https://', '').replace('.supabase.co', '');
    console.log('\nPlease apply the SQL manually in your Supabase Dashboard:');
    console.log('https://supabase.com/dashboard/project/' + projectRef + '/sql/new');
    console.log('\n--- COPY THIS SQL ---\n');
    console.log(fs.readFileSync('./supabase/migrations/033_admin_delete_policies.sql', 'utf8'));
});
