'use client';

import React from 'react';
import { useSearchParams } from 'next/navigation';
import { RequestDetail } from '@/components/requests';
import { Button, Spinner } from '@/components/ui';
import { ArrowLeft } from 'lucide-react';
import Link from 'next/link';

export default function RequestDetailClient() {
    const searchParams = useSearchParams();
    const id = searchParams.get('id');

    if (!id) {
        return (
            <div className="max-w-6xl mx-auto p-4">
                <div className="text-center py-12">
                    <p className="text-red-400 mb-4">No request ID provided</p>
                    <Link href="/app">
                        <Button variant="secondary">Go Back</Button>
                    </Link>
                </div>
            </div>
        );
    }

    return (
        <div className="max-w-6xl mx-auto">
            <RequestDetail requestId={id} />
        </div>
    );
}
