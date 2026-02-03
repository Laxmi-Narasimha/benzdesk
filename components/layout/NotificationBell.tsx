// ============================================================================
// NotificationBell Component
// Displays notification indicator and dropdown with recent notifications
// Improved formatting, better names/titles display, responsive design
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
    ArrowRight,
    User,
} from 'lucide-react';
import { useNotifications, Notification } from '@/hooks/useNotifications';
import { useAuth } from '@/lib/AuthContext';

// ============================================================================
// Notification Icon Helper
// ============================================================================

function getNotificationIcon(type: Notification['type']) {
    const iconClass = "w-4 h-4";
    switch (type) {
        case 'comment':
            return <MessageSquare className={`${iconClass} text-blue-400`} />;
        case 'status_change':
            return <FileText className={`${iconClass} text-emerald-400`} />;
        case 'file_upload':
            return <Upload className={`${iconClass} text-purple-400`} />;
        default:
            return <Bell className={`${iconClass} text-amber-400`} />;
    }
}

// ============================================================================
// Type Label Helper
// ============================================================================

function getTypeLabel(type: Notification['type']) {
    switch (type) {
        case 'comment':
            return 'New Comment';
        case 'status_change':
            return 'Status Updated';
        case 'file_upload':
            return 'File Uploaded';
        case 'mention':
            return 'You were mentioned';
        default:
            return 'Notification';
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
                setDropdownPosition({ top: 0, left: 0 });
            } else {
                const rect = buttonRef.current.getBoundingClientRect();
                setDropdownPosition({
                    top: rect.top - 8,
                    left: Math.max(16, rect.right - 360),
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

    // Parse notification content for better display
    const parseNotificationContent = (notification: Notification) => {
        // Extract sender name from title if present (format: "Name commented" or similar)
        const title = notification.title || '';
        const message = notification.message || '';

        // Try to extract person name and request title from message
        // Common formats: "On: Request Title", "Request: Title"
        let requestTitle = '';
        let senderName = '';
        let content = message;

        // Extract sender from title (e.g., "💬 John commented" -> "John")
        const titleMatch = title.match(/(?:💬|📎|🔄|📩)\s*(.+?)\s+(?:commented|replied|uploaded|updated|submitted)/i);
        if (titleMatch) {
            senderName = titleMatch[1].trim();
        }

        // Extract request title from message (e.g., "On: My Request\n...")
        const requestMatch = message.match(/(?:On:|Request:)\s*(.+?)(?:\n|$)/i);
        if (requestMatch) {
            requestTitle = requestMatch[1].trim();
            content = message.replace(requestMatch[0], '').trim();
        }

        // Clean up content - remove quotes and excess whitespace
        content = content.replace(/^["']|["']$/g, '').trim();

        return { senderName, requestTitle, content };
    };

    const dropdownContent = (
        <>
            {/* Mobile backdrop */}
            {isMobile && (
                <div
                    className="fixed inset-0 bg-black/60 backdrop-blur-sm"
                    style={{ zIndex: 9998 }}
                    onClick={() => setIsOpen(false)}
                />
            )}
            <div
                ref={dropdownRef}
                className={clsx(
                    'fixed bg-white border border-gray-200 shadow-2xl flex flex-col',
                    isMobile
                        ? 'inset-3 rounded-2xl'
                        : 'w-[360px] rounded-xl overflow-hidden'
                )}
                style={isMobile ? { zIndex: 9999 } : {
                    top: dropdownPosition.top,
                    left: dropdownPosition.left,
                    transform: 'translateY(-100%)',
                    zIndex: 9999,
                }}
            >
                {/* Header */}
                <div className="flex items-center justify-between px-4 py-3 border-b border-gray-100 bg-gradient-to-r from-primary-500 to-primary-600">
                    <div className="flex items-center gap-2">
                        <Bell className="w-4 h-4 text-white" />
                        <h3 className="text-sm font-semibold text-white">Notifications</h3>
                        {unreadCount > 0 && (
                            <span className="px-1.5 py-0.5 text-xs font-bold bg-white/20 text-white rounded-full">
                                {unreadCount} new
                            </span>
                        )}
                    </div>
                    <div className="flex items-center gap-1">
                        {unreadCount > 0 && (
                            <button
                                onClick={(e) => {
                                    e.stopPropagation();
                                    markAllAsRead();
                                }}
                                className="flex items-center gap-1 text-xs text-white/80 hover:text-white transition-colors px-2 py-1 rounded hover:bg-white/10"
                            >
                                <CheckCheck className="w-3.5 h-3.5" />
                                <span className="hidden sm:inline">Mark all read</span>
                            </button>
                        )}
                        <button
                            onClick={() => setIsOpen(false)}
                            className="p-1.5 text-white/70 hover:text-white hover:bg-white/10 rounded-lg transition-colors"
                            aria-label="Close notifications"
                        >
                            <X className="w-5 h-5" />
                        </button>
                    </div>
                </div>

                {/* Notification List */}
                <div className={clsx(
                    'overflow-y-auto',
                    isMobile ? 'flex-1' : 'max-h-[400px]'
                )}>
                    {notifications.length === 0 ? (
                        <div className="px-6 py-12 text-center">
                            <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-gray-100 flex items-center justify-center">
                                <Bell className="w-8 h-8 text-gray-300" />
                            </div>
                            <p className="text-sm font-medium text-gray-600">No notifications yet</p>
                            <p className="text-xs text-gray-400 mt-1 max-w-[200px] mx-auto">
                                You&apos;ll be notified when there are updates to your requests
                            </p>
                        </div>
                    ) : (
                        <div className="divide-y divide-gray-50">
                            {notifications.map((notification) => {
                                const { senderName, requestTitle, content } = parseNotificationContent(notification);

                                return (
                                    <button
                                        key={notification.id}
                                        onClick={() => handleNotificationClick(notification)}
                                        className={clsx(
                                            'w-full flex items-start gap-3 px-4 py-3 text-left transition-all duration-200',
                                            'hover:bg-gray-50 active:bg-gray-100',
                                            !notification.is_read && 'bg-primary-50/50 border-l-3 border-l-primary-500'
                                        )}
                                    >
                                        {/* Icon with colored background */}
                                        <div className={clsx(
                                            'flex-shrink-0 mt-0.5 p-2 rounded-lg',
                                            notification.type === 'comment' && 'bg-blue-100',
                                            notification.type === 'status_change' && 'bg-emerald-100',
                                            notification.type === 'file_upload' && 'bg-purple-100',
                                            notification.type === 'mention' && 'bg-amber-100',
                                            !['comment', 'status_change', 'file_upload', 'mention'].includes(notification.type) && 'bg-gray-100'
                                        )}>
                                            {getNotificationIcon(notification.type)}
                                        </div>

                                        {/* Content */}
                                        <div className="flex-1 min-w-0 space-y-1">
                                            {/* Type Label */}
                                            <div className="flex items-center gap-2">
                                                <span className={clsx(
                                                    'text-xs font-semibold uppercase tracking-wide',
                                                    notification.type === 'comment' && 'text-blue-600',
                                                    notification.type === 'status_change' && 'text-emerald-600',
                                                    notification.type === 'file_upload' && 'text-purple-600',
                                                    notification.type === 'mention' && 'text-amber-600',
                                                    !['comment', 'status_change', 'file_upload', 'mention'].includes(notification.type) && 'text-gray-600'
                                                )}>
                                                    {getTypeLabel(notification.type)}
                                                </span>
                                                {!notification.is_read && (
                                                    <span className="w-2 h-2 rounded-full bg-primary-500 animate-pulse" />
                                                )}
                                            </div>

                                            {/* Sender Name */}
                                            {senderName && (
                                                <div className="flex items-center gap-1.5">
                                                    <User className="w-3 h-3 text-gray-400" />
                                                    <span className="text-sm font-medium text-gray-800 truncate">
                                                        {senderName}
                                                    </span>
                                                </div>
                                            )}

                                            {/* Request Title */}
                                            {requestTitle && (
                                                <p className="text-sm text-gray-700 font-medium truncate">
                                                    <span className="text-gray-400">on </span>
                                                    &quot;{requestTitle}&quot;
                                                </p>
                                            )}

                                            {/* Message Preview */}
                                            {content && (
                                                <p className="text-xs text-gray-500 line-clamp-2">
                                                    {content}
                                                </p>
                                            )}

                                            {/* Timestamp */}
                                            <p className="text-xs text-gray-400 mt-1" suppressHydrationWarning>
                                                {formatDistanceToNow(new Date(notification.created_at), { addSuffix: true })}
                                            </p>
                                        </div>

                                        {/* Arrow indicator */}
                                        <div className="flex-shrink-0 self-center opacity-0 group-hover:opacity-100 transition-opacity">
                                            <ArrowRight className="w-4 h-4 text-gray-300" />
                                        </div>
                                    </button>
                                );
                            })}
                        </div>
                    )}
                </div>

                {/* Footer */}
                {notifications.length > 0 && (
                    <div className="px-4 py-2.5 border-t border-gray-100 bg-gray-50/50 text-center">
                        <span className="text-xs text-gray-500">
                            Showing latest {notifications.length} notification{notifications.length !== 1 ? 's' : ''}
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
                    'relative p-2.5 rounded-xl transition-all duration-200',
                    'text-gray-500 hover:text-gray-700 hover:bg-gray-100',
                    isOpen && 'bg-primary-100 text-primary-600 ring-2 ring-primary-500/30'
                )}
                aria-label={`Notifications ${unreadCount > 0 ? `(${unreadCount} unread)` : ''}`}
            >
                <Bell className="w-5 h-5" />

                {/* Unread Badge */}
                {unreadCount > 0 && (
                    <span className="absolute -top-1 -right-1 min-w-[20px] h-5 flex items-center justify-center text-xs font-bold text-white bg-red-500 rounded-full px-1.5 shadow-lg ring-2 ring-white animate-pulse">
                        {unreadCount > 9 ? '9+' : unreadCount}
                    </span>
                )}
            </button>

            {/* Dropdown Portal - only render on client after mount */}
            {isMounted && isOpen && createPortal(dropdownContent, document.body)}
        </>
    );
}

export default NotificationBell;
