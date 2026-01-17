// ============================================================================
// Sidebar Component
// Mobile-responsive navigation sidebar with hamburger menu for mobile
// ============================================================================

'use client';

import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { clsx } from 'clsx';
import {
    LayoutDashboard,
    FileText,
    Plus,
    Users,
    BarChart3,
    LogOut,
    ClipboardList,
    Clock,
    AlertTriangle,
    ChevronRight,
    Menu,
    X,
    BookOpen,
} from 'lucide-react';
import { useAuth } from '@/lib/AuthContext';
import { RoleBadge } from '@/components/ui';
import { NotificationBell } from './NotificationBell';

// ============================================================================
// Types
// ============================================================================

interface NavItem {
    href: string;
    label: string;
    icon: React.ReactNode;
    roles?: ('requester' | 'accounts_admin' | 'director')[];
    badge?: number;
}

// ============================================================================
// Navigation Items
// ============================================================================

const requesterNav: NavItem[] = [
    {
        href: '/app/my-requests',
        label: 'My Requests',
        icon: <FileText className="w-5 h-5" />,
        roles: ['requester'],
    },
    {
        href: '/app/my-requests/new',
        label: 'New Request',
        icon: <Plus className="w-5 h-5" />,
        roles: ['requester'],
    },
    {
        href: '/app/help',
        label: 'Help & Guide',
        icon: <BookOpen className="w-5 h-5" />,
        roles: ['requester'],
    },
];

const adminNav: NavItem[] = [
    {
        href: '/admin/queue',
        label: 'Request Queue',
        icon: <ClipboardList className="w-5 h-5" />,
        roles: ['accounts_admin', 'director'],
    },
    {
        href: '/admin/reports',
        label: 'Reports',
        icon: <BarChart3 className="w-5 h-5" />,
        roles: ['accounts_admin', 'director'],
    },
    {
        href: '/admin/help',
        label: 'Admin Guide',
        icon: <BookOpen className="w-5 h-5" />,
        roles: ['accounts_admin', 'director'],
    },
];

const directorNav: NavItem[] = [
    {
        href: '/director/dashboard',
        label: 'Dashboard',
        icon: <LayoutDashboard className="w-5 h-5" />,
        roles: ['director'],
    },
    {
        href: '/director/admin-performance',
        label: 'Admin Performance',
        icon: <Users className="w-5 h-5" />,
        roles: ['director'],
    },
    {
        href: '/director/sla',
        label: 'SLA Tracking',
        icon: <Clock className="w-5 h-5" />,
        roles: ['director'],
    },
    {
        href: '/director/stale',
        label: 'Stale Requests',
        icon: <AlertTriangle className="w-5 h-5" />,
        roles: ['director'],
    },
];

// ============================================================================
// Mobile Header Component
// ============================================================================

function MobileHeader({ onMenuClick }: { onMenuClick: () => void }) {
    return (
        <header className="fixed top-0 left-0 right-0 h-14 bg-white border-b border-gray-200 flex items-center justify-between px-4 z-30 lg:hidden">
            <Link href="/" className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-primary-500 to-primary-600 flex items-center justify-center">
                    <span className="text-white font-bold text-sm">B</span>
                </div>
                <span className="font-semibold text-gray-900">BenzDesk</span>
            </Link>

            <div className="flex items-center gap-2">
                <NotificationBell />
                <button
                    onClick={onMenuClick}
                    className="p-2 text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-lg transition-colors"
                    aria-label="Open menu"
                >
                    <Menu className="w-6 h-6" />
                </button>
            </div>
        </header>
    );
}

// ============================================================================
// Sidebar Component
// ============================================================================

