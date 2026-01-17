'use client';

import React from 'react';
import { Card } from '@/components/ui';
import {
    LayoutDashboard,
    ClipboardList,
    Trash2,
    CheckCircle2,
    Clock,
    Filter,
    Shield
} from 'lucide-react';

export default function AdminHelpPage() {
    return (
        <div className="max-w-4xl mx-auto space-y-8">
            <div className="flex flex-col gap-2">
                <h1 className="text-2xl font-bold text-gray-900">Admin Guide</h1>
                <p className="text-gray-500">
                    Guide for Accounts Admins & Directors: Managing the request lifecycle efficiently.
                </p>
            </div>

            {/* 1. Queue Management */}
            <section className="space-y-4">
                <div className="flex items-center gap-3">
                    <div className="p-2 bg-blue-100 rounded-lg">
                        <ClipboardList className="w-6 h-6 text-blue-600" />
                    </div>
                    <h2 className="text-xl font-semibold text-gray-900">Managing the Request Queue</h2>
                </div>

                <Card className="p-6 space-y-4">
                    <p className="text-gray-600">
                        The <strong>Request Queue</strong> is your main workspace. Here's how to use it effectively:
                    </p>
                    <ul className="list-disc list-inside space-y-3 text-gray-700 ml-2">
                        <li>
                            <strong>Filters (<Filter className="w-4 h-4 inline" />):</strong> Use the dropdowns to filter by Status (e.g., "Open"), Category (e.g., "Expense"), or Priority.
                        </li>
                        <li>
                            <strong>Fresh Start View:</strong> By default, the system shows requests from Jan 14, 2026 onwards. Old requests are hidden but safe in the database.
                        </li>
                        <li>
                            <strong>Sorting:</strong> Click "Sort by" to organize by Priority (handle Critical first!) or Created Date.
                        </li>
                        <li>
                            <strong>Assigning:</strong> Open a request and click "Take Ownership" or assign it to a colleague if you have Director access.
                        </li>
                    </ul>
                </Card>
            </section>

            {/* 2. Changing Statuses */}
            <section className="space-y-4">
                <div className="flex items-center gap-3">
                    <div className="p-2 bg-green-100 rounded-lg">
                        <CheckCircle2 className="w-6 h-6 text-green-600" />
                    </div>
                    <h2 className="text-xl font-semibold text-gray-900">Workflow & Statuses</h2>
                </div>

                <Card className="p-6 space-y-2">
                    <p className="text-gray-600 mb-4">
                        Proper status updates keep the user informed and stop them from messaging you manually.
                    </p>

                    <div className="grid gap-4 sm:grid-cols-2">
                        <div className="p-3 bg-gray-50 rounded-lg border border-gray-100">
                            <span className="font-semibold text-blue-700">Open → In Progress</span>
                            <p className="text-sm text-gray-600 mt-1">
                                Mark this immediately when you start working so others don't pick it up.
                            </p>
                        </div>

                        <div className="p-3 bg-gray-50 rounded-lg border border-gray-100">
                            <span className="font-semibold text-purple-700">→ Waiting on Requester</span>
                            <p className="text-sm text-gray-600 mt-1">
                                Use this if you need a missing bill or clarification. The user gets notified to reply.
                            </p>
                        </div>

                        <div className="p-3 bg-gray-50 rounded-lg border border-gray-100">
                            <span className="font-semibold text-green-700">→ Pending Closure</span>
                            <p className="text-sm text-gray-600 mt-1">
                                Mark this when you are done. The user will confirm and close it.
                                <br /><em className="text-xs">If they don't respond, it auto-closes after 48 hours (Director only feature).</em>
                            </p>
                        </div>

                        <div className="p-3 bg-gray-50 rounded-lg border border-gray-100">
                            <span className="font-semibold text-gray-700">→ Closed</span>
                            <p className="text-sm text-gray-600 mt-1">
                                Final state. Can be re-opened if necessary, but try to avoid it.
                            </p>
                        </div>
                    </div>
                </Card>
            </section>

            {/* 3. Handling Issues */}
            <section className="space-y-4">
                <div className="flex items-center gap-3">
                    <div className="p-2 bg-red-100 rounded-lg">
                        <Shield className="w-6 h-6 text-red-600" />
                    </div>
                    <h2 className="text-xl font-semibold text-gray-900">Deletion & Control</h2>
                </div>

                <Card className="p-6 space-y-4">
                    <div className="flex items-start gap-4">
                        <Trash2 className="w-5 h-5 text-red-500 mt-1 shrink-0" />
                        <div>
                            <h3 className="font-semibold text-gray-900">Deleting Requests</h3>
                            <p className="text-gray-600 text-sm mt-1">
                                Admins and Directors can delete requests that are <strong>Closed</strong>.
                                This is useful for removing test data or duplicate kinds of errors.
                                <br />
                                <span className="text-red-600 font-medium">Warning:</span>Deletion is permanent.
                            </p>
                        </div>
                    </div>
                </Card>
            </section>

            {/* 4. SLA Targets (Director Only) */}
            <section className="space-y-4">
                <div className="flex items-center gap-3">
                    <div className="p-2 bg-amber-100 rounded-lg">
                        <Clock className="w-6 h-6 text-amber-600" />
                    </div>
                    <h2 className="text-xl font-semibold text-gray-900">SLA Targets</h2>
                </div>
                <Card className="p-6">
                    <p className="text-gray-600 mb-4">
                        We aim to resolve high priority requests within:
                    </p>
                    <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 text-center">
                        <div className="p-3 bg-red-50 rounded-lg">
                            <div className="text-lg font-bold text-red-600">24h</div>
                            <div className="text-xs text-red-500 font-medium">Critical (P1)</div>
                        </div>
                        <div className="p-3 bg-orange-50 rounded-lg">
                            <div className="text-lg font-bold text-orange-600">48h</div>
                            <div className="text-xs text-orange-500 font-medium">High (P2)</div>
                        </div>
                        <div className="p-3 bg-gray-50 rounded-lg">
                            <div className="text-lg font-bold text-gray-600">72h</div>
                            <div className="text-xs text-gray-500 font-medium">Normal (P3)</div>
                        </div>
                        <div className="p-3 bg-green-50 rounded-lg">
                            <div className="text-lg font-bold text-green-600">5 Days</div>
                            <div className="text-xs text-green-500 font-medium">Low (P4)</div>
                        </div>
                    </div>
                </Card>
            </section>
        </div>
    );
}
