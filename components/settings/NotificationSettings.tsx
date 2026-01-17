// ============================================================================
// Notification & PWA Settings Component
// Permanent buttons for enabling notifications and installing PWA
// Fixed hydration issues by deferring browser API calls to client
// ============================================================================

'use client';

import React, { useState, useEffect, useCallback } from 'react';
import { Bell, BellOff, Download, Check, Smartphone, RefreshCw, AlertTriangle, Send } from 'lucide-react';
import { Card, Button } from '@/components/ui';
import { useAuth } from '@/lib/AuthContext';

// ============================================================================
// Notification Settings Section (Hydration-Safe)
// ============================================================================

export function NotificationSettings() {
    const { user } = useAuth();
    const [mounted, setMounted] = useState(false);
    const [permission, setPermission] = useState<string>('default');
    const [isSubscribed, setIsSubscribed] = useState(false);
    const [loading, setLoading] = useState(false);
    const [testing, setTesting] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [success, setSuccess] = useState<string | null>(null);
    const [supported, setSupported] = useState(false);
    const [debugInfo, setDebugInfo] = useState<string[]>([]);

    // Only run browser checks after mount to avoid hydration mismatch
    useEffect(() => {
        setMounted(true);

        // Check browser support only on client
        const checkSupport = typeof window !== 'undefined' &&
            'serviceWorker' in navigator &&
            'PushManager' in window &&
            'Notification' in window;
        setSupported(checkSupport);

        if (checkSupport) {
            setPermission(Notification.permission);
        }
    }, []);

    const addDebug = useCallback((msg: string) => {
        const timestamp = new Date().toLocaleTimeString();
        console.log(`[NotificationSettings] ${msg}`);
        setDebugInfo(prev => [...prev.slice(-9), `${timestamp}: ${msg}`]);
    }, []);

    const handleEnableNotifications = async () => {
        if (!user) {
            setError('Please login first');
            return;
        }

        setLoading(true);
        setError(null);
        setSuccess(null);
        setDebugInfo([]);

        try {
            addDebug('Starting notification setup...');

            // Step 1: Request permission
            addDebug('Requesting notification permission...');
            const perm = await Notification.requestPermission();
            addDebug(`Permission result: ${perm}`);
            setPermission(perm);

            if (perm !== 'granted') {
                setError(perm === 'denied'
                    ? 'Notifications blocked. Enable them in browser settings (click lock icon).'
                    : 'Permission not granted');
                return;
            }

            // Step 2: Register service worker
            addDebug('Registering service worker...');
            const registration = await navigator.serviceWorker.register('/sw.js');
            addDebug(`SW registered: ${registration.scope}`);

            // Step 3: Wait for service worker to be ready
            addDebug('Waiting for SW to be ready...');
            const readySW = await navigator.serviceWorker.ready;
            addDebug(`SW ready: ${readySW.active?.state}`);

            // Step 4: Subscribe to push
            const VAPID_KEY = 'BN68gV5OViKFtES0XgM82WGpZhslNvDrLZTCSZbyUZf-FZR4NRduk6AOzWzbKkBtfSIibZzgsdFVoMMVS8wysmw';
            addDebug('Creating push subscription...');

            // Convert VAPID key
            const urlBase64ToUint8Array = (base64String: string) => {
                const padding = '='.repeat((4 - base64String.length % 4) % 4);
                const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
                const rawData = atob(base64);
                const outputArray = new Uint8Array(rawData.length);
                for (let i = 0; i < rawData.length; ++i) {
                    outputArray[i] = rawData.charCodeAt(i);
                }
                return outputArray;
            };

            let subscription = await readySW.pushManager.getSubscription();
            if (!subscription) {
                subscription = await readySW.pushManager.subscribe({
                    userVisibleOnly: true,
                    applicationServerKey: urlBase64ToUint8Array(VAPID_KEY),
                });
                addDebug('New subscription created');
            } else {
                addDebug('Existing subscription found');
            }
            addDebug(`Endpoint: ${subscription.endpoint.substring(0, 50)}...`);

            // Step 5: Save to database
            addDebug('Saving to database...');
            const { getSupabaseClient } = await import('@/lib/supabaseClient');
            const supabase = getSupabaseClient();

            const subJson = subscription.toJSON();
            const { error: dbError } = await supabase.from('push_subscriptions').upsert({
                user_id: user.id,
                endpoint: subJson.endpoint,
                p256dh: subJson.keys?.p256dh || '',
                auth: subJson.keys?.auth || '',
            }, {
                onConflict: 'user_id,endpoint',
            });

            if (dbError) {
                addDebug(`DB Error: ${dbError.message}`);
                setError(`Failed to save: ${dbError.message}`);
                return;
            }

            addDebug('✅ Subscription saved successfully!');
            setIsSubscribed(true);
            setSuccess('Notifications enabled! Click "Test Notification" to verify.');

        } catch (err: any) {
            addDebug(`❌ Error: ${err.message}`);
            setError(err.message || 'Failed to enable notifications');
        } finally {
            setLoading(false);
        }
    };

    const handleTestNotification = async () => {
        if (!user) return;

        setTesting(true);
        setError(null);
        addDebug('Sending test notification...');

        try {
            const { getSupabaseClient } = await import('@/lib/supabaseClient');
            const supabase = getSupabaseClient();

            const { data, error: funcError } = await supabase.functions.invoke('send-push', {
                body: {
                    user_id: user.id,
                    title: '🔔 Test Notification',
                    body: 'If you see this, push notifications are working!',
                    url: '/app/help',
                    tag: 'test-notification',
                },
            });

            addDebug(`Edge function response: ${JSON.stringify(data)}`);

            if (funcError) {
                addDebug(`❌ Function error: ${funcError.message}`);
                setError(`Test failed: ${funcError.message}`);
            } else if (data?.success) {
                addDebug(`✅ Test sent to ${data.sent} device(s)`);
                setSuccess(`Test sent! Check for notification. (${data.sent} device(s))`);
            } else {
                addDebug(`⚠️ No devices found or send failed`);
                setError(data?.message || 'No subscriptions found. Try re-subscribing.');
            }
        } catch (err: any) {
            addDebug(`❌ Error: ${err.message}`);
            setError(err.message);
        } finally {
            setTesting(false);
        }
    };

    // Don't render until mounted (prevents hydration mismatch)
    if (!mounted) {
        return (
            <Card className="p-6">
                <div className="flex items-center gap-3 mb-4">
                    <div className="p-2 bg-blue-100 rounded-lg">
                        <Bell className="w-6 h-6 text-blue-600" />
                    </div>
                    <div>
                        <h3 className="font-semibold text-gray-900">Push Notifications</h3>
                        <p className="text-sm text-gray-500">Loading...</p>
                    </div>
                </div>
            </Card>
        );
    }

    return (
        <Card className="p-6">
            <div className="flex items-center gap-3 mb-4">
                <div className="p-2 bg-blue-100 rounded-lg">
                    <Bell className="w-6 h-6 text-blue-600" />
                </div>
                <div>
                    <h3 className="font-semibold text-gray-900">Push Notifications</h3>
                    <p className="text-sm text-gray-500">Get notified when your requests are updated</p>
                </div>
            </div>

            {!supported ? (
                <div className="bg-yellow-50 p-4 rounded-lg text-yellow-700 text-sm flex items-start gap-2">
                    <AlertTriangle className="w-4 h-4 mt-0.5 shrink-0" />
                    <span>Push notifications are not supported in this browser. Try Chrome or Edge.</span>
                </div>
            ) : (
                <div className="space-y-4">
                    {/* Status indicator */}
                    <div className="flex items-center gap-2 text-sm">
                        {permission === 'granted' ? (
                            <>
                                <Check className="w-4 h-4 text-green-600" />
                                <span className="text-green-700 font-medium">Notifications enabled</span>
                            </>
                        ) : permission === 'denied' ? (
                            <>
                                <BellOff className="w-4 h-4 text-red-600" />
                                <span className="text-red-700 font-medium">Notifications blocked</span>
                            </>
                        ) : (
                            <>
                                <Bell className="w-4 h-4 text-gray-400" />
                                <span className="text-gray-600">Notifications not enabled</span>
                            </>
                        )}
                    </div>

                    {/* Error/Success messages */}
                    {error && (
                        <div className="bg-red-50 text-red-700 p-3 rounded-lg text-sm">
                            {error}
                        </div>
                    )}
                    {success && (
                        <div className="bg-green-50 text-green-700 p-3 rounded-lg text-sm">
                            {success}
                        </div>
                    )}

                    {/* Debug info */}
                    {debugInfo.length > 0 && (
                        <div className="bg-gray-800 text-green-400 p-3 rounded-lg text-xs font-mono max-h-32 overflow-y-auto">
                            {debugInfo.map((line, i) => (
                                <div key={i}>{line}</div>
                            ))}
                        </div>
                    )}

                    {/* Action buttons */}
                    <div className="flex gap-2">
                        <Button
                            onClick={handleEnableNotifications}
                            disabled={loading || permission === 'denied'}
                            className="flex-1"
                        >
                            {loading ? (
                                <>
                                    <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                                    Enabling...
                                </>
                            ) : permission === 'granted' ? (
                                <>
                                    <RefreshCw className="w-4 h-4 mr-2" />
                                    Re-subscribe
                                </>
                            ) : (
                                <>
                                    <Bell className="w-4 h-4 mr-2" />
                                    Enable
                                </>
                            )}
                        </Button>

                        {permission === 'granted' && (
                            <Button
                                onClick={handleTestNotification}
                                disabled={testing}
                                variant="secondary"
                                className="flex-1"
                            >
                                {testing ? (
                                    <>
                                        <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                                        Sending...
                                    </>
                                ) : (
                                    <>
                                        <Send className="w-4 h-4 mr-2" />
                                        Test
                                    </>
                                )}
                            </Button>
                        )}
                    </div>

                    {permission === 'denied' && (
                        <p className="text-xs text-gray-500">
                            To enable: Click lock icon in address bar → Site Settings → Allow Notifications
                        </p>
                    )}
                </div>
            )}
        </Card>
    );
}

