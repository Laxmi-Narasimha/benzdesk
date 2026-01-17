'use client';

import React from 'react';
import { Card } from '@/components/ui';
import {
    FileText,
    Plus,
    MessageSquare,
    CheckCircle2,
    Clock,
    AlertCircle
} from 'lucide-react';

export default function UserHelpPage() {
    return (
        <div className="max-w-4xl mx-auto space-y-8">
            <div className="flex flex-col gap-2">
                <h1 className="text-2xl font-bold text-gray-900">User Guide</h1>
                <p className="text-gray-500">
                    Welcome to BenzDesk! Here is everything you need to know to get started.
                </p>
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

                <Card className="p-6 grid gap-6 sm:grid-cols-2">
                    <div className="space-y-2">
                        <div className="flex items-center gap-2">
                            <span className="w-3 h-3 rounded-full bg-blue-500"></span>
                            <span className="font-semibold text-gray-900">Open</span>
                        </div>
                        <p className="text-sm text-gray-600">
                            Your request has been sent but not yet viewed by an admin.
                        </p>
                    </div>

                    <div className="space-y-2">
                        <div className="flex items-center gap-2">
                            <span className="w-3 h-3 rounded-full bg-amber-500"></span>
                            <span className="font-semibold text-gray-900">In Progress</span>
                        </div>
                        <p className="text-sm text-gray-600">
                            The team is actively working on your request.
                        </p>
                    </div>

                    <div className="space-y-2">
                        <div className="flex items-center gap-2">
                            <span className="w-3 h-3 rounded-full bg-purple-500"></span>
                            <span className="font-semibold text-gray-900">Waiting on Requester</span>
                        </div>
                        <p className="text-sm text-gray-600">
                            <strong>Action Required!</strong> The admin asked you a question. Please check the comments and reply.
                        </p>
                    </div>

                    <div className="space-y-2">
                        <div className="flex items-center gap-2">
                            <span className="w-3 h-3 rounded-full bg-green-500"></span>
                            <span className="font-semibold text-gray-900">Pending Closure</span>
                        </div>
                        <p className="text-sm text-gray-600">
                            Work is done! Please confirm if you are satisfied so the ticket can be closed.
                        </p>
                    </div>

                    <div className="space-y-2 sm:col-span-2 border-t pt-4 mt-2">
                        <div className="flex items-center gap-2">
                            <span className="w-3 h-3 rounded-full bg-gray-500"></span>
                            <span className="font-semibold text-gray-900">Closed</span>
                        </div>
                        <p className="text-sm text-gray-600">
                            The request is complete and archived. No further actions can be taken.
                        </p>
                    </div>
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
        </div>
    );
}
