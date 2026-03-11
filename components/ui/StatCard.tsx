// ============================================================================
// StatCard Component
// Specialized card for dashboard metrics
// ============================================================================

import React from 'react';
import { clsx } from 'clsx';
import { Card } from './Card';
import { TrendingUp, TrendingDown, Minus } from 'lucide-react';

export interface StatCardProps {
    title: string;
    value: string | number;
    icon?: React.ReactNode;
    trend?: {
        value: number;
        label: string;
        direction: 'up' | 'down' | 'neutral';
    };
    color?: 'primary' | 'success' | 'warning' | 'danger' | 'info';
    className?: string;
    onClick?: () => void;
}

const COLORS = {
    primary: 'bg-primary-50 text-primary-600 dark:bg-primary-900/20 dark:text-primary-400',
    success: 'bg-green-50 text-green-600 dark:bg-green-900/20 dark:text-green-400',
    warning: 'bg-amber-50 text-amber-600 dark:bg-amber-900/20 dark:text-amber-400',
    danger: 'bg-red-50 text-red-600 dark:bg-red-900/20 dark:text-red-400',
    info: 'bg-blue-50 text-blue-600 dark:bg-blue-900/20 dark:text-blue-400',
};

export function StatCard({
    title,
    value,
    icon,
    trend,
    color = 'primary',
    className,
    onClick,
}: StatCardProps) {
    return (
        <Card
            className={clsx('relative overflow-hidden', className)}
            hover={!!onClick}
            onClick={onClick}
            padding="md"
        >
            <div className="flex justify-between items-start">
                <div className="space-y-1">
                    <p className="text-sm font-medium text-slate-500">
                        {title}
                    </p>
                    <h3 className="text-2xl font-bold text-slate-900">
                        {value}
                    </h3>
                </div>
                {icon && (
                    <div className={clsx('p-3 rounded-xl', COLORS[color])}>
                        {React.cloneElement(icon as React.ReactElement, { className: 'w-5 h-5' })}
                    </div>
                )}
            </div>

            {trend && (
                <div className="mt-4 flex items-center gap-2 text-sm">
                    <span
                        className={clsx(
                            'flex items-center gap-1 font-medium',
                            trend.direction === 'up' && 'text-green-600 dark:text-green-400',
                            trend.direction === 'down' && 'text-red-600 dark:text-red-400',
                            trend.direction === 'neutral' && 'text-dark-400'
                        )}
                    >
                        {trend.direction === 'up' && <TrendingUp className="w-4 h-4" />}
                        {trend.direction === 'down' && <TrendingDown className="w-4 h-4" />}
                        {trend.direction === 'neutral' && <Minus className="w-4 h-4" />}
                        {Math.abs(trend.value)}%
                    </span>
                    <span className="text-dark-400">
                        {trend.label}
                    </span>
                </div>
            )}
        </Card>
    );
}

export default StatCard;
