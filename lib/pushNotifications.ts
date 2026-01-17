// ============================================================================
// Push Notifications Helper
// Handles: Service Worker registration, Push subscription, Permission requests
// ============================================================================

'use client';

import { getSupabaseClient } from './supabaseClient';

// VAPID public key - will be generated and set in environment
const VAPID_PUBLIC_KEY = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY || '';

// ============================================================================
// Service Worker Registration
// ============================================================================

export async function registerServiceWorker(): Promise<ServiceWorkerRegistration | null> {
    if (typeof window === 'undefined' || !('serviceWorker' in navigator)) {
        console.log('[Push] Service workers not supported');
        return null;
    }

    try {
        const registration = await navigator.serviceWorker.register('/sw.js', {
            scope: '/',
        });
        console.log('[Push] Service worker registered:', registration.scope);
        return registration;
    } catch (error) {
        console.error('[Push] Service worker registration failed:', error);
        return null;
    }
}

// ============================================================================
// Notification Permission
// ============================================================================

export function getNotificationPermission(): NotificationPermission | 'unsupported' {
    if (typeof window === 'undefined' || !('Notification' in window)) {
        return 'unsupported';
    }
    return Notification.permission;
}

export async function requestNotificationPermission(): Promise<NotificationPermission | 'unsupported'> {
    if (typeof window === 'undefined' || !('Notification' in window)) {
        return 'unsupported';
    }

    try {
        const permission = await Notification.requestPermission();
        console.log('[Push] Permission result:', permission);
        return permission;
    } catch (error) {
        console.error('[Push] Permission request failed:', error);
        return 'denied';
    }
}

// ============================================================================
// Push Subscription
// ============================================================================

function urlBase64ToUint8Array(base64String: string): Uint8Array {
    const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
    const base64 = (base64String + padding)
        .replace(/-/g, '+')
        .replace(/_/g, '/');

    const rawData = window.atob(base64);
    const outputArray = new Uint8Array(rawData.length);

    for (let i = 0; i < rawData.length; ++i) {
        outputArray[i] = rawData.charCodeAt(i);
    }
    return outputArray;
}

export async function subscribeToPush(userId: string): Promise<{ success: boolean; error?: string }> {
    if (!VAPID_PUBLIC_KEY) {
        console.warn('[Push] VAPID public key not configured');
        return { success: false, error: 'Push notifications not configured' };
    }

    try {
        const registration = await registerServiceWorker();
        if (!registration) {
            return { success: false, error: 'Service worker not available' };
        }

        // Check if already subscribed
        let subscription = await registration.pushManager.getSubscription();

        if (!subscription) {
            // Create new subscription
            subscription = await registration.pushManager.subscribe({
                userVisibleOnly: true,
                applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY) as BufferSource,
            });
            console.log('[Push] New subscription created');
        }

        // Save subscription to database
        const subscriptionJson = subscription.toJSON();
        const supabase = getSupabaseClient();

        const { error } = await supabase.from('push_subscriptions').upsert({
            user_id: userId,
            endpoint: subscriptionJson.endpoint,
            p256dh: subscriptionJson.keys?.p256dh || '',
            auth: subscriptionJson.keys?.auth || '',
        }, {
            onConflict: 'user_id,endpoint',
        });

        if (error) {
            console.error('[Push] Failed to save subscription:', error);
            return { success: false, error: 'Failed to save subscription' };
        }

        console.log('[Push] Subscription saved successfully');
        return { success: true };
    } catch (error) {
        console.error('[Push] Subscription failed:', error);
        return { success: false, error: 'Failed to subscribe to notifications' };
    }
}

export async function unsubscribeFromPush(userId: string): Promise<{ success: boolean; error?: string }> {
    try {
        const registration = await navigator.serviceWorker.ready;
        const subscription = await registration.pushManager.getSubscription();

        if (subscription) {
            await subscription.unsubscribe();
        }

        // Remove from database
        const supabase = getSupabaseClient();
        await supabase.from('push_subscriptions').delete().eq('user_id', userId);

        console.log('[Push] Unsubscribed successfully');
        return { success: true };
    } catch (error) {
        console.error('[Push] Unsubscribe failed:', error);
        return { success: false, error: 'Failed to unsubscribe' };
    }
}

// ============================================================================
// Check Push Support
// ============================================================================

export function isPushSupported(): boolean {
    return (
        typeof window !== 'undefined' &&
        'serviceWorker' in navigator &&
        'PushManager' in window &&
        'Notification' in window
    );
}
