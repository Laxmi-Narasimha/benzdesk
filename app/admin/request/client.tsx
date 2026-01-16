'use client';

import React from 'react';
import { useSearchParams } from 'next/navigation';
import { RequestDetail } from '@/components/requests';
import { ProtectedRoute } from '@/lib/AuthContext';
import { Button } from '@/components/ui';
import Link from 'next/link';

export default function AdminRequestDetailClient() {
    const searchParams = useSearchParams();
    const id = searchParams.get('id');

    if (!id) {
        return (
            <div className="max-w-6xl mx-auto p-4 text-center">
                <p className="text-red-400 mb-4">No request ID provided</p>
                <Link href="/admin">
                    <Button variant="secondary">Go Back</Button>
                </Link>
            </div>
        );
    }

    return (
        <ProtectedRoute requiredRoles={['accounts_admin', 'director']}>
            <div className="max-w-6xl mx-auto">
                <RequestDetail requestId={id} />
            </div>
        </ProtectedRoute>
    );
}
