// ============================================================================
// Next.js Middleware
// Server-side authentication protection
// Redirects unauthenticated users to login for protected routes
// ============================================================================

import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

// Routes that require authentication
const PROTECTED_PATHS = ['/app', '/admin', '/director'];

// Routes that are public (no auth required)
const PUBLIC_PATHS = ['/', '/login'];

export async function middleware(request: NextRequest) {
    const { pathname } = request.nextUrl;

    // Skip middleware for static files and API routes
    if (
        pathname.startsWith('/_next') ||
        pathname.startsWith('/api') ||
        pathname.includes('.') // static files like .js, .css, .png
    ) {
        return NextResponse.next();
    }

    // Check if this is a protected path
    const isProtectedPath = PROTECTED_PATHS.some(path => pathname.startsWith(path));
    const isPublicPath = PUBLIC_PATHS.includes(pathname);

    // If public path, allow access
    if (isPublicPath) {
        return NextResponse.next();
    }

    // For protected paths, check authentication
    if (isProtectedPath) {
        // Try to get the session from cookies
        const supabaseAuthToken = request.cookies.get('sb-igrudnilqwmlgvmgneng-auth-token');
        const supabaseAuthTokenCodeVerifier = request.cookies.get('sb-igrudnilqwmlgvmgneng-auth-token-code-verifier');

        // Check for various Supabase auth cookie patterns
        const hasAuthCookie =
            supabaseAuthToken ||
            supabaseAuthTokenCodeVerifier ||
            request.cookies.getAll().some(c => c.name.includes('supabase') && c.name.includes('auth'));

        if (!hasAuthCookie) {
            // No auth cookie found - redirect to login
            const loginUrl = new URL('/login', request.url);

            // Save the intended destination for redirect after login
            loginUrl.searchParams.set('redirect', pathname);

            return NextResponse.redirect(loginUrl);
        }

        // Auth cookie exists - allow access
        // The client-side auth will handle any expired sessions
        return NextResponse.next();
    }

    // For any other paths, allow access
    return NextResponse.next();
}

// Configure which routes the middleware runs on
export const config = {
    matcher: [
        /*
         * Match all request paths except:
         * - _next/static (static files)
         * - _next/image (image optimization files)
         * - favicon.ico (favicon file)
         * - public folder files
         */
        '/((?!_next/static|_next/image|favicon.ico|.*\\..*|api).*)',
    ],
};
