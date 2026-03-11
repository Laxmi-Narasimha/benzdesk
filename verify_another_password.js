const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'https://igrudnilqwmlgvmgneng.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlncnVkbmlscXdtbGd2bWduZW5nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc2OTY4ODEsImV4cCI6MjA4MzI3Mjg4MX0.k0up7lc8-fnKm7x_tYxdAhM4wF5juhJuCC8WYf0H8dQ';

const supabase = createClient(supabaseUrl, supabaseKey);

async function testLogin() {
    console.log('Testing login with "benz" password...');
    const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
        email: 'sales7@benz-packaging.com',
        password: 'benz',
    });

    if (authError) {
        console.error('Login Failed with "benz":', authError.message);
        process.exit(1);
    } else {
        console.log('Login Succeeded with "benz"!', authData.user.id);
        process.exit(0);
    }
}

testLogin();
