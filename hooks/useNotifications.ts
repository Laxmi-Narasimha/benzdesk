// ============================================================================
// Notifications Hook
// Fetches and manages user notifications with real-time updates + browser push
// ============================================================================

'use client';

import { useState, useEffect, useCallback } from 'react';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { useAuth } from '@/lib/AuthContext';

// ============================================================================
// Types
// ============================================================================

export interface Notification {
    id: string;
    user_id: string;
    request_id: string | null;
    type: 'comment' | 'status_change' | 'file_upload' | 'mention';
    title: string;
    message: string;
    is_read: boolean;
    created_at: string;
}

// ============================================================================
// Browser Notification Helpers
// ============================================================================

const NOTIFICATION_PERMISSION_KEY = 'benzdesk_notification_permission';

function getBrowserPermissionStatus(): 'granted' | 'denied' | 'default' | 'unsupported' {
    if (typeof window === 'undefined' || !('Notification' in window)) {
        return 'unsupported';
    }
    return Notification.permission;
}

async function requestBrowserPermission(): Promise<boolean> {
    if (typeof window === 'undefined' || !('Notification' in window)) {
        return false;
    }

    try {
        const permission = await Notification.requestPermission();
        localStorage.setItem(NOTIFICATION_PERMISSION_KEY, permission);
        return permission === 'granted';
    } catch (err) {
        console.error('Error requesting notification permission:', err);
        return false;
    }
}

function showBrowserNotification(notification: Notification) {
    if (getBrowserPermissionStatus() !== 'granted') return;
    if (typeof window === 'undefined') return;

    // Only show if page is not visible (user is in another tab)
    if (document.visibilityState === 'visible') return;

    try {
        const browserNotif = new Notification(notification.title, {
            body: notification.message,
            icon: '/favicon.ico',
            badge: '/favicon.ico',
            tag: notification.id,
            requireInteraction: false,
        });

        browserNotif.onclick = () => {
            window.focus();
            browserNotif.close();
            // Navigate to request if available
            if (notification.request_id) {
                window.location.href = `/app/request?id=${notification.request_id}`;
            }
        };

        // Auto-close after 5 seconds
        setTimeout(() => browserNotif.close(), 5000);
    } catch (err) {
        console.error('Error showing browser notification:', err);
    }
}

// ============================================================================
// Hook
// ============================================================================

export function useNotifications() {
    const { user } = useAuth();
    const [notifications, setNotifications] = useState<Notification[]>([]);
    const [unreadCount, setUnreadCount] = useState(0);
    const [loading, setLoading] = useState(true);
    const [browserPermission, setBrowserPermission] = useState<'granted' | 'denied' | 'default' | 'unsupported'>('default');

    // Check browser permission on mount
    useEffect(() => {
        setBrowserPermission(getBrowserPermissionStatus());
    }, []);

    // Request browser notification permission
    const requestPermission = useCallback(async () => {
        const granted = await requestBrowserPermission();
        setBrowserPermission(granted ? 'granted' : 'denied');
        return granted;
    }, []);

    // Fetch notifications
    const fetchNotifications = useCallback(async () => {
        if (!user) {
            setNotifications([]);
            setUnreadCount(0);
            setLoading(false);
            return;
        }

        try {
            const supabase = getSupabaseClient();

            const { data, error } = await supabase
                .from('notifications')
                .select('*')
                .eq('user_id', user.id)
                .order('created_at', { ascending: false })
                .limit(50);

            if (error) throw error;

            const notifs = data || [];
            setNotifications(notifs);
            setUnreadCount(notifs.filter(n => !n.is_read).length);
        } catch (err) {
            console.error('Error fetching notifications:', err);
        } finally {
            setLoading(false);
        }
    }, [user]);

    // Mark notification as read
    const markAsRead = useCallback(async (notificationId: string) => {
        if (!user) return;

        try {
            const supabase = getSupabaseClient();

            const { error } = await supabase
                .from('notifications')
                .update({ is_read: true })
                .eq('id', notificationId)
                .eq('user_id', user.id);

            if (error) throw error;

            setNotifications(prev =>
                prev.map(n => n.id === notificationId ? { ...n, is_read: true } : n)
            );
            setUnreadCount(prev => Math.max(0, prev - 1));
        } catch (err) {
            console.error('Error marking notification as read:', err);
        }
    }, [user]);

    // Mark all as read
    const markAllAsRead = useCallback(async () => {
        if (!user) return;

        try {
            const supabase = getSupabaseClient();

            const { error } = await supabase
                .from('notifications')
                .update({ is_read: true })
                .eq('user_id', user.id)
                .eq('is_read', false);

            if (error) throw error;

            setNotifications(prev => prev.map(n => ({ ...n, is_read: true })));
            setUnreadCount(0);
        } catch (err) {
            console.error('Error marking all notifications as read:', err);
        }
    }, [user]);

    // Initial fetch and subscription
    useEffect(() => {
        fetchNotifications();

        if (!user) return;

        // Set up real-time subscription for new notifications
        const supabase = getSupabaseClient();
        const channel = supabase
            .channel('notifications')
            .on(
                'postgres_changes',
                {
                    event: 'INSERT',
                    schema: 'public',
                    table: 'notifications',
                    filter: `user_id=eq.${user.id}`,
                },
                (payload) => {
                    const newNotif = payload.new as Notification;
                    setNotifications(prev => [newNotif, ...prev]);
                    setUnreadCount(prev => prev + 1);

                    // Show browser notification for real-time alerts
                    showBrowserNotification(newNotif);
                }
            )
            .subscribe();

        return () => {
            supabase.removeChannel(channel);
        };
    }, [user, fetchNotifications]);

    return {
        notifications,
        unreadCount,
        loading,
        markAsRead,
        markAllAsRead,
        refetch: fetchNotifications,
        // Browser notification helpers
        browserPermission,
        requestPermission,
    };
}

