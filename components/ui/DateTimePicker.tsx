// ============================================================================
// DateTimePicker Component (Light Mode)
// Intuitive date and time selection with presets and calendar
// ============================================================================

'use client';

import React, { useState, useRef, useEffect } from 'react';
import { createPortal } from 'react-dom';
import { clsx } from 'clsx';
import { format, addDays, startOfDay, setHours, setMinutes, isBefore, isToday } from 'date-fns';
import { Calendar, Clock, X, ChevronLeft, ChevronRight } from 'lucide-react';

// ============================================================================
// Types
// ============================================================================

interface DateTimePickerProps {
    value: string | null; // ISO string or null
    onChange: (value: string | null) => void;
    minDate?: Date;
    disabled?: boolean;
    placeholder?: string;
}

interface QuickOption {
    label: string;
    getValue: () => Date;
}

// ============================================================================
// Quick Select Options
// ============================================================================

const quickOptions: QuickOption[] = [
    { label: 'Today 6 PM', getValue: () => setHours(setMinutes(startOfDay(new Date()), 0), 18) },
    { label: 'Tomorrow 6 PM', getValue: () => setHours(setMinutes(startOfDay(addDays(new Date(), 1)), 0), 18) },
    { label: 'In 2 Days', getValue: () => setHours(setMinutes(startOfDay(addDays(new Date(), 2)), 0), 18) },
    { label: 'Next Week', getValue: () => setHours(setMinutes(startOfDay(addDays(new Date(), 7)), 0), 18) },
];

const timeOptions = [
    { label: '9:00 AM', hours: 9, minutes: 0 },
    { label: '12:00 PM', hours: 12, minutes: 0 },
    { label: '3:00 PM', hours: 15, minutes: 0 },
    { label: '6:00 PM', hours: 18, minutes: 0 },
    { label: '9:00 PM', hours: 21, minutes: 0 },
];

// ============================================================================
// Component
// ============================================================================

