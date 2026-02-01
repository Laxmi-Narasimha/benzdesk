// ============================================================================
// Expense Claim Detail Page (Server Component Wrapper)
// Required for static export with dynamic route
// ============================================================================

import ExpenseClaimClient from './client';

// For static export: return empty array to use client-side routing
export function generateStaticParams() {
    return [];
}

// Allow dynamic params for client-side navigation
export const dynamicParams = true;

export default function ExpenseClaimPage() {
    return <ExpenseClaimClient />;
}
