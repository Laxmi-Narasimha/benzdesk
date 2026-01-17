// ============================================================================
// Notification & PWA Settings Component
// Permanent buttons for enabling notifications and installing PWA
// ============================================================================

'use client';

import React, { useState, useEffect } from 'react';
import { Bell, BellOff, Download, Check, Smartphone, RefreshCw } from 'lucide-react';
import { Card, Button } from '@/components/ui';
import { useAuth } from '@/lib/AuthContext';
import {
    isPushSupported,
    getNotificationPermission,
    requestNotificationPermission,
    subscribeToPush,
    registerServiceWorker,
} from '@/lib/pushNotifications';

// ============================================================================
// Notification Settings Section
// ============================================================================

export function NotificationSettings() {
    const { user } = useAuth();
    const [permission, setPermission] = useState<string>('default');
    const [isSubscribed, setIsSubscribed] = useState(false);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [success, setSuccess] = useState<string | null>(null);

    useEffect(() => {
        // Check current permission status
        const perm = getNotificationPermission();
        setPermission(perm);

        // Register service worker on mount
        registerServiceWorker();
    }, []);

    const handleEnableNotifications = async () => {
        if (!user) return;

        setLoading(true);
        setError(null);
        setSuccess(null);

        try {
            // Request permission
            console.log('[Settings] Requesting notification permission...');
            const perm = await requestNotificationPermission();
            console.log('[Settings] Permission result:', perm);
            setPermission(perm);

            if (perm === 'granted') {
                // Subscribe to push
                console.log('[Settings] Subscribing to push notifications...');
                const result = await subscribeToPush(user.id);
                console.log('[Settings] Subscription result:', result);

                if (result.success) {
                    setIsSubscribed(true);
                    setSuccess('Notifications enabled! You will now receive push notifications.');
                } else {
                    setError(result.error || 'Failed to subscribe to notifications');
                }
            } else if (perm === 'denied') {
                setError('Notifications blocked. Please enable them in your browser settings.');
            }
        } catch (err: any) {
            console.error('[Settings] Error enabling notifications:', err);
            setError(err.message || 'Failed to enable notifications');
        } finally {
            setLoading(false);
        }
    };

    const supported = isPushSupported();

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
                <div className="bg-gray-50 p-4 rounded-lg text-gray-600 text-sm">
                    Push notifications are not supported in this browser.
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

                    {/* Enable button */}
                    <Button
                        onClick={handleEnableNotifications}
                        disabled={loading || permission === 'denied'}
                        className="w-full"
                    >
                        {loading ? (
                            <>
                                <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                                Enabling...
                            </>
                        ) : permission === 'granted' ? (
                            <>
                                <Check className="w-4 h-4 mr-2" />
                                Re-subscribe
                            </>
                        ) : (
                            <>
                                <Bell className="w-4 h-4 mr-2" />
                                Enable Notifications
                            </>
                        )}
                    </Button>

                    {permission === 'denied' && (
                        <p className="text-xs text-gray-500">
                            To enable notifications, click the lock icon in your browser&apos;s address bar and allow notifications.
                        </p>
                    )}
                </div>
            )}
        </Card>
    );
}

// ============================================================================
// PWA Install Settings Section
// ============================================================================

let deferredPrompt: any = null;

export function PWAInstallSettings() {
    const [canInstall, setCanInstall] = useState(false);
    const [isInstalled, setIsInstalled] = useState(false);
    const [loading, setLoading] = useState(false);

    useEffect(() => {
        // Check if already installed
        const isStandalone = window.matchMedia('(display-mode: standalone)').matches;
        if (isStandalone) {
            setIsInstalled(true);
            return;
        }

        // Listen for install prompt
        const handleBeforeInstall = (e: Event) => {
            e.preventDefault();
            deferredPrompt = e;
            setCanInstall(true);
        };

        window.addEventListener('beforeinstallprompt', handleBeforeInstall);

        return () => {
            window.removeEventListener('beforeinstallprompt', handleBeforeInstall);
        };
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
                {/* Status indicator */}
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
                            <span className="text-gray-600">App not installed</span>
                        </>
                    )}
                </div>

                {/* Install button */}
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
                        BenzDesk is installed! You can access it from your home screen.
                    </div>
                )}

                {!canInstall && !isInstalled && (
                    <div className="bg-gray-50 p-4 rounded-lg text-gray-600 text-sm space-y-2">
                        <p><strong>To install on your device:</strong></p>
                        <ul className="list-disc list-inside space-y-1 text-xs">
                            <li><strong>Chrome/Edge:</strong> Click the install icon in the address bar</li>
                            <li><strong>iOS Safari:</strong> Tap Share → "Add to Home Screen"</li>
                            <li><strong>Android:</strong> Menu (⋮) → "Install app"</li>
                        </ul>
                    </div>
                )}
            </div>
        </Card>
    );
}
