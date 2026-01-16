// ============================================================================
// Badge Component
// Status and priority badges with color coding
// ============================================================================

import React from 'react';
import { clsx } from 'clsx';
import type { RequestStatus, Priority } from '@/types';

// ============================================================================
// Types
// ============================================================================

export interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
    variant?: 'default' | 'outline' | 'subtle';
    color?: 'gray' | 'blue' | 'green' | 'yellow' | 'orange' | 'red' | 'purple';
    size?: 'sm' | 'md';
    dot?: boolean;
}

// ============================================================================
// Badge Component
// ============================================================================

export const Badge = React.forwardRef<HTMLSpanElement, BadgeProps>(
    (
        {
            className,
            variant = 'default',
            color = 'gray',
            size = 'sm',
            dot = false,
            children,
            ...props
        },
        ref
    ) => {
        return (
            <span
                ref={ref}
                className={clsx(
                    'inline-flex items-center font-semibold rounded-full',
                    'transition-colors duration-200',

                    // Size
                    {
                        'px-2 py-0.5 text-xs gap-1': size === 'sm',
                        'px-3 py-1 text-sm gap-1.5': size === 'md',
                    },

                    // Variant + Color combinations
                    {
                        // Default (solid background)
                        'bg-gray-500/20 text-gray-400 border border-gray-500/30':
                            variant === 'default' && color === 'gray',
                        'bg-blue-500/20 text-blue-400 border border-blue-500/30':
                            variant === 'default' && color === 'blue',
                        'bg-green-500/20 text-green-400 border border-green-500/30':
                            variant === 'default' && color === 'green',
                        'bg-yellow-500/20 text-yellow-400 border border-yellow-500/30':
                            variant === 'default' && color === 'yellow',
                        'bg-orange-500/20 text-orange-400 border border-orange-500/30':
                            variant === 'default' && color === 'orange',
                        'bg-red-500/20 text-red-400 border border-red-500/30':
                            variant === 'default' && color === 'red',
                        'bg-purple-500/20 text-purple-400 border border-purple-500/30':
                            variant === 'default' && color === 'purple',

                        // Outline (transparent with border)
                        'bg-transparent text-gray-400 border border-gray-500/50':
                            variant === 'outline' && color === 'gray',
                        'bg-transparent text-blue-400 border border-blue-500/50':
                            variant === 'outline' && color === 'blue',
                        'bg-transparent text-green-400 border border-green-500/50':
                            variant === 'outline' && color === 'green',
                        'bg-transparent text-yellow-400 border border-yellow-500/50':
                            variant === 'outline' && color === 'yellow',
                        'bg-transparent text-orange-400 border border-orange-500/50':
                            variant === 'outline' && color === 'orange',
                        'bg-transparent text-red-400 border border-red-500/50':
                            variant === 'outline' && color === 'red',
                        'bg-transparent text-purple-400 border border-purple-500/50':
                            variant === 'outline' && color === 'purple',

                        // Subtle (very light background, no border)
                        'bg-gray-500/10 text-gray-400 border-0':
                            variant === 'subtle' && color === 'gray',
                        'bg-blue-500/10 text-blue-400 border-0':
                            variant === 'subtle' && color === 'blue',
                        'bg-green-500/10 text-green-400 border-0':
                            variant === 'subtle' && color === 'green',
                        'bg-yellow-500/10 text-yellow-400 border-0':
                            variant === 'subtle' && color === 'yellow',
                        'bg-orange-500/10 text-orange-400 border-0':
                            variant === 'subtle' && color === 'orange',
                        'bg-red-500/10 text-red-400 border-0':
                            variant === 'subtle' && color === 'red',
                        'bg-purple-500/10 text-purple-400 border-0':
                            variant === 'subtle' && color === 'purple',
                    },

                    className
                )}
                {...props}
            >
                {/* Status dot */}
                {dot && (
                    <span
                        className={clsx(
                            'w-1.5 h-1.5 rounded-full',
                            {
                                'bg-gray-400': color === 'gray',
                                'bg-blue-400': color === 'blue',
                                'bg-green-400': color === 'green',
                                'bg-yellow-400': color === 'yellow',
                                'bg-orange-400': color === 'orange',
                                'bg-red-400': color === 'red',
                                'bg-purple-400': color === 'purple',
                            }
                        )}
                    />
                )}
                {children}
            </span>
        );
    }
);

Badge.displayName = 'Badge';

// ============================================================================
// Status Badge - Pre-configured for request statuses
// ============================================================================

const statusConfig: Record<RequestStatus, { color: BadgeProps['color']; label: string }> = {
    open: { color: 'green', label: 'Open' },
    in_progress: { color: 'blue', label: 'In Progress' },
    waiting_on_requester: { color: 'yellow', label: 'Waiting' },
    pending_closure: { color: 'purple', label: 'Pending Closure' },
    closed: { color: 'gray', label: 'Closed' },
};

export interface StatusBadgeProps extends Omit<BadgeProps, 'color' | 'children'> {
    status: RequestStatus;
}

export function StatusBadge({ status, ...props }: StatusBadgeProps) {
    const config = statusConfig[status];

    return (
        <Badge color={config.color} dot {...props}>
            {config.label}
        </Badge>
    );
}

// ============================================================================
// Priority Badge - Pre-configured for priority levels
// ============================================================================

const priorityConfig: Record<Priority, { color: BadgeProps['color']; label: string }> = {
    1: { color: 'red', label: 'Critical' },
    2: { color: 'orange', label: 'High' },
    3: { color: 'yellow', label: 'Medium' },
    4: { color: 'green', label: 'Low' },
    5: { color: 'gray', label: 'Minimal' },
};

export interface PriorityBadgeProps extends Omit<BadgeProps, 'color' | 'children'> {
    priority: Priority;
}

export function PriorityBadge({ priority, ...props }: PriorityBadgeProps) {
    const config = priorityConfig[priority];

    return (
        <Badge color={config.color} {...props}>
            P{priority} - {config.label}
        </Badge>
    );
}

// ============================================================================
// Role Badge - Pre-configured for user roles
// ============================================================================

export interface RoleBadgeProps extends Omit<BadgeProps, 'color' | 'children'> {
    role: 'requester' | 'accounts_admin' | 'director';
}

export function RoleBadge({ role, ...props }: RoleBadgeProps) {
    const config: Record<string, { color: BadgeProps['color']; label: string }> = {
        requester: { color: 'gray', label: 'Employee' },
        accounts_admin: { color: 'blue', label: 'Admin' },
        director: { color: 'purple', label: 'Director' },
    };

    const { color, label } = config[role] || { color: 'gray', label: role };

    return (
        <Badge color={color} variant="outline" {...props}>
            {label}
        </Badge>
    );
}

export default Badge;
