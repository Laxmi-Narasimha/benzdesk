// ============================================================================
// Loading & Skeleton Components
// Spinners, skeletons, and loading states
// ============================================================================

import React from 'react';
import { clsx } from 'clsx';

// ============================================================================
// Spinner Component
// ============================================================================

export interface SpinnerProps {
    size?: 'sm' | 'md' | 'lg' | 'xl';
    color?: 'primary' | 'white' | 'gray';
    className?: string;
}

export function Spinner({ size = 'md', color = 'primary', className }: SpinnerProps) {
    return (
        <div
            className={clsx(
                'rounded-full animate-spin border-2 border-t-transparent',
                {
                    'w-4 h-4': size === 'sm',
                    'w-5 h-5': size === 'md',
                    'w-8 h-8': size === 'lg',
                    'w-12 h-12': size === 'xl',
                },
                {
                    'border-primary-500 border-t-transparent': color === 'primary',
                    'border-white border-t-transparent': color === 'white',
                    'border-dark-500 border-t-transparent': color === 'gray',
                },
                className
            )}
            role="status"
            aria-label="Loading"
        >
            <span className="sr-only">Loading...</span>
        </div>
    );
}

// ============================================================================
// Full Page Loader
// ============================================================================

export interface PageLoaderProps {
    message?: string;
}

export function PageLoader({ message = 'Loading...' }: PageLoaderProps) {
    return (
        <div className="fixed inset-0 bg-dark-950 flex flex-col items-center justify-center z-50">
            <div className="relative">
                {/* Outer ring */}
                <div className="w-16 h-16 rounded-full border-4 border-dark-800" />

                {/* Spinning arc */}
                <div className="absolute inset-0 w-16 h-16 rounded-full border-4 border-t-primary-500 border-r-transparent border-b-transparent border-l-transparent animate-spin" />

                {/* Inner glow */}
                <div className="absolute inset-2 w-12 h-12 rounded-full bg-primary-500/10 animate-pulse" />
            </div>

            <p className="mt-6 text-dark-400 text-sm font-medium animate-pulse">
                {message}
            </p>
        </div>
    );
}

// ============================================================================
// Skeleton Components
// ============================================================================

export interface SkeletonProps extends React.HTMLAttributes<HTMLDivElement> {
    variant?: 'text' | 'circular' | 'rectangular' | 'rounded';
    width?: string | number;
    height?: string | number;
    lines?: number;
}

export function Skeleton({
    className,
    variant = 'text',
    width,
    height,
    lines = 1,
    style,
    ...props
}: SkeletonProps) {
    const baseClasses = 'animate-pulse bg-dark-700/50';

    if (variant === 'text' && lines > 1) {
        return (
            <div className={clsx('space-y-2', className)} {...props}>
                {Array.from({ length: lines }).map((_, i) => (
                    <div
                        key={i}
                        className={clsx(baseClasses, 'h-4 rounded')}
                        style={{
                            width: i === lines - 1 ? '75%' : '100%',
                            ...style,
                        }}
                    />
                ))}
            </div>
        );
    }

    return (
        <div
            className={clsx(
                baseClasses,
                {
                    'h-4 rounded': variant === 'text',
                    'rounded-full': variant === 'circular',
                    'rounded-none': variant === 'rectangular',
                    'rounded-xl': variant === 'rounded',
                },
                className
            )}
            style={{
                width: width || (variant === 'circular' ? height : '100%'),
                height: height || (variant === 'text' ? undefined : '100%'),
                ...style,
            }}
            {...props}
        />
    );
}

// ============================================================================
// Card Skeleton
// ============================================================================

export function CardSkeleton({ className }: { className?: string }) {
    return (
        <div
            className={clsx(
                'rounded-2xl border border-dark-700/50 bg-dark-800/50 p-6',
                className
            )}
        >
            <div className="flex items-start justify-between mb-4">
                <Skeleton variant="rounded" width={120} height={20} />
                <Skeleton variant="circular" width={36} height={36} />
            </div>
            <Skeleton variant="text" className="mb-2" />
            <Skeleton variant="text" width="60%" />
        </div>
    );
}

// ============================================================================
// Table Skeleton
// ============================================================================

export function TableSkeleton({
    rows = 5,
    columns = 4,
    className,
}: {
    rows?: number;
    columns?: number;
    className?: string;
}) {
    return (
        <div className={clsx('rounded-2xl border border-dark-700/50 overflow-hidden', className)}>
            {/* Header */}
            <div className="bg-dark-800/50 px-4 py-3 flex gap-4">
                {Array.from({ length: columns }).map((_, i) => (
                    <Skeleton
                        key={i}
                        variant="text"
                        width={i === 0 ? '30%' : '15%'}
                        height={12}
                    />
                ))}
            </div>

            {/* Rows */}
            {Array.from({ length: rows }).map((_, rowIndex) => (
                <div
                    key={rowIndex}
                    className="px-4 py-4 border-t border-dark-700/30 flex gap-4"
                >
                    {Array.from({ length: columns }).map((_, colIndex) => (
                        <Skeleton
                            key={colIndex}
                            variant="text"
                            width={colIndex === 0 ? '30%' : '15%'}
                            height={16}
                        />
                    ))}
                </div>
            ))}
        </div>
    );
}

// ============================================================================
// Request List Skeleton
// ============================================================================

export function RequestListSkeleton({ count = 5 }: { count?: number }) {
    return (
        <div className="space-y-4">
            {Array.from({ length: count }).map((_, i) => (
                <div
                    key={i}
                    className="rounded-2xl border border-dark-700/50 bg-dark-800/50 p-5"
                >
                    <div className="flex items-center justify-between mb-3">
                        <Skeleton variant="text" width={200} height={20} />
                        <Skeleton variant="rounded" width={80} height={24} />
                    </div>
                    <Skeleton variant="text" lines={2} className="mb-4" />
                    <div className="flex items-center gap-3">
                        <Skeleton variant="rounded" width={60} height={20} />
                        <Skeleton variant="rounded" width={80} height={20} />
                        <Skeleton variant="text" width={100} height={14} />
                    </div>
                </div>
            ))}
        </div>
    );
}

export default Spinner;
