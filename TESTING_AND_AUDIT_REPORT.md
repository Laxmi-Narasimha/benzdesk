# BenzDesk Testing & Audit Report

**Date:** 2024-05-23
**Auditor:** Jules (AI Software Engineer)
**Scope:** Full Codebase Review for Industry-Grade Readiness

---

## Executive Summary

After a comprehensive review of the BenzDesk codebase, database schema, and security implementation, I have identified **one critical functional blocker** and **several major security gaps** that prevent this application from being considered "industry-grade" or even fully functional.

While the backend RLS policies and audit logging triggers are robust (excellent work there), the frontend integration with these security features is largely missing or incomplete. Furthermore, a database constraint mismatch will cause the core feature (Request Creation) to fail for most users.

---

## 1. CRITICAL: Database Constraint Mismatch (Functional Blocker)

**Severity:** 🔴 **Critical** (App will not work)

The TypeScript application uses a specific set of categories (e.g., `expense_reimbursement`, `purchase_order`), but the Database `requests` table enforces a `CHECK` constraint with a completely different set of outdated values.

-   **TypeScript (`types/index.ts`):**
    `['expense_reimbursement', 'salary_payroll', 'purchase_order', 'delivery_challan', 'invoice_query', 'gst_tax_query', ...]`
-   **Database (`infra/supabase/migrations/001_init.sql`):**
    `CONSTRAINT valid_category CHECK (category IN ('invoice', 'reimbursement', 'vendor_payment', 'salary_query', ...))`

**Impact:**
Any attempt to create a request with a category like "Expense Reimbursement" or "Purchase Order" will fail with a database error (`new row for relation "requests" violates check constraint "valid_category"`).

**Recommendation:**
You must run a migration to drop and recreate this constraint with the correct values matching `types/index.ts`.

```sql
ALTER TABLE requests DROP CONSTRAINT valid_category;
ALTER TABLE requests ADD CONSTRAINT valid_category CHECK (
  category IN (
    'expense_reimbursement', 'salary_payroll', 'purchase_order',
    'delivery_challan', 'invoice_query', 'vendor_payment',
    'travel_allowance', 'transport_expense', 'gst_tax_query',
    'bank_account_update', 'advance_request', 'petty_cash', 'other'
  )
);
```

---

## 2. MAJOR: Missing Security Features

### 2.1. Cloudflare Turnstile (Bot Protection) Ignored
**Severity:** 🟠 **High**

-   **Issue:** The implementation plan explicitly required server-side Turnstile verification to prevent abuse of the OTP endpoint. The backend function `functions/api/verify-turnstile.ts` exists, but the frontend (`app/login/page.tsx`) **completely ignores it**.
-   **Vulnerability:** Attackers can script thousands of requests to the login endpoint, triggering email floods (spamming employees) or enumerating valid email addresses, bypassing rate limits.
-   **Recommendation:** Update `app/login/page.tsx` to:
    1.  Render the Turnstile widget.
    2.  Get the token.
    3.  Call `/api/verify-turnstile` *before* calling `sendOtp`.

### 2.2. Missing MFA/TOTP Implementation
**Severity:** 🟠 **High**

-   **Issue:** Accounts Admins and Directors are required to have MFA. However:
    1.  There is **no UI** for a user to scan a QR code and setup TOTP.
    2.  There is **no UI** in `app/login/page.tsx` to accept a TOTP code during login.
    3.  `AuthContext.tsx` checks if MFA is "enabled" (`user.factors`), but this does not enforce that the *current session* has been verified (AAL2).
-   **Vulnerability:** If an admin's password is compromised, the attacker has full access. The "MFA Required" requirement is effectively not implemented on the frontend.
-   **Recommendation:**
    1.  Add an "MFA Setup" page in the user settings.
    2.  Update the Login flow to detect if the user has MFA enabled, and if so, prompt for the 6-digit code using `supabase.auth.signInWithOtp({ ... })` or `verifyOtp` with the code.
    3.  Ideally, enforce AAL2 (Authenticator Assurance Level 2) in RLS policies or strictly in `AuthContext`.

---

## 3. Implementation Deviations

### 3.1. Destructive User Deactivation
**Severity:** 🟡 **Medium**

-   **Issue:** The `deactivate-user.ts` function **deletes** the row from `user_roles` instead of setting `is_active = false`.
-   **Impact:** While the audit log (`request_events`) preserves the `actor_id`, removing the `user_roles` entry destroys the historical record of what role that user held. It breaks the "soft delete" philosophy outlined in the plan.
-   **Recommendation:** Change the logic to update the row:
    ```typescript
    await supabase.from('user_roles').update({ is_active: false }).eq('user_id', userId);
    ```

### 3.2. Unused/Incomplete "Deadline" Migration
**Severity:** ⚪ **Low**

-   **Issue:** `005_add_deadline.sql` was intended to add a deadline column and update categories. It added the column but punted on the categories.
-   **Impact:** Combined with Issue #1, this confirms the category migration was missed.

---

## 4. Code Quality & Logic Review

-   **AuthContext MFA Check:**
    -   `mfa_enabled: Boolean(supabaseUser.factors?.find(f => f.status === 'verified'))`
    -   *Note:* The `factors` array is not always populated on the initial session object returned by `getSession()`. This check might be flaky.
    -   *Fix:* Use `supabase.auth.mfa.getAuthenticatorAssuranceLevel()` for a reliable check.

-   **Hardcoded Values:**
    -   `functions/api/admin/deactivate-user.ts` uses a hardcoded ban duration of `87600h` (10 years). This is acceptable but worth noting.

-   **Missing Error Boundaries:**
    -   The app lacks a global Error Boundary (in `app/global-error.tsx` or similar) to catch React rendering errors gracefully.

---

## 5. Conclusion & Next Steps

The application has a solid "security backbone" in the database (RLS, Triggers, Immutable Logs), which is the hardest part to get right. However, the application layer is currently **broken** (Database Constraint) and **insecure** (Missing Turnstile & MFA).

**Immediate Actions Required (in order):**
1.  **Fix Database Constraint:** Run the SQL migration to match TypeScript categories.
2.  **Implement Turnstile:** Wire up the frontend login form to the existing backend function.
3.  **Implement MFA:** Build the UI for TOTP setup and challenge.
4.  **Fix Deactivation:** Switch from `DELETE` to `UPDATE is_active=false`.

Once these four items are addressed, the application will meet the "Industry Grade" standard requested.