export function DateTimePicker({
    value,
    onChange,
    minDate = new Date(),
    disabled = false,
    placeholder = 'Set deadline (optional)',
}: DateTimePickerProps) {
    const [isOpen, setIsOpen] = useState(false);
    const [isMounted, setIsMounted] = useState(false);
    const [viewDate, setViewDate] = useState(new Date());
    const buttonRef = useRef<HTMLButtonElement>(null);
    const dropdownRef = useRef<HTMLDivElement>(null);
    const [position, setPosition] = useState({ top: 0, left: 0, width: 320, openUp: false });

    // Parse current value
    const currentDate = value ? new Date(value) : null;

    // Track mount state to prevent SSR hydration issues
    useEffect(() => {
        setIsMounted(true);
    }, []);

    // Calculate position when opening
    useEffect(() => {
        if (isOpen && buttonRef.current) {
            const rect = buttonRef.current.getBoundingClientRect();
            const viewportHeight = window.innerHeight;
            const viewportWidth = window.innerWidth;
            const dropdownHeight = 420;
            const isMobile = viewportWidth < 640;

            if (isMobile) {
                // On mobile: center the dropdown on screen
                setPosition({
                    top: Math.max(16, (viewportHeight - dropdownHeight) / 2),
                    left: (viewportWidth - 320) / 2,
                    width: 320,
                    openUp: false,
                });
            } else {
                // On desktop: position near button
                const openUp = rect.bottom + dropdownHeight > viewportHeight;
                setPosition({
                    top: openUp ? rect.top : rect.bottom + 4,
                    left: Math.max(8, Math.min(rect.left, viewportWidth - 328)),
                    width: Math.min(rect.width, 320),
                    openUp,
                });
            }
        }
    }, [isOpen]);

    // Close on click outside
    useEffect(() => {
        if (!isOpen) return;

        function handleClick(e: MouseEvent) {
            if (
                dropdownRef.current && !dropdownRef.current.contains(e.target as Node) &&
                buttonRef.current && !buttonRef.current.contains(e.target as Node)
            ) {
                setIsOpen(false);
            }
        }

        document.addEventListener('mousedown', handleClick);
        return () => document.removeEventListener('mousedown', handleClick);
    }, [isOpen]);

    // Generate calendar days
    const generateCalendarDays = () => {
        const year = viewDate.getFullYear();
        const month = viewDate.getMonth();
        const firstDay = new Date(year, month, 1);
        const lastDay = new Date(year, month + 1, 0);
        const startPadding = firstDay.getDay();
        const days: (Date | null)[] = [];

        for (let i = 0; i < startPadding; i++) {
            days.push(null);
        }

        for (let day = 1; day <= lastDay.getDate(); day++) {
            days.push(new Date(year, month, day));
        }

        return days;
    };

    // Handle date selection
    const handleDateSelect = (date: Date) => {
        const hours = currentDate?.getHours() ?? 18;
        const minutes = currentDate?.getMinutes() ?? 0;
        const newDate = setHours(setMinutes(date, minutes), hours);
        onChange(newDate.toISOString());
    };

    // Handle time selection
    const handleTimeSelect = (hours: number, minutes: number) => {
        const date = currentDate ?? new Date();
        const newDate = setHours(setMinutes(date, minutes), hours);
        onChange(newDate.toISOString());
    };

    // Handle quick option
    const handleQuickOption = (option: QuickOption) => {
        onChange(option.getValue().toISOString());
        setIsOpen(false);
    };

    // Clear value
    const handleClear = (e: React.MouseEvent) => {
        e.stopPropagation();
        onChange(null);
    };

    // Format display value
    const displayValue = currentDate
        ? `${format(currentDate, 'MMM d, yyyy')} at ${format(currentDate, 'h:mm a')}`
        : null;

    // Check if we're on mobile for backdrop
    const isMobile = typeof window !== 'undefined' && window.innerWidth < 640;

    const dropdownContent = (
        <>
            {/* Mobile backdrop overlay */}
            {isMobile && (
                <div
                    className="fixed inset-0 bg-black/40 backdrop-blur-sm"
                    style={{ zIndex: 9998 }}
                    onClick={() => setIsOpen(false)}
                />
            )}
            <div
                ref={dropdownRef}
                className="fixed w-80 bg-white border border-gray-200 rounded-xl shadow-2xl overflow-hidden max-h-[90vh] overflow-y-auto"
                style={{
                    top: position.openUp ? position.top : position.top,
                    left: position.left,
                    transform: position.openUp ? 'translateY(-100%)' : undefined,
                    zIndex: 9999,
                }}
            >
                {/* Quick options */}
                <div className="p-3 bg-gray-50 border-b border-gray-200">
                    <p className="text-xs text-gray-500 uppercase tracking-wider mb-2 font-medium">Quick Select</p>
                    <div className="flex flex-wrap gap-2">
                        {quickOptions.map((option) => (
                            <button
                                key={option.label}
                                type="button"
                                onClick={() => handleQuickOption(option)}
                                className="px-3 py-1.5 text-xs bg-white border border-gray-200 hover:border-primary-400 hover:bg-primary-50 text-gray-700 rounded-lg transition-colors"
                            >
                                {option.label}
                            </button>
                        ))}
                    </div>
                </div>

                {/* Calendar header */}
                <div className="flex items-center justify-between px-4 py-2 border-b border-gray-100">
                    <button
                        type="button"
                        onClick={() => setViewDate(new Date(viewDate.getFullYear(), viewDate.getMonth() - 1))}
                        className="p-1.5 text-gray-400 hover:text-gray-700 hover:bg-gray-100 rounded-lg transition-colors"
                    >
                        <ChevronLeft className="w-4 h-4" />
                    </button>
                    <span className="text-sm font-semibold text-gray-900">
                        {format(viewDate, 'MMMM yyyy')}
                    </span>
                    <button
                        type="button"
                        onClick={() => setViewDate(new Date(viewDate.getFullYear(), viewDate.getMonth() + 1))}
                        className="p-1.5 text-gray-400 hover:text-gray-700 hover:bg-gray-100 rounded-lg transition-colors"
                    >
                        <ChevronRight className="w-4 h-4" />
                    </button>
                </div>

                {/* Calendar grid */}
                <div className="p-3">
                    <div className="grid grid-cols-7 gap-1 mb-1">
                        {['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'].map((day) => (
                            <div key={day} className="text-center text-xs text-gray-400 py-1 font-medium">
                                {day}
                            </div>
                        ))}
                    </div>
                    <div className="grid grid-cols-7 gap-1">
                        {generateCalendarDays().map((date, idx) => {
                            if (!date) {
                                return <div key={`empty-${idx}`} className="p-2" />;
                            }

                            const isPast = isBefore(date, startOfDay(minDate));
                            const isSelected = currentDate && format(date, 'yyyy-MM-dd') === format(currentDate, 'yyyy-MM-dd');
                            const isTodayDate = isToday(date);

                            return (
                                <button
                                    key={date.toISOString()}
                                    type="button"
                                    onClick={() => !isPast && handleDateSelect(date)}
                                    disabled={isPast}
                                    className={clsx(
                                        'p-2 text-sm rounded-lg transition-colors font-medium',
                                        isPast && 'text-gray-300 cursor-not-allowed',
                                        !isPast && !isSelected && 'text-gray-700 hover:bg-gray-100',
                                        isSelected && 'bg-primary-500 text-white',
                                        isTodayDate && !isSelected && 'ring-1 ring-primary-500 text-primary-600'
                                    )}
                                >
                                    {date.getDate()}
                                </button>
                            );
                        })}
                    </div>
                </div>

                {/* Time selection */}
                <div className="p-3 border-t border-gray-100">
                    <p className="text-xs text-gray-500 uppercase tracking-wider mb-2 flex items-center gap-1 font-medium">
                        <Clock className="w-3 h-3" />
                        Time
                    </p>
                    <div className="flex flex-wrap gap-2">
                        {timeOptions.map((option) => {
                            const isSelected = currentDate &&
                                currentDate.getHours() === option.hours &&
                                currentDate.getMinutes() === option.minutes;

                            return (
                                <button
                                    key={option.label}
                                    type="button"
                                    onClick={() => handleTimeSelect(option.hours, option.minutes)}
                                    className={clsx(
                                        'px-3 py-1.5 text-xs rounded-lg transition-colors font-medium',
                                        isSelected
                                            ? 'bg-primary-500 text-white'
                                            : 'bg-gray-100 hover:bg-gray-200 text-gray-700'
                                    )}
                                >
                                    {option.label}
                                </button>
                            );
                        })}
                    </div>
                </div>

                {/* Footer */}
                <div className="flex items-center justify-between px-3 py-2 border-t border-gray-100 bg-gray-50">
                    <button
                        type="button"
                        onClick={() => {
                            onChange(null);
                            setIsOpen(false);
                        }}
                        className="text-xs text-gray-500 hover:text-gray-700 transition-colors font-medium"
                    >
                        Clear
                    </button>
                    <button
                        type="button"
                        onClick={() => setIsOpen(false)}
                        className="px-4 py-1.5 text-xs bg-primary-500 text-white rounded-lg hover:bg-primary-600 transition-colors font-medium"
                    >
                        Done
                    </button>
                </div>
            </div>
        </>
    );

    return (
        <>
            <button
                ref={buttonRef}
                type="button"
                onClick={() => !disabled && setIsOpen(!isOpen)}
                disabled={disabled}
                className={clsx(
                    'w-full flex items-center justify-between px-4 py-3 bg-gray-50 border rounded-lg text-left transition-all',
                    disabled && 'opacity-50 cursor-not-allowed',
                    isOpen ? 'border-primary-500 ring-2 ring-primary-500/20' : 'border-gray-300 hover:border-gray-400',
                    currentDate ? 'text-gray-900' : 'text-gray-500'
                )}
            >
                <span className="flex items-center gap-2">
                    <Calendar className="w-4 h-4 text-gray-400" />
                    {displayValue || placeholder}
                </span>
                {currentDate && (
                    <button
                        type="button"
                        onClick={handleClear}
                        className="p-1 text-gray-400 hover:text-gray-600 transition-colors"
                    >
                        <X className="w-4 h-4" />
                    </button>
                )}
            </button>

            {/* Only render portal on client after mount */}
            {isMounted && isOpen && createPortal(dropdownContent, document.body)}
        </>
    );
}

export default DateTimePicker;
