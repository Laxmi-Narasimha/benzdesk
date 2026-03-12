const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

const supabaseUrl = 'https://igrudnilqwmlgvmgneng.supabase.co';
const envFile = fs.readFileSync('c:\\\\Users\\\\user\\\\benzdesk\\\\.env.local', 'utf8');
const serviceKeyLine = envFile.split('\\n').find(line => line.startsWith('SUPABASE_SERVICE_ROLE_KEY='));
let serviceKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlncnVkbmlscXdtbGd2bWduZW5nIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NzY5Njg4MSwiZXhwIjoyMDgzMjcyODgxfQ.Qp4_Q4c0kYn-v7vY_xV4_Aqk-qXQ_uP2K_F_G5k_L1Y"; 

const supabase = createClient(supabaseUrl, serviceKey);

async function testErrors() {
  console.log("--- Testing Request Update (Simulating Admin Update) ---");
  const { data: reqs } = await supabase.from('requests').select('id, status').limit(1);
  if (reqs && reqs.length > 0) {
    const reqId = reqs[0].id;
    console.log(`Updating request ${reqId} from ${reqs[0].status} to 'approved'`);
    const { error: reqErr } = await supabase.from('requests').update({ status: 'approved' }).eq('id', reqId);
    if (reqErr) {
        console.error("Request Update Error:", reqErr);
    } else {
        console.log("Request updated successfully (Service Role). If this works, the issue is strictly RLS.");
    }
    await supabase.from('requests').update({ status: reqs[0].status }).eq('id', reqId); // Revert
  }

  console.log("\\n--- Testing Employee Band Update (Simulating Admin Update) ---");
  const { data: emps } = await supabase.from('employees').select('id, name, band, role').eq('name', 'laxmi').limit(1);
  if (emps && emps.length > 0) {
    const emp = emps[0];
    console.log(`Updating employee ${emp.name} (role: ${emp.role}) to band 'manager' with role '${emp.role}'`);
    const { error: empErr } = await supabase.from('employees').update({ band: 'manager', role: emp.role }).eq('id', emp.id);
    if (empErr) {
        console.error("Employee Update Error:", empErr);
    } else {
        console.log("Employee updated successfully.");
        await supabase.from('employees').update({ band: emp.band }).eq('id', emp.id); // Revert
    }
  } else {
    // try to get any employee
    const { data: emps2 } = await supabase.from('employees').select('id, name, band, role').limit(1);
    const emp = emps2[0];
    console.log(`Updating employee ${emp.name} to role 'super_admin' to test trigger`);
    const { error: empErr2 } = await supabase.from('employees').update({ role: 'super_admin' }).eq('id', emp.id);
    console.error("Employee Update Error (super_admin test):", empErr2);
  }
}

testErrors();
