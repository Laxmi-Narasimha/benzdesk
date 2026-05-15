const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

const envFile = fs.readFileSync('.env.local', 'utf8');
const urlMatch = envFile.match(/NEXT_PUBLIC_SUPABASE_URL=(.+)/);
const keyMatch = envFile.match(/NEXT_PUBLIC_SUPABASE_ANON_KEY=(.+)/);

if (!urlMatch || !keyMatch) {
  console.error('Could not find Supabase credentials');
  process.exit(1);
}

const supabaseUrl = urlMatch[1].trim();
const supabaseKey = keyMatch[1].trim();

const supabase = createClient(supabaseUrl, supabaseKey);

async function exportRequests() {
  console.log("Logging in as admin...");
  const { data: auth, error: authErr } = await supabase.auth.signInWithPassword({
    email: 'dinesh@benz-packaging.com',
    password: 'BenzDesk2026!'
  });

  if (authErr) {
    console.error("Login failed:", authErr.message);
    return;
  }
  
  // Find all open requests
  const { data: openRequests, error: rErr } = await supabase
    .from('requests')
    .select('*')
    .neq('status', 'closed');

  if (rErr) {
    console.error("Error fetching requests:", rErr);
    return;
  }

  // Get all employees
  const { data: employees, error: eErr } = await supabase
    .from('employees')
    .select('id, name, email');
    
  if (eErr) {
    console.error("Error fetching employees:", eErr);
    return;
  }

  // Map employee info to requests
  const requestsWithEmployee = openRequests.map(r => {
    const emp = employees.find(e => e.id === r.created_by);
    return { ...r, employees: emp };
  });

  // Filter for Laxmi
  const laxmiRequests = requestsWithEmployee.filter(req => {
    // Check if employee name or email contains laxmi
    const emp = req.employees;
    if (emp) {
      const name = (emp.name || '').toLowerCase();
      const email = (emp.email || '').toLowerCase();
      return name.includes('laxmi') || email.includes('laxmi');
    }
    return false;
  });

  console.log(`Found ${laxmiRequests.length} open requests for Laxmi.`);
  
  if (laxmiRequests.length === 0) {
    console.log("Printing some open requests to see what is there:");
    console.log(requestsWithEmployee.slice(0, 3).map(r => ({ id: r.id, title: r.title, createdByEmail: r.employees?.email })));
    return;
  }

  // Format as CSV
  const header = ['ID', 'Title', 'Description', 'Category', 'Priority', 'Status', 'Created At', 'Requester Name', 'Requester Email']
  const rows = laxmiRequests.map(r => {
    return [
      r.id,
      r.title,
      r.description,
      r.category,
      r.priority,
      r.status,
      r.created_at,
      r.employees?.name,
      r.employees?.email
    ].map(val => {
      if (val === null || val === undefined) return '';
      const strVal = String(val).replace(/"/g, '""').replace(/\n/g, ' ');
      return `"${strVal}"`;
    }).join(',');
  });

  const csvContent = header.join(',') + '\n' + rows.join('\n');
  const filePath = path.join(__dirname, 'Laxmi_Open_Requests.csv');
  
  fs.writeFileSync(filePath, csvContent);
  console.log(`\nSuccessfully saved export to: ${filePath}`);
}

exportRequests();
