// ============================================================================
// Card Component
// Glass-morphism container with variants
// ============================================================================

import React from 'react';
import { clsx } from 'clsx';

// ============================================================================
// Types
// ============================================================================

export interface CardProps extends React.HTMLAttributes<HTMLDivElement> {
    variant?: 'default' | 'outlined' | 'elevated';
    padding?: 'none' | 'sm' | 'md' | 'lg';
    hover?: boolean;
}

// ============================================================================
// Card Component
// ============================================================================

export const Card = React.forwardRef<HTMLDivElement, CardProps>(
    (
        {
            className,
            variant = 'default',
            padding = 'md',
            hover = false,
            children,
            ...props
        },
        ref
    ) => {
        return (
            <div
                ref={ref}
                className={clsx(
                    // Base styles
                    'relative rounded-2xl overflow-hidden',
                    'transition-all duration-300',

                    // Variants
                    {
                        // Default - glass effect
                        'bg-gradient-to-br from-dark-800/80 to-dark-900/80 backdrop-blur-xl border border-dark-700/50':
                            variant === 'default',

                        // Outlined - transparent with border
                        'bg-transparent border border-dark-700/50':
                            variant === 'outlined',

                        // Elevated - more visible
                        'bg-dark-800/90 backdrop-blur-xl border border-dark-700/50 shadow-glass':
                            variant === 'elevated',
                    },

                    // Padding
                    {
                        'p-0': padding === 'none',
                        'p-4': padding === 'sm',
                        'p-6': padding === 'md',
                        'p-8': padding === 'lg',
                    },

                    // Hover effect
                    hover && 'hover:border-primary-500/30 hover:shadow-glow cursor-pointer',

                    className
                )}
                {...props}
            >
                {/* Subtle gradient overlay */}
                <div className="absolute inset-0 bg-gradient-to-br from-white/5 to-transparent pointer-events-none" />

                {/* Content */}
                <div className="relative">{children}</div>
            </div>
        );
    }
);

Card.displayName = 'Card';

// ============================================================================
// Card Header
// ============================================================================

export interface CardHeaderProps extends React.HTMLAttributes<HTMLDivElement> {
    title?: string;
    description?: string;
    action?: React.ReactNode;
}

export function CardHeader({
    className,
    title,
    description,
    action,
    children,
    ...props
}: CardHeaderProps) {
    return (
        <div
            className={clsx(
                'flex items-start justify-between gap-4',
                className
            )}
            {...props}
        >
            <div className="flex-1 min-w-0">
                {title && (
                    <h3 className="text-lg font-semibold text-dark-50 truncate">
                        {title}
                    </h3>
                )}
                {description && (
                    <p className="text-sm text-dark-400 mt-1">
                        {description}
                    </p>
                )}
                {children}
            </div>
            {action && (
                <div className="flex-shrink-0">{action}</div>
            )}
        </div>
    );
}

// ============================================================================
// Card Content
// ============================================================================

export interface CardContentProps extends React.HTMLAttributes<HTMLDivElement> { }

export function CardContent({ className, ...props }: CardContentProps) {
    return (
        <div className={clsx('mt-4', className)} {...props} />
    );
}

// ============================================================================
// Card Footer
// ============================================================================

export interface CardFooterProps extends React.HTMLAttributes<HTMLDivElement> { }

export function CardFooter({ className, ...props }: CardFooterProps) {
    return (
        <div
            className={clsx(
                'mt-6 pt-4 border-t border-dark-700/50 flex items-center gap-3',
                className
            )}
            {...props}
        />
    );
}

// ============================================================================
// Metric Card
// ============================================================================

export interface MetricCardProps {
    title: string;
    value: string | number;
    change?: number;
    changeLabel?: string;
    icon?: React.ReactNode;
    trend?: 'up' | 'down' | 'neutral';
    className?: string;
}

export function MetricCard({
    title,
    value,
    change,
    changeLabel,
    icon,
    trend = 'neutral',
    className,
}: MetricCardProps) {
    return (
        <Card className={clsx('', className)}>
            <div className="flex items-start justify-between">
                <div>
                    <p className="text-sm font-medium text-dark-400 uppercase tracking-wider">
                        {title}
                    </p>
                    <p className="text-3xl font-bold mt-2 bg-gradient-to-r from-primary-400 to-primary-200 bg-clip-text text-transparent">
                        {value}
                    </p>
                    {change !== undefined && (
                        <p className={clsx(
                            'text-sm mt-2 flex items-center gap-1',
                            {
                                'text-green-400': trend === 'up',
                                'text-red-400': trend === 'down',
                                'text-dark-400': trend === 'neutral',
                            }
                        )}>
                            <span>
                                {change > 0 ? '+' : ''}{change}%
                            </span>
                            {changeLabel && (
                                <span className="text-dark-500">{changeLabel}</span>
                            )}
                        </p>
                    )}
                </div>
                {icon && (
                    <div className="p-3 rounded-xl bg-primary-500/10 text-primary-400">
                        {icon}
                    </div>
                )}
            </div>
        </Card>
    );
}

export default Card;
