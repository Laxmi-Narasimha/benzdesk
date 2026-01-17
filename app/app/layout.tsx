// ============================================================================
// App Layout (Requester Routes)
// Protected layout with sidebar for authenticated requesters
// ============================================================================

'use client';

import React, { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/AuthContext';
import { Sidebar } from '@/components/layout/Sidebar';
import { Header } from '@/components/layout/Header';
import { PageLoader } from '@/components/ui';
import { NotificationPrompt, IOSInstallPrompt, PWAInstallPrompt } from '@/components/NotificationPrompt';

export default function AppLayout({
    children,
}: {
    children: React.ReactNode;
}) {
    const router = useRouter();
    const { user, loading } = useAuth();

    // Redirect to login if not authenticated
    useEffect(() => {
        if (!loading && !user) {
            router.replace('/login');
        }
    }, [user, loading, router]);

    if (loading) {
        return <PageLoader message="Loading..." />;
    }

    if (!user) {
        return null;
    }

    return (
        <div className="min-h-screen bg-gray-50">
            {/* Sidebar */}
            <Sidebar />

            {/* Main content */}
            <div className="lg:pl-64">
                <Header />
                <main className="p-4 sm:p-6 pt-4">
                    {children}
                </main>
            </div>

            {/* PWA Prompts */}
            <NotificationPrompt />
            <IOSInstallPrompt />
            <PWAInstallPrompt />
        </div>
    );
}

