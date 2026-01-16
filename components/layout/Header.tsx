// ============================================================================
// Header Component (Light Mode)
// Top navigation bar with breadcrumbs - hidden on mobile (shown in Sidebar)
// ============================================================================

'use client';

import React from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { ChevronRight, Search } from 'lucide-react';

// ============================================================================
// Types
// ============================================================================

interface HeaderProps {
    title?: string;
    subtitle?: string;
    actions?: React.ReactNode;
}

// ============================================================================
// Breadcrumb Generator
// ============================================================================

function generateBreadcrumbs(pathname: string): { label: string; href: string }[] {
    const segments = pathname.split('/').filter(Boolean);
    const breadcrumbs: { label: string; href: string }[] = [];

    let currentPath = '';

    for (const segment of segments) {
        currentPath += `/${segment}`;

        // Format segment as label
        let label = segment
            .split('-')
            .map(word => word.charAt(0).toUpperCase() + word.slice(1))
            .join(' ');

        // Special cases
        if (segment === 'app') label = 'Home';
        if (segment === 'my-requests') label = 'My Requests';
        if (segment === 'admin') label = 'Admin';
        if (segment === 'director') label = 'Director';
        if (segment === 'queue') label = 'Request Queue';
        if (segment === 'new') label = 'New Request';

        // Skip UUID segments in display
        if (segment.match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)) {
            label = 'Details';
        }

        breadcrumbs.push({ label, href: currentPath });
    }

    return breadcrumbs;
}

// ============================================================================
// Header Component
// ============================================================================

export function Header({ title, subtitle, actions }: HeaderProps) {
    const pathname = usePathname();
    const breadcrumbs = generateBreadcrumbs(pathname);

    return (
        <header className="sticky top-0 z-20 bg-white/80 backdrop-blur-xl border-b border-gray-200 hidden lg:block">
            <div className="flex items-center justify-between h-14 px-6">
                {/* Left section - Breadcrumbs */}
                <nav className="flex items-center gap-2 text-sm">
                    {breadcrumbs.map((crumb, index) => (
                        <React.Fragment key={crumb.href}>
                            {index > 0 && (
                                <ChevronRight className="w-4 h-4 text-gray-400" />
                            )}
                            {index === breadcrumbs.length - 1 ? (
                                <span className="font-medium text-gray-900">{crumb.label}</span>
                            ) : (
                                <Link
                                    href={crumb.href}
                                    className="text-gray-500 hover:text-gray-700 transition-colors"
                                >
                                    {crumb.label}
                                </Link>
                            )}
                        </React.Fragment>
                    ))}
                </nav>

                {/* Right section */}
                <div className="flex items-center gap-3">
                    {/* Search button */}
                    <button className="p-2 rounded-lg text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition-colors">
                        <Search className="w-5 h-5" />
                    </button>

                    {/* Custom actions */}
                    {actions}
                </div>
            </div>

            {/* Title section (optional) */}
            {(title || subtitle) && (
                <div className="px-6 pb-4">
                    {title && (
                        <h1 className="text-2xl font-bold text-gray-900">{title}</h1>
                    )}
                    {subtitle && (
                        <p className="text-sm text-gray-500 mt-1">{subtitle}</p>
                    )}
                </div>
            )}
        </header>
    );
}

export default Header;