// ============================================================================
// PWA Install Settings Section (Hydration-Safe)
// ============================================================================

let deferredPrompt: any = null;

export function PWAInstallSettings() {
    const [mounted, setMounted] = useState(false);
    const [canInstall, setCanInstall] = useState(false);
    const [isInstalled, setIsInstalled] = useState(false);
    const [loading, setLoading] = useState(false);

    useEffect(() => {
        setMounted(true);

        // Check if already installed (only on client)
        if (typeof window !== 'undefined') {
            const isStandalone = window.matchMedia('(display-mode: standalone)').matches;
            if (isStandalone) {
                setIsInstalled(true);
                return;
            }

            const handleBeforeInstall = (e: Event) => {
                e.preventDefault();
                deferredPrompt = e;
                setCanInstall(true);
            };

            window.addEventListener('beforeinstallprompt', handleBeforeInstall);
            return () => window.removeEventListener('beforeinstallprompt', handleBeforeInstall);
        }
    }, []);

    const handleInstall = async () => {
        if (!deferredPrompt) return;

        setLoading(true);
        try {
            deferredPrompt.prompt();
            const { outcome } = await deferredPrompt.userChoice;
            if (outcome === 'accepted') {
                setIsInstalled(true);
                setCanInstall(false);
            }
        } catch (err) {
            console.error('[PWA] Install error:', err);
        } finally {
            deferredPrompt = null;
            setLoading(false);
        }
    };

    if (!mounted) {
        return (
            <Card className="p-6">
                <div className="flex items-center gap-3 mb-4">
                    <div className="p-2 bg-purple-100 rounded-lg">
                        <Smartphone className="w-6 h-6 text-purple-600" />
                    </div>
                    <div>
                        <h3 className="font-semibold text-gray-900">Install App</h3>
                        <p className="text-sm text-gray-500">Loading...</p>
                    </div>
                </div>
            </Card>
        );
    }

    return (
        <Card className="p-6">
            <div className="flex items-center gap-3 mb-4">
                <div className="p-2 bg-purple-100 rounded-lg">
                    <Smartphone className="w-6 h-6 text-purple-600" />
                </div>
                <div>
                    <h3 className="font-semibold text-gray-900">Install App</h3>
                    <p className="text-sm text-gray-500">Add BenzDesk to your home screen</p>
                </div>
            </div>

            <div className="space-y-4">
                <div className="flex items-center gap-2 text-sm">
                    {isInstalled ? (
                        <>
                            <Check className="w-4 h-4 text-green-600" />
                            <span className="text-green-700 font-medium">App installed</span>
                        </>
                    ) : canInstall ? (
                        <>
                            <Download className="w-4 h-4 text-purple-600" />
                            <span className="text-purple-700 font-medium">Ready to install</span>
                        </>
                    ) : (
                        <>
                            <Smartphone className="w-4 h-4 text-gray-400" />
                            <span className="text-gray-600">Use instructions below</span>
                        </>
                    )}
                </div>

                {canInstall && !isInstalled && (
                    <Button
                        onClick={handleInstall}
                        disabled={loading}
                        variant="secondary"
                        className="w-full"
                    >
                        {loading ? (
                            <>
                                <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                                Installing...
                            </>
                        ) : (
                            <>
                                <Download className="w-4 h-4 mr-2" />
                                Install BenzDesk
                            </>
                        )}
                    </Button>
                )}

                {isInstalled && (
                    <div className="bg-green-50 text-green-700 p-3 rounded-lg text-sm">
                        BenzDesk is installed! Access it from your home screen.
                    </div>
                )}

                {!canInstall && !isInstalled && (
                    <div className="bg-gray-50 p-3 rounded-lg text-gray-600 text-xs space-y-1">
                        <p><strong>Chrome/Edge:</strong> Click install icon (⊕) in address bar</p>
                        <p><strong>iOS Safari:</strong> Share → Add to Home Screen</p>
                        <p><strong>Android:</strong> Menu (⋮) → Install app</p>
                    </div>
                )}
            </div>
        </Card>
    );
}
