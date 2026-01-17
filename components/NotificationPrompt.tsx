// ============================================================================
// Notification Prompt Component
// Shows a prompt to enable push notifications
// ============================================================================

'use client';

import React, { useState, useEffect } from 'react';
import { Bell, X, Check } from 'lucide-react';
import { useAuth } from '@/lib/AuthContext';
import {
    isPushSupported,
    getNotificationPermission,
    requestNotificationPermission,
    subscribeToPush,
    registerServiceWorker,
} from '@/lib/pushNotifications';

export function NotificationPrompt() {
    const { user } = useAuth();
    const [show, setShow] = useState(false);
    const [loading, setLoading] = useState(false);
    const [enabled, setEnabled] = useState(false);

    useEffect(() => {
        // Register service worker on mount
        registerServiceWorker();

        // Check if we should show the prompt
        if (!user || !isPushSupported()) return;

        const permission = getNotificationPermission();
        if (permission === 'granted') {
            setEnabled(true);
            // Re-subscribe in case subscription expired
            subscribeToPush(user.id);
            return;
        }

        // Show prompt if not denied and haven't dismissed before
        const dismissed = localStorage.getItem('notification-prompt-dismissed');
        if (permission !== 'denied' && !dismissed) {
            // Delay showing prompt
            const timer = setTimeout(() => setShow(true), 5000);
            return () => clearTimeout(timer);
        }
    }, [user]);

    const handleEnable = async () => {
        if (!user) return;

        setLoading(true);
        try {
            const permission = await requestNotificationPermission();
            if (permission === 'granted') {
                const result = await subscribeToPush(user.id);
                if (result.success) {
                    setEnabled(true);
                    setShow(false);
                }
            }
        } catch (error) {
            console.error('Failed to enable notifications:', error);
        } finally {
            setLoading(false);
        }
    };

    const handleDismiss = () => {
        localStorage.setItem('notification-prompt-dismissed', 'true');
        setShow(false);
    };

    if (!show || enabled) return null;

    return (
        <div className="fixed bottom-4 right-4 z-50 max-w-sm animate-slide-up">
            <div className="bg-white rounded-xl shadow-xl border border-gray-200 p-4">
                <div className="flex items-start gap-3">
                    <div className="flex-shrink-0 w-10 h-10 bg-primary-100 rounded-full flex items-center justify-center">
                        <Bell className="w-5 h-5 text-primary-600" />
                    </div>
                    <div className="flex-1 min-w-0">
                        <h4 className="text-sm font-semibold text-gray-900">
                            Enable Notifications
                        </h4>
                        <p className="text-xs text-gray-500 mt-1">
                            Get instant alerts when your requests are updated, even when the app is closed.
                        </p>
                        <div className="flex items-center gap-2 mt-3">
                            <button
                                onClick={handleEnable}
                                disabled={loading}
                                className="flex items-center gap-1.5 px-3 py-1.5 bg-primary-500 hover:bg-primary-600 text-white text-xs font-medium rounded-lg transition-colors disabled:opacity-50"
                            >
                                {loading ? (
                                    <span className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                                ) : (
                                    <Check className="w-3 h-3" />
                                )}
                                Enable
                            </button>
                            <button
                                onClick={handleDismiss}
                                className="px-3 py-1.5 text-gray-500 hover:text-gray-700 text-xs font-medium transition-colors"
                            >
                                Not now
                            </button>
                        </div>
                    </div>
                    <button
                        onClick={handleDismiss}
                        className="flex-shrink-0 text-gray-400 hover:text-gray-600 transition-colors"
                    >
                        <X className="w-4 h-4" />
                    </button>
                </div>
            </div>
        </div>
    );
}

// ============================================================================
// iOS Install Prompt
// Shows a banner for iOS users to install the PWA
// ============================================================================

export function IOSInstallPrompt() {
    const [show, setShow] = useState(false);

    useEffect(() => {
        // Check if iOS and not already installed
        const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
        const isStandalone = (window.navigator as any).standalone === true;
        const dismissed = localStorage.getItem('ios-install-dismissed');

        if (isIOS && !isStandalone && !dismissed) {
            const timer = setTimeout(() => setShow(true), 3000);
            return () => clearTimeout(timer);
        }
    }, []);

    const handleDismiss = () => {
        localStorage.setItem('ios-install-dismissed', 'true');
        setShow(false);
    };

    if (!show) return null;

    return (
        <div className="fixed bottom-0 left-0 right-0 z-50 p-4 bg-white border-t border-gray-200 shadow-lg animate-slide-up">
            <div className="flex items-center gap-3 max-w-lg mx-auto">
                <div className="flex-shrink-0 w-12 h-12 bg-primary-500 rounded-xl flex items-center justify-center">
                    <span className="text-white font-bold text-lg">B</span>
                </div>
                <div className="flex-1">
                    <h4 className="text-sm font-semibold text-gray-900">
                        Install BenzDesk
                    </h4>
                    <p className="text-xs text-gray-500 mt-0.5">
                        Tap <span className="inline-flex items-center"><svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12" /></svg></span> then "Add to Home Screen"
                    </p>
                </div>
                <button
                    onClick={handleDismiss}
                    className="flex-shrink-0 text-gray-400 hover:text-gray-600"
                >
                    <X className="w-5 h-5" />
                </button>
            </div>
        </div>
    );
}
