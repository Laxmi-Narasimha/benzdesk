'use client';

import React from 'react';
import { Card } from '@/components/ui';
import {
    FileText,
    Plus,
    MessageSquare,
    CheckCircle2,
    Clock,
    AlertCircle,
    Settings,
} from 'lucide-react';
import { NotificationSettings, PWAInstallSettings } from '@/components/settings/NotificationSettings';

export default function UserHelpPage() {
    return (
        <div className="max-w-4xl mx-auto space-y-8">
            <div className="flex flex-col gap-2">
                <h1 className="text-2xl font-bold text-gray-900">User Guide</h1>
                <p className="text-gray-500">
                    Welcome to BenzDesk! Here is everything you need to know to get started.
                </p>

                {/* Video Tutorial */}
                <a
                    href="https://www.loom.com/share/4521ef65ea314c53ad09c7bf7e02718b"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="mt-4 group relative block overflow-hidden rounded-xl border border-blue-100 bg-blue-50 hover:bg-blue-100 transition-all cursor-pointer"
                >
                    <div className="p-6 flex items-center gap-4">
                        <div className="flex-shrink-0 w-12 h-12 bg-blue-600 rounded-full flex items-center justify-center shadow-md group-hover:scale-110 transition-transform">
                            <svg className="w-6 h-6 text-white ml-1" fill="currentColor" viewBox="0 0 24 24">
                                <path d="M8 5v14l11-7z" />
                            </svg>
                        </div>
                        <div>
                            <h3 className="text-lg font-bold text-blue-900">Watch Video Tutorial</h3>
                            <p className="text-blue-700">Click here to watch a quick demo video on how to use the platform.</p>
                        </div>
                    </div>
                </a>
            </div>

            {/* 1. Creating a Request */}
            <section className="space-y-4">
                <div className="flex items-center gap-3">
                    <div className="p-2 bg-primary-100 rounded-lg">
                        <Plus className="w-6 h-6 text-primary-600" />
                    </div>
                    <h2 className="text-xl font-semibold text-gray-900">How to Submit a Request</h2>
                </div>

                <Card className="p-6 space-y-4">
                    <p className="text-gray-600 leading-relaxed">
                        Need approval for an expense, salary clarification, or a purchase order?
                        Submitting a request is easy:
                    </p>
                    <ol className="list-decimal list-inside space-y-3 text-gray-700 ml-2">
                        <li>
                            Click on <span className="font-semibold text-gray-900">New Request</span> in the sidebar menu.
                        </li>
                        <li>
                            <strong>Select the Category:</strong> Choose the option that best fits your need (e.g., "Expense Reimbursement", "Travel Allowance").
                        </li>
                        <li>
                            <strong>Give it a Title:</strong> Keep it short but clear (e.g., "Train tickets for Delhi Visit").
                        </li>
                        <li>
                            <strong>Describe Details:</strong> Explain <em>why</em> you need this and any important details.
                        </li>
                        <li>
                            <strong>Attach Files (Optional):</strong> You can upload bills, receipts, or screenshots.
                        </li>
                        <li>
                            <strong>Set Priority:</strong> Mark it as Urgent only if it truly cannot wait!
                        </li>
                    </ol>
                    <div className="bg-blue-50 p-4 rounded-lg border border-blue-100 text-sm text-blue-800 mt-4">
                        💡 <strong>Tip:</strong> providing clear details and attachments upfront helps the Accounts team process your request faster without asking for more info.
                    </div>
                </Card>
            </section>

            {/* 2. Tracking Status */}
            <section className="space-y-4">
                <div className="flex items-center gap-3">
                    <div className="p-2 bg-amber-100 rounded-lg">
                        <Clock className="w-6 h-6 text-amber-600" />
                    </div>
                    <h2 className="text-xl font-semibold text-gray-900">Understanding Statuses</h2>
                </div>

                <div className="space-y-4">
                    <div className="p-4 bg-green-50 rounded-xl border border-green-200">
                        <div className="flex items-center gap-2 mb-2">
                            <span className="w-3 h-3 rounded-full bg-green-500"></span>
                            <span className="font-bold text-green-900 text-lg">Pending Closure</span>
                        </div>
                        <p className="text-gray-800 font-medium">
                            This means the Admin has finished their work!
                        </p>
                        <div className="mt-3 bg-white p-3 rounded-lg border border-green-100 shadow-sm">
                            <p className="text-sm text-gray-600 mb-2">Your Job Now:</p>
                            <ol className="list-decimal list-inside text-sm text-gray-800 space-y-1">
                                <li>Check if your work is actually done.</li>
                                <li>If yes, <strong>YOU MUST CLICK THE CLOSE BUTTON</strong>.</li>
                            </ol>
                            <p className="text-xs text-red-500 mt-2 font-bold">
                                * Do not leave it open. The Admin cannot close it for you. You have to do it.
                            </p>
                        </div>
                    </div>

                    <div className="grid grid-cols-2 gap-4">
                        <div className="p-3 bg-blue-50 rounded-lg">
                            <span className="font-bold text-blue-900 block mb-1">Open</span>
                            <span className="text-xs text-blue-700">Sent to admin. Waiting for them to see it.</span>
                        </div>
                        <div className="p-3 bg-amber-50 rounded-lg">
                            <span className="font-bold text-amber-900 block mb-1">In Progress</span>
                            <span className="text-xs text-amber-700">Admin is working on it right now.</span>
                        </div>
                    </div>
                </div>

                <Card className="space-y-2 sm:col-span-2 border-t pt-4 mt-2">
                    <div className="flex items-center gap-2">
                        <span className="w-3 h-3 rounded-full bg-gray-500"></span>
                        <span className="font-semibold text-gray-900">Closed</span>
                    </div>
                    <p className="text-sm text-gray-600">
                        The request is complete and archived. No further actions can be taken.
                    </p>
                </Card>
            </section>

            {/* 3. Communication */}
            <section className="space-y-4">
                <div className="flex items-center gap-3">
                    <div className="p-2 bg-purple-100 rounded-lg">
                        <MessageSquare className="w-6 h-6 text-purple-600" />
                    </div>
                    <h2 className="text-xl font-semibold text-gray-900">Communication & Notifications</h2>
                </div>

                <Card className="p-6 space-y-4">
                    <p className="text-gray-600">
                        Stay updated without refreshing the page constantly.
                    </p>
                    <ul className="list-disc list-inside space-y-2 text-gray-700 ml-2">
                        <li>
                            <strong>Comments:</strong> Use the "Comments" tab inside a request to chat with the Accounts team. This keeps all conversation in one place.
                        </li>
                        <li>
                            <strong>Notifications:</strong> Check the 🔔 icon in the sidebar (or top right on mobile) for updates on your requests.
                        </li>
                        <li>
                            <strong>Mobile App:</strong> This website works great on your phone! Open it in your mobile browser to check status on the go.
                        </li>
                    </ul>
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
        </div >
    );
}
