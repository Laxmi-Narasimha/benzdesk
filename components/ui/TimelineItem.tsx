// ============================================================================
// Timeline Item Component
// Vertical step-progress indicator for events
// ============================================================================

import React from 'react';
import { clsx } from 'clsx';
import { MapPin, Play, Square, Navigation, Circle } from 'lucide-react';

export interface TimelineItemProps {
    type: 'start' | 'end' | 'stop' | 'move';
    title: string;
    subtitle?: string;
    time: string;
    address?: string | null;
    meta?: React.ReactNode;
    isLast?: boolean;
    isActive?: boolean;
    onClick?: () => void;
}

export function TimelineItem({
    type,
    title,
    subtitle,
    time,
    address,
    meta,
    isLast = false,
    isActive = false,
    onClick,
}: TimelineItemProps) {
    const getIcon = () => {
        switch (type) {
            case 'start': return <Play className="w-3 h-3 text-green-500 fill-green-500" />;
            case 'end': return <Square className="w-3 h-3 text-red-500 fill-red-500" />;
            case 'stop': return <MapPin className="w-3 h-3 text-amber-500 fill-amber-500" />;
            case 'move': return <Navigation className="w-3 h-3 text-blue-500" />;
            default: return <Circle className="w-3 h-3 text-gray-400" />;
        }
    };

    const getBgColor = () => {
        switch (type) {
            case 'start': return 'bg-green-100 dark:bg-green-900/30 ring-green-500/20';
            case 'end': return 'bg-red-100 dark:bg-red-900/30 ring-red-500/20';
            case 'stop': return 'bg-amber-100 dark:bg-amber-900/30 ring-amber-500/20';
            case 'move': return 'bg-blue-100 dark:bg-blue-900/30 ring-blue-500/20';
            default: return 'bg-gray-100 dark:bg-gray-800 ring-gray-500/20';
        }
    };

    return (
        <div
            className={clsx("relative pl-8 pb-8 group", onClick && "cursor-pointer")}
            onClick={onClick}
        >
            {/* Connecting Line */}
            {!isLast && (
                <div className="absolute left-[15px] top-8 bottom-0 w-px bg-gray-200 dark:bg-dark-700 group-hover:bg-primary-500/30 transition-colors" />
            )}

            {/* Icon Dot */}
            <div className={clsx(
                "absolute left-0 top-1 w-8 h-8 rounded-full flex items-center justify-center ring-4 ring-transparent transition-all",
                getBgColor(),
                isActive && "ring-opacity-100 scale-110"
            )}>
                {getIcon()}
            </div>

            {/* Content */}
            <div className={clsx(
                "flex flex-col sm:flex-row sm:items-start sm:justify-between gap-1 p-3 -mt-2 rounded-xl transition-colors",
                isActive ? "bg-primary-50 dark:bg-primary-900/10" : "hover:bg-gray-50 dark:hover:bg-dark-800/50"
            )}>
                <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                        <span className="font-semibold text-slate-900 text-sm">
                            {title}
                        </span>
                        {subtitle && (
                            <span className="text-xs px-2 py-0.5 rounded-full bg-gray-100 text-gray-600">
                                {subtitle}
                            </span>
                        )}
                    </div>

                    {address && (
                        <p className="text-xs text-gray-500 mt-0.5 truncate max-w-md">
                            📍 {address}
                        </p>
                    )}

                    {meta && (
                        <div className="mt-1 text-xs">{meta}</div>
                    )}
                </div>

                <div className="text-right shrink-0">
                    <div className="font-mono text-xs font-medium text-slate-500 bg-gray-100 px-2 py-1 rounded">
                        {time}
                    </div>
                </div>
            </div>
        </div>
    );
}

export default TimelineItem;
