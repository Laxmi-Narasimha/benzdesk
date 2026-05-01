// ============================================================================
// Sales Manager Layout
// Protected layout for sales managers
// ============================================================================

'use client';

import React, { useEffect } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { useAuth } from '@/lib/AuthContext';
import { Header } from '@/components/layout/Header';
import { PageLoader, Card } from '@/components/ui';
import { NotificationPrompt, IOSInstallPrompt, PWAInstallPrompt } from '@/components/NotificationPrompt';
import Link from 'next/link';
import { clsx } from 'clsx';
import { LayoutDashboard, ClipboardList, Users } from 'lucide-react';

const navItems = [
    { href: '/sales-manager/dashboard', label: 'Dashboard', icon: LayoutDashboard },
    { href: '/sales-manager/queue', label: 'Pending Approvals', icon: ClipboardList },
    { href: '/sales-manager/team', label: 'My Team', icon: Users },
];

function SalesManagerSidebar() {
    const pathname = usePathname();
    return (
        <div className="hidden lg:flex lg:flex-col lg:fixed lg:inset-y-0 lg:w-64 bg-dark-900 border-r border-dark-800 z-40">
            <div className="flex items-center gap-3 px-6 py-5 border-b border-dark-800">
                <div className="w-8 h-8 rounded-lg bg-primary-500 flex items-center justify-center text-white font-bold text-sm">
                    SM
                </div>
                <div>
                    <p className="font-semibold text-dark-50 text-sm">Sales Manager</p>
                    <p className="text-xs text-dark-500">BenzDesk</p>
                </div>
            </div>
            <nav className="flex-1 px-3 py-4 space-y-1">
                {navItems.map((item) => {
                    const Icon = item.icon;
                    const active = pathname === item.href || pathname.startsWith(item.href + '/');
                    return (
                        <Link
                            key={item.href}
                            href={item.href}
                            className={clsx(
                                'flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors',
                                active
                                    ? 'bg-primary-500/10 text-primary-400'
                                    : 'text-dark-400 hover:text-dark-50 hover:bg-dark-800'
                            )}
                        >
                            <Icon className="w-4 h-4 flex-shrink-0" />
                            {item.label}
                        </Link>
                    );
                })}
            </nav>
        </div>
    );
}

export default function SalesManagerLayout({
    children,
}: {
    children: React.ReactNode;
}) {
    const router = useRouter();
    const { user, loading, isSalesManager } = useAuth();

    useEffect(() => {
        if (!loading) {
            if (!user) {
                router.replace('/login');
            } else if (!isSalesManager) {
                router.replace('/');
            }
        }
    }, [user, loading, isSalesManager, router]);

    if (loading) {
        return <PageLoader message="Loading..." />;
    }

    if (!user || !isSalesManager) {
        return (
            <div className="min-h-screen flex items-center justify-center">
                <Card className="text-center p-8">
                    <h2 className="text-xl font-semibold text-dark-100">Access Denied</h2>
                    <p className="text-dark-400 mt-2">You don&apos;t have permission to access this area.</p>
                </Card>
            </div>
        );
    }

    return (
        <div className="min-h-screen bg-dark-950">
            <SalesManagerSidebar />
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