export function Sidebar() {
    const { user, logout, isRequester, isAdmin, isDirector } = useAuth();
    const pathname = usePathname();
    const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);

    // Close mobile menu on route change
    useEffect(() => {
        setIsMobileMenuOpen(false);
    }, [pathname]);

    // Close mobile menu on resize to desktop
    useEffect(() => {
        const handleResize = () => {
            if (window.innerWidth >= 1024) {
                setIsMobileMenuOpen(false);
            }
        };
        window.addEventListener('resize', handleResize);
        return () => window.removeEventListener('resize', handleResize);
    }, []);

    // Prevent body scroll when mobile menu is open
    useEffect(() => {
        if (isMobileMenuOpen) {
            document.body.style.overflow = 'hidden';
        } else {
            document.body.style.overflow = '';
        }
        return () => {
            document.body.style.overflow = '';
        };
    }, [isMobileMenuOpen]);

    // Filter nav items by role
    const getNavItems = () => {
        const items: NavItem[] = [];

        if (isRequester) {
            items.push(...requesterNav);
        }

        if (isAdmin || isDirector) {
            items.push(...adminNav);
        }

        if (isDirector) {
            items.push(...directorNav);
        }

        return items;
    };

    const navItems = getNavItems();

    const sidebarContent = (
        <>
            {/* Logo - hidden on mobile (shown in MobileHeader) */}
            <div className="p-6 border-b border-gray-200 hidden lg:block">
                <Link href="/" className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-primary-500 to-primary-600 flex items-center justify-center shadow-sm">
                        <span className="text-white font-bold text-lg">B</span>
                    </div>
                    <div>
                        <h1 className="text-lg font-bold text-gray-900">BenzDesk</h1>
                        <p className="text-xs text-gray-500">Accounts Portal</p>
                    </div>
                </Link>
            </div>

            {/* Mobile close button */}
            <div className="flex items-center justify-between p-4 border-b border-gray-200 lg:hidden">
                <span className="font-semibold text-gray-900">Menu</span>
                <button
                    onClick={() => setIsMobileMenuOpen(false)}
                    className="p-2 text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-lg transition-colors"
                >
                    <X className="w-5 h-5" />
                </button>
            </div>

            {/* Navigation */}
            <nav className="flex-1 overflow-y-auto py-4 px-2">
                <div className="space-y-1">
                    {navItems.map((item) => {
                        const isActive = pathname === item.href || pathname.startsWith(item.href + '/');

                        return (
                            <Link
                                key={item.href}
                                href={item.href}
                                className={clsx(
                                    'flex items-center gap-3 px-4 py-3 rounded-lg mx-1',
                                    'transition-all duration-200 group',
                                    {
                                        'bg-primary-50 text-primary-600 border-l-2 border-primary-500 rounded-l-none':
                                            isActive,
                                        'text-gray-600 hover:bg-gray-100 hover:text-gray-900':
                                            !isActive,
                                    }
                                )}
                            >
                                <span
                                    className={clsx(
                                        'transition-colors',
                                        isActive ? 'text-primary-500' : 'text-gray-400 group-hover:text-gray-600'
                                    )}
                                >
                                    {item.icon}
                                </span>
                                <span className="flex-1 text-sm font-medium">{item.label}</span>
                                {item.badge !== undefined && item.badge > 0 && (
                                    <span className="px-2 py-0.5 text-xs font-semibold rounded-full bg-primary-100 text-primary-600">
                                        {item.badge}
                                    </span>
                                )}
                                {isActive && (
                                    <ChevronRight className="w-4 h-4 text-primary-500" />
                                )}
                            </Link>
                        );
                    })}
                </div>
            </nav>

            {/* User section */}
            <div className="p-4 border-t border-gray-200">
                {user && (
                    <div className="mb-4">
                        <div className="flex items-center gap-3 px-2">
                            <div className="w-9 h-9 rounded-full bg-gradient-to-br from-primary-500 to-primary-600 flex items-center justify-center">
                                <span className="text-white font-semibold text-sm">
                                    {user.email.charAt(0).toUpperCase()}
                                </span>
                            </div>
                            <div className="flex-1 min-w-0">
                                <p className="text-sm font-medium text-gray-900 truncate">
                                    {user.email}
                                </p>
                                <RoleBadge role={user.role} size="sm" />
                            </div>
                            {/* Notification bell only on desktop sidebar */}
                            <div className="hidden lg:block">
                                <NotificationBell />
                            </div>
                        </div>
                    </div>
                )}

                <button
                    onClick={() => logout()}
                    className="w-full flex items-center gap-3 px-4 py-2.5 rounded-lg text-gray-500 hover:bg-red-50 hover:text-red-600 transition-colors"
                >
                    <LogOut className="w-5 h-5" />
                    <span className="text-sm font-medium">Sign Out</span>
                </button>

                <div className="mt-4 px-4 text-xs text-gray-400 flex items-center justify-between">
                    <span>v1.0.12</span>
                    <span className="text-green-500 font-medium">● Online</span>
                </div>
            </div>
        </>
    );

    return (
        <>
            {/* Mobile Header */}
            <MobileHeader onMenuClick={() => setIsMobileMenuOpen(true)} />

            {/* Mobile overlay */}
            {isMobileMenuOpen && (
                <div
                    className="fixed inset-0 bg-black/50 z-40 lg:hidden animate-fade-in"
                    onClick={() => setIsMobileMenuOpen(false)}
                />
            )}

            {/* Sidebar - desktop fixed, mobile slide-in */}
            <aside
                className={clsx(
                    'fixed top-0 h-screen bg-white border-r border-gray-200 flex flex-col z-50',
                    // Desktop: always visible
                    'lg:left-0 lg:w-64',
                    // Mobile: slide in from left
                    'w-72 lg:translate-x-0 transition-transform duration-300 ease-out',
                    isMobileMenuOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'
                )}
            >
                {sidebarContent}
            </aside>

            {/* Spacer for mobile header */}
            <div className="h-14 lg:hidden" />
        </>
    );
}

export default Sidebar;
