// ============================================================================
// My Requests Page
// List of requester's own requests
// ============================================================================

'use client';

import React from 'react';
import Link from 'next/link';
import { Plus } from 'lucide-react';
import { Button, Card } from '@/components/ui';
import { RequestList } from '@/components/requests';

export default function MyRequestsPage() {
    return (
        <div className="max-w-5xl mx-auto space-y-6">
            {/* Header */}
            <div className="flex items-center justify-between">
                <div>
                    <h1 className="text-2xl font-bold text-dark-50">My Requests</h1>
                    <p className="text-dark-400 mt-1">
                        View and track your submitted requests
                    </p>
                </div>
                <Link href="/app/my-requests/new">
                    <Button leftIcon={<Plus className="w-4 h-4" />}>
                        New Request
                    </Button>
                </Link>
            </div>

            {/* Request list */}
            <RequestList
                showFilters={true}
                showAssignee={false}
                linkPrefix="/app/request"
            />
        </div>
    );
}
