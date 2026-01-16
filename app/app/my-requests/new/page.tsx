// ============================================================================
// New Request Page
// Form for creating a new request
// ============================================================================

'use client';

import React from 'react';
import { RequestForm } from '@/components/requests';

export default function NewRequestPage() {
    return (
        <div className="max-w-3xl mx-auto px-4 sm:px-0">
            {/* Header */}
            <div className="mb-6 sm:mb-8">
                <h1 className="text-xl sm:text-2xl font-bold text-gray-900">Create New Request</h1>
                <p className="text-gray-500 mt-1 text-sm sm:text-base">
                    Submit a new request to the Accounts team
                </p>
            </div>

            {/* Form */}
            <RequestForm />
        </div>
    );
}

