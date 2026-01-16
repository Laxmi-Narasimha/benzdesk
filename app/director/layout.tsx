// ============================================================================
// Director Layout
// Protected layout for director only
// ============================================================================

'use client';

import React, { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/AuthContext';
import { Sidebar } from '@/components/layout/Sidebar';
import { Header } from '@/components/layout/Header';
import { PageLoader, Card } from '@/components/ui';

export default function DirectorLayout({
    children,
}: {
    children: React.ReactNode;
}) {
    const router = useRouter();
    const { user, loading, isDirector } = useAuth();

    // Redirect if not director
    useEffect(() => {
        if (!loading) {
            if (!user) {
                router.replace('/login');
            } else if (!isDirector) {
                router.replace('/app/my-requests');
            }
        }
    }, [user, loading, isDirector, router]);

    if (loading) {
        return <PageLoader message="Loading..." />;
    }

    if (!user || !isDirector) {
        return (
            <div className="min-h-screen flex items-center justify-center">
                <Card className="text-center p-8">
                    <h2 className="text-xl font-semibold text-dark-100">Access Denied</h2>
                    <p className="text-dark-400 mt-2">Director access required.</p>
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
        </div>
    );
}
