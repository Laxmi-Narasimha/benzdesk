// ============================================================================
// Home Page
// Redirects based on auth state and role
// ============================================================================

'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/AuthContext';
import { PageLoader } from '@/components/ui';

export default function HomePage() {
    const router = useRouter();
    const { user, loading, isRequester, isAdmin, isDirector } = useAuth();

    useEffect(() => {
        if (loading) return;

        if (!user) {
            router.replace('/login');
            return;
        }

        // Redirect based on role
        if (isDirector) {
            router.replace('/director/dashboard');
        } else if (isAdmin) {
            router.replace('/admin/queue');
        } else {
            router.replace('/app/my-requests');
        }
    }, [user, loading, isRequester, isAdmin, isDirector, router]);

    return <PageLoader message="Redirecting..." />;
}
