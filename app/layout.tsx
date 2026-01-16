// ============================================================================
// Root Layout
// Application shell with providers
// ============================================================================

import type { Metadata } from 'next';
import { AuthProvider } from '@/lib/AuthContext';
import { ToastProvider } from '@/components/ui';
import '@/styles/globals.css';

export const metadata: Metadata = {
    title: 'BenzDesk - Accounts Request Portal',
    description: 'Internal accounts request management platform for Benz',
    keywords: ['accounts', 'requests', 'internal portal', 'benzdesk'],
};

export default function RootLayout({
    children,
}: {
    children: React.ReactNode;
}) {
    return (
        <html lang="en" className="dark">
            <head>
                <link rel="icon" href="/favicon.ico" />
                <meta name="viewport" content="width=device-width, initial-scale=1" />
            </head>
            <body className="min-h-screen bg-dark-950 text-dark-50 antialiased">
                <AuthProvider>
                    <ToastProvider>
                        {children}
                    </ToastProvider>
                </AuthProvider>
            </body>
        </html>
    );
}
