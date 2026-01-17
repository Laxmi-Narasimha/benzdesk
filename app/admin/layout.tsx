// ============================================================================
// Admin Layout
// Protected layout for accounts admins
// ============================================================================

'use client';

import React, { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/AuthContext';
import { Sidebar } from '@/components/layout/Sidebar';
import { Header } from '@/components/layout/Header';
import { PageLoader, Card } from '@/components/ui';
import { NotificationPrompt, IOSInstallPrompt, PWAInstallPrompt } from '@/components/NotificationPrompt';

export default function AdminLayout({
    children,
}: {
    children: React.ReactNode;
}) {
    const router = useRouter();
    const { user, loading, isAdmin, isDirector, canManageRequests } = useAuth();

    // Redirect if not admin
    useEffect(() => {
        if (!loading) {
            if (!user) {
                router.replace('/login');
            } else if (!canManageRequests) {
                router.replace('/app/my-requests');
            }
        }
    }, [user, loading, canManageRequests, router]);

    if (loading) {
        return <PageLoader message="Loading..." />;
    }

    if (!user || !canManageRequests) {
        return (
            <div className="min-h-screen flex items-center justify-center">
                <Card className="text-center p-8">
                    <h2 className="text-xl font-semibold text-dark-100">Access Denied</h2>
                    <p className="text-dark-400 mt-2">You don't have permission to access this area.</p>
                </Card>
            </div>
        );
    }

    return (
        <div className="min-h-screen bg-dark-950">
            <Sidebar />
            <div className="lg:pl-64">
                <Header />
                <main className="p-6">
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
