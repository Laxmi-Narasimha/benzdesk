// ============================================================================
// NotificationBell Component
// Displays notification indicator and dropdown with recent notifications
// ============================================================================

'use client';

import React, { useState, useRef, useEffect } from 'react';
import { createPortal } from 'react-dom';
import { useRouter } from 'next/navigation';
import { clsx } from 'clsx';
import { formatDistanceToNow } from 'date-fns';
import {
    Bell,
    MessageSquare,
    FileText,
    Upload,
    CheckCheck,
    X,
} from 'lucide-react';
import { useNotifications, Notification } from '@/hooks/useNotifications';
import { useAuth } from '@/lib/AuthContext';

// ============================================================================
// Notification Icon Helper
// ============================================================================

function getNotificationIcon(type: Notification['type']) {
    switch (type) {
        case 'comment':
            return <MessageSquare className="w-4 h-4 text-blue-400" />;
        case 'status_change':
            return <FileText className="w-4 h-4 text-green-400" />;
        case 'file_upload':
            return <Upload className="w-4 h-4 text-purple-400" />;
        default:
            return <Bell className="w-4 h-4 text-gray-400" />;
    }
}

// ============================================================================
// NotificationBell Component
// ============================================================================

export function NotificationBell() {
    const router = useRouter();
    const { user, isAdmin, isDirector } = useAuth();
    const { notifications, unreadCount, markAsRead, markAllAsRead } = useNotifications();
    const [isOpen, setIsOpen] = useState(false);
    const [isMounted, setIsMounted] = useState(false);
    const buttonRef = useRef<HTMLButtonElement>(null);
    const dropdownRef = useRef<HTMLDivElement>(null);
    const [isMobile, setIsMobile] = useState(false);
    const [dropdownPosition, setDropdownPosition] = useState({ top: 0, left: 0 });

    // Track mount state to prevent SSR hydration issues
    useEffect(() => {
        setIsMounted(true);
        setIsMobile(window.innerWidth < 640);
    }, []);

    // Calculate dropdown position when opening
    useEffect(() => {
        if (isOpen && buttonRef.current) {
            const viewportWidth = window.innerWidth;
            const isMobileView = viewportWidth < 640;
            setIsMobile(isMobileView);

            if (isMobileView) {
                // On mobile: center the modal (we'll use fixed centering in CSS)
                setDropdownPosition({ top: 0, left: 0 });
            } else {
                // On desktop: position dropdown above the button
                const rect = buttonRef.current.getBoundingClientRect();
                setDropdownPosition({
                    top: rect.top - 8,
                    left: Math.max(16, rect.right - 320),
                });
            }
        }
    }, [isOpen]);

    // Close dropdown when clicking outside
    useEffect(() => {
        function handleClickOutside(event: MouseEvent) {
            if (
                dropdownRef.current &&
                !dropdownRef.current.contains(event.target as Node) &&
                buttonRef.current &&
                !buttonRef.current.contains(event.target as Node)
            ) {
                setIsOpen(false);
            }
        }

        if (isOpen) {
            document.addEventListener('mousedown', handleClickOutside);
            return () => document.removeEventListener('mousedown', handleClickOutside);
        }
    }, [isOpen]);

    // Close on escape key
    useEffect(() => {
        function handleEscape(event: KeyboardEvent) {
            if (event.key === 'Escape') setIsOpen(false);
        }
        if (isOpen) {
            document.addEventListener('keydown', handleEscape);
            return () => document.removeEventListener('keydown', handleEscape);
        }
    }, [isOpen]);

    if (!user) return null;

    const handleNotificationClick = (notification: Notification) => {
        markAsRead(notification.id);

        if (notification.request_id) {
            if (isAdmin || isDirector) {
                router.push(`/admin/request?id=${notification.request_id}`);
            } else {
                router.push(`/app/request?id=${notification.request_id}`);
            }
        }

        setIsOpen(false);
    };

    const dropdownContent = (
        <>
            {/* Mobile backdrop */}
            {isMobile && (
                <div
                    className="fixed inset-0 bg-black/50 backdrop-blur-sm"
                    style={{ zIndex: 9998 }}
                    onClick={() => setIsOpen(false)}
                />
            )}
            <div
                ref={dropdownRef}
                className={clsx(
                    'fixed bg-white border border-gray-200 shadow-2xl flex flex-col',
                    isMobile
                        ? 'inset-2 rounded-2xl'
                        : 'w-80 rounded-xl overflow-hidden'
                )}
                style={isMobile ? { zIndex: 9999 } : {
                    top: dropdownPosition.top,
                    left: dropdownPosition.left,
                    transform: 'translateY(-100%)',
                    zIndex: 9999,
                }}
            >
                {/* Header with X close button */}
                <div className="flex items-center justify-between px-4 py-3 border-b border-gray-200 bg-gray-50">
                    <h3 className="text-sm font-semibold text-gray-900">Notifications</h3>
                    <div className="flex items-center gap-2">
                        {unreadCount > 0 && (
                            <button
                                onClick={(e) => {
                                    e.stopPropagation();
                                    markAllAsRead();
                                }}
                                className="flex items-center gap-1.5 text-xs text-gray-500 hover:text-gray-700 transition-colors px-2 py-1 rounded hover:bg-gray-200"
                            >
                                <CheckCheck className="w-3.5 h-3.5" />
                                Mark all read
                            </button>
                        )}
                        <button
                            onClick={() => setIsOpen(false)}
                            className="p-1.5 text-gray-400 hover:text-gray-600 hover:bg-gray-200 rounded-lg transition-colors"
                            aria-label="Close notifications"
                        >
                            <X className="w-5 h-5" />
                        </button>
                    </div>
                </div>

                <div className={clsx(
                    'overflow-y-auto',
                    isMobile ? 'flex-1' : 'max-h-80'
                )}>
                    {notifications.length === 0 ? (
                        <div className="px-4 py-8 text-center">
                            <Bell className="w-10 h-10 mx-auto mb-3 text-gray-300" />
                            <p className="text-sm text-gray-500">No notifications yet</p>
                            <p className="text-xs text-gray-400 mt-1">
                                You'll be notified of updates to your requests
                            </p>
                        </div>
                    ) : (
                        <div className="divide-y divide-gray-100">
                            {notifications.slice(0, 10).map((notification) => (
                                <button
                                    key={notification.id}
                                    onClick={() => handleNotificationClick(notification)}
                                    className={clsx(
                                        'w-full flex items-start gap-3 px-4 py-3 text-left transition-colors',
                                        'hover:bg-gray-50',
                                        !notification.is_read && 'bg-primary-50'
                                    )}
                                >
                                    {/* Icon */}
                                    <div className="flex-shrink-0 mt-0.5 p-1.5 rounded-lg bg-dark-800">
                                        {getNotificationIcon(notification.type)}
                                    </div>

                                    {/* Content */}
                                    <div className="flex-1 min-w-0">
                                        <p className={clsx(
                                            'text-sm leading-tight',
                                            notification.is_read ? 'text-dark-300' : 'text-dark-100 font-medium'
                                        )}>
                                            {notification.title}
                                        </p>
                                        <p className="text-xs text-dark-500 mt-1 line-clamp-2">
                                            {notification.message}
                                        </p>
                                        <p className="text-xs text-gray-400 mt-1.5" suppressHydrationWarning>
                                            {formatDistanceToNow(new Date(notification.created_at), { addSuffix: true })}
                                        </p>
                                    </div>

                                    {/* Unread indicator */}
                                    {!notification.is_read && (
                                        <div className="flex-shrink-0 mt-1.5">
                                            <span className="w-2 h-2 rounded-full bg-primary-500 block animate-pulse" />
                                        </div>
                                    )}
                                </button>
                            ))}
                        </div>
                    )}
                </div>

                {/* Footer */}
                {notifications.length > 10 && (
                    <div className="px-4 py-2 border-t border-gray-200 bg-gray-50 text-center">
                        <span className="text-xs text-gray-500">
                            Showing 10 of {notifications.length} notifications
                        </span>
                    </div>
                )}
            </div>
        </>
    );

    return (
        <>
            <button
                ref={buttonRef}
                onClick={() => setIsOpen(!isOpen)}
                className={clsx(
                    'relative p-2 rounded-lg transition-all duration-200',
                    'text-gray-500 hover:text-gray-700 hover:bg-gray-100',
                    isOpen && 'bg-gray-100 text-gray-700 ring-2 ring-primary-500/30'
                )}
                aria-label={`Notifications ${unreadCount > 0 ? `(${unreadCount} unread)` : ''}`}
            >
                <Bell className="w-5 h-5" />

                {/* Unread Badge */}
                {unreadCount > 0 && (
                    <span className="absolute -top-1 -right-1 min-w-[20px] h-5 flex items-center justify-center text-xs font-bold text-white bg-red-500 rounded-full px-1 shadow-lg animate-pulse">
                        {unreadCount > 99 ? '99+' : unreadCount}
                    </span>
                )}
            </button>

            {/* Dropdown Portal - only render on client after mount */}
            {isMounted && isOpen && createPortal(dropdownContent, document.body)}
        </>
    );
}

export default NotificationBell;

