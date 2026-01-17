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
    Shield,
    Settings
} from 'lucide-react';
import { NotificationSettings, PWAInstallSettings } from '@/components/settings/NotificationSettings';

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

            {/* 2. Changing Statuses - SIMPLIFIED */}
            <section className="space-y-4">
                <div className="flex items-center gap-3">
                    <div className="p-2 bg-green-100 rounded-lg">
                        <CheckCircle2 className="w-6 h-6 text-green-600" />
                    </div>
                    <h2 className="text-xl font-semibold text-gray-900">How to Update Status</h2>
                </div>

                <Card className="p-6 space-y-4">
                    <p className="text-lg text-gray-800 font-medium">
                        Your goal is to move the request from Start to Finish. Here is the rule:
                    </p>

                    <div className="grid gap-4">
                        <div className="p-4 bg-blue-50 rounded-xl border border-blue-200">
                            <h3 className="text-lg font-bold text-blue-800 flex items-center gap-2">
                                1. Start Work
                            </h3>
                            <p className="text-gray-700 mt-1">
                                As soon as you see a new request, change status to <strong>In Progress</strong>.
                                <br />
                                <span className="text-sm text-gray-500">This tells everyone: "I am working on it!"</span>
                            </p>
                        </div>

                        <div className="p-4 bg-purple-50 rounded-xl border border-purple-200">
                            <h3 className="text-lg font-bold text-purple-800 flex items-center gap-2">
                                2. Need Info?
                            </h3>
                            <p className="text-gray-700 mt-1">
                                If the employee forgot a bill or needs to explain something, change status to <strong>Waiting on Requester</strong>.
                                <br />
                                <span className="text-sm text-gray-500">The system will notify them to reply to you.</span>
                            </p>
                        </div>

                        <div className="p-4 bg-green-50 rounded-xl border border-green-200 ring-2 ring-green-100">
                            <h3 className="text-lg font-bold text-green-800 flex items-center gap-2">
                                3. Job Done? (Important!)
                            </h3>
                            <p className="text-gray-900 mt-2 font-medium">
                                When you have finished the work (payment made, booking done, etc.), you MUST change status to:
                            </p>
                            <div className="my-3 text-center">
                                <span className="px-4 py-2 bg-green-600 text-white rounded-lg font-bold shadow-sm">
                                    Pending Closure
                                </span>
                            </div>
                            <p className="text-red-600 font-bold bg-white p-3 rounded-lg border border-red-100">
                                ✋ STOP! You cannot click "Closed". Only the Employee can close it.
                            </p>
                            <p className="text-gray-700 mt-2 text-sm">
                                You set it to <strong>Pending Closure</strong>. This sends a message to the employee:
                                <em>"I have done my part, please check and close."</em>
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

            {/* 5. App Settings */}
            <section className="space-y-4">
                <div className="flex items-center gap-3">
                    <div className="p-2 bg-indigo-100 rounded-lg">
                        <Settings className="w-6 h-6 text-indigo-600" />
                    </div>
                    <h2 className="text-xl font-semibold text-gray-900">App Settings</h2>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <NotificationSettings />
                    <PWAInstallSettings />
                </div>
            </section>
        </div>
    );
}
