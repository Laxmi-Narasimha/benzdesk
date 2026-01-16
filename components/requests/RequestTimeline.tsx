// ============================================================================
// Request Timeline Component
// Displays audit events as a visual timeline
// ============================================================================

'use client';

import React from 'react';
import { clsx } from 'clsx';
import { format, formatDistanceToNow } from 'date-fns';
import {
    PlusCircle,
    MessageSquare,
    ArrowRight,
    UserPlus,
    CheckCircle,
    RefreshCw,
    Paperclip,
    Trash2,
} from 'lucide-react';
import { Card } from '@/components/ui';
import type { RequestEvent, RequestEventType } from '@/types';
import { REQUEST_STATUS_LABELS } from '@/types';

// ============================================================================
// Types
// ============================================================================

interface RequestTimelineProps {
    events: RequestEvent[];
}

// ============================================================================
// Event Config
// ============================================================================

interface EventConfig {
    icon: React.ReactNode;
    color: string;
    bgColor: string;
    getTitle: (event: RequestEvent) => string;
    getDescription?: (event: RequestEvent) => string | null;
}

const eventConfigs: Record<RequestEventType, EventConfig> = {
    created: {
        icon: <PlusCircle className="w-4 h-4" />,
        color: 'text-green-400',
        bgColor: 'bg-green-500/20',
        getTitle: () => 'Request created',
        getDescription: (e) => {
            const data = e.new_data as any;
            return data?.title ? `"${data.title}"` : null;
        },
    },
    comment: {
        icon: <MessageSquare className="w-4 h-4" />,
        color: 'text-blue-400',
        bgColor: 'bg-blue-500/20',
        getTitle: (e) => {
            const data = e.new_data as any;
            return data?.is_internal ? 'Internal note added' : 'Comment added';
        },
        getDescription: (e) => {
            const data = e.new_data as any;
            return data?.body_preview || null;
        },
    },
    status_changed: {
        icon: <ArrowRight className="w-4 h-4" />,
        color: 'text-amber-400',
        bgColor: 'bg-amber-500/20',
        getTitle: (e) => {
            const oldStatus = (e.old_data as any)?.status;
            const newStatus = (e.new_data as any)?.status;
            const oldLabel = oldStatus ? REQUEST_STATUS_LABELS[oldStatus as keyof typeof REQUEST_STATUS_LABELS] : 'Unknown';
            const newLabel = newStatus ? REQUEST_STATUS_LABELS[newStatus as keyof typeof REQUEST_STATUS_LABELS] : 'Unknown';
            return `Status changed from ${oldLabel} to ${newLabel}`;
        },
    },
    assigned: {
        icon: <UserPlus className="w-4 h-4" />,
        color: 'text-purple-400',
        bgColor: 'bg-purple-500/20',
        getTitle: (e) => {
            const newAssignee = (e.new_data as any)?.assigned_to;
            const oldAssignee = (e.old_data as any)?.assigned_to;
            if (!oldAssignee && newAssignee) {
                return 'Request assigned';
            } else if (oldAssignee && !newAssignee) {
                return 'Assignment removed';
            } else {
                return 'Request reassigned';
            }
        },
    },
    closed: {
        icon: <CheckCircle className="w-4 h-4" />,
        color: 'text-green-400',
        bgColor: 'bg-green-500/20',
        getTitle: () => 'Request closed',
    },
    reopened: {
        icon: <RefreshCw className="w-4 h-4" />,
        color: 'text-amber-400',
        bgColor: 'bg-amber-500/20',
        getTitle: () => 'Request reopened',
    },
    attachment_added: {
        icon: <Paperclip className="w-4 h-4" />,
        color: 'text-cyan-400',
        bgColor: 'bg-cyan-500/20',
        getTitle: () => 'Attachment added',
        getDescription: (e) => {
            const data = e.new_data as any;
            return data?.filename || null;
        },
    },
    attachment_removed: {
        icon: <Trash2 className="w-4 h-4" />,
        color: 'text-red-400',
        bgColor: 'bg-red-500/20',
        getTitle: () => 'Attachment removed',
        getDescription: (e) => {
            const data = e.old_data as any;
            return data?.filename || null;
        },
    },
};

// ============================================================================
// Component
// ============================================================================

export function RequestTimeline({ events }: RequestTimelineProps) {
    if (events.length === 0) {
        return (
            <Card className="text-center py-8">
                <p className="text-dark-400">No events recorded yet</p>
            </Card>
        );
    }

    return (
        <Card padding="lg">
            <div className="relative pl-8 space-y-6">
                {/* Vertical line */}
                <div className="absolute left-3 top-2 bottom-2 w-px bg-gradient-to-b from-primary-500/50 via-dark-700 to-dark-700" />

                {events.map((event, index) => {
                    const config = eventConfigs[event.event_type as RequestEventType] || {
                        icon: <PlusCircle className="w-4 h-4" />,
                        color: 'text-gray-400',
                        bgColor: 'bg-gray-500/20',
                        getTitle: () => event.event_type,
                    };

                    return (
                        <div key={event.id} className="relative animate-fade-in">
                            {/* Timeline dot */}
                            <div
                                className={clsx(
                                    'absolute -left-5 top-1 w-6 h-6 rounded-full flex items-center justify-center',
                                    'ring-4 ring-dark-900',
                                    config.bgColor
                                )}
                            >
                                <span className={config.color}>{config.icon}</span>
                            </div>

                            {/* Content */}
                            <div className="min-w-0">
                                <div className="flex items-center gap-2 flex-wrap">
                                    <span className="text-sm font-medium text-dark-100">
                                        {config.getTitle(event)}
                                    </span>
                                    <span className="text-xs text-dark-500">
                                        {formatDistanceToNow(new Date(event.created_at), { addSuffix: true })}
                                    </span>
                                </div>

                                {config.getDescription && (
                                    <p className="text-sm text-dark-400 mt-1 truncate">
                                        {config.getDescription(event)}
                                    </p>
                                )}

                                {event.note && (
                                    <p className="text-sm text-dark-500 mt-1 italic">
                                        Note: {event.note}
                                    </p>
                                )}

                                <p className="text-xs text-dark-600 mt-1">
                                    {format(new Date(event.created_at), 'MMM d, yyyy h:mm a')}
                                </p>
                            </div>
                        </div>
                    );
                })}
            </div>
        </Card>
    );
}

export default RequestTimeline;
