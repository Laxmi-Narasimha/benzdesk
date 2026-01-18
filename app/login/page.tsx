// ============================================================================
// Login Page
// Email magic link first, password as secondary option, with Open Email button
// ============================================================================

'use client';

import React, { useState, useEffect } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { Loader2, Mail, Lock, ArrowLeft, CheckCircle, ExternalLink, KeyRound } from 'lucide-react';
import { useAuth } from '@/lib/AuthContext';
import { useToast } from '@/components/ui';

// ============================================================================
// Email Provider Detection
// ============================================================================

function getEmailProvider(email: string): { name: string; url: string } | null {
    const domain = email.split('@')[1]?.toLowerCase();

    const providers: Record<string, { name: string; url: string }> = {
        'gmail.com': { name: 'Gmail', url: 'https://mail.google.com' },
        'googlemail.com': { name: 'Gmail', url: 'https://mail.google.com' },
        'outlook.com': { name: 'Outlook', url: 'https://outlook.live.com' },
        'hotmail.com': { name: 'Outlook', url: 'https://outlook.live.com' },
        'live.com': { name: 'Outlook', url: 'https://outlook.live.com' },
        'yahoo.com': { name: 'Yahoo Mail', url: 'https://mail.yahoo.com' },
        'icloud.com': { name: 'iCloud Mail', url: 'https://www.icloud.com/mail' },
        'me.com': { name: 'iCloud Mail', url: 'https://www.icloud.com/mail' },
        'protonmail.com': { name: 'ProtonMail', url: 'https://mail.proton.me' },
        'proton.me': { name: 'ProtonMail', url: 'https://mail.proton.me' },
    };

    return providers[domain] || null;
}

// ============================================================================
// Login Page Component
// ============================================================================

export default function LoginPage() {
    const router = useRouter();
    const searchParams = useSearchParams();
    const redirectTo = searchParams.get('redirect') || '/';
    const { user, loading: authLoading, sendOtp, loginWithPassword } = useAuth();
    const { success, error: showError } = useToast();

    // Steps: email, password, link_sent
    const [step, setStep] = useState<'email' | 'password' | 'link_sent'>('email');
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [isLoading, setIsLoading] = useState(false);
    const [usePassword, setUsePassword] = useState(false); // Default to email link

    useEffect(() => {
        if (!authLoading && user) {
            // Redirect to original destination or home
            router.replace(redirectTo);
        }
    }, [user, authLoading, router, redirectTo]);

    const handleEmailSubmit = async (e: React.FormEvent) => {
        e.preventDefault();

        if (!email.trim()) {
            showError('Error', 'Please enter your email');
            return;
        }

        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
            showError('Error', 'Please enter a valid email address');
            return;
        }

        if (usePassword) {
            setStep('password');
        } else {
            // Send magic link
            setIsLoading(true);
            try {
                await sendOtp(email);
                success('Link Sent', 'Check your email for the sign-in link');
                setStep('link_sent');
            } finally {
                setIsLoading(false);
            }
        }
    };

    const handlePasswordLogin = async (e: React.FormEvent) => {
        e.preventDefault();

        if (!password.trim()) {
            showError('Error', 'Please enter your password');
            return;
        }

        setIsLoading(true);

        try {
            const { success: verified, error } = await loginWithPassword(email, password);

            if (verified) {
                success('Welcome', 'Signed in successfully');
                router.replace(redirectTo);
            } else {
                showError('Error', error || 'Invalid credentials');
            }
        } finally {
            setIsLoading(false);
        }
    };

    const handleResendLink = async () => {
        setIsLoading(true);
        try {
            await sendOtp(email);
            success('Link Resent', 'We sent another link to your email');
        } finally {
            setIsLoading(false);
        }
    };

    const openEmailClient = () => {
        const provider = getEmailProvider(email);
        if (provider) {
            window.open(provider.url, '_blank');
        }
    };

    const emailProvider = getEmailProvider(email);

    if (authLoading) {
        return (
            <div className="min-h-screen flex items-center justify-center bg-gray-50">
                <Loader2 className="w-5 h-5 animate-spin text-primary-500" />
            </div>
        );
    }

    return (
        <div className="min-h-screen flex items-center justify-center p-6 bg-gradient-to-br from-gray-50 to-gray-100">
            <div className="w-full max-w-sm">
                {/* Header */}
                <div className="text-center mb-8">
                    <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-primary-500 to-primary-600 flex items-center justify-center mx-auto mb-4 shadow-lg shadow-primary-500/25">
                        <span className="text-white font-bold text-xl">B</span>
                    </div>
                    <h1 className="text-2xl font-bold text-gray-900">
                        BenzDesk
                    </h1>
                    <p className="text-sm mt-1 text-gray-500">
                        Accounts Request Portal
                    </p>
                </div>

                {/* Form Card */}
                <div className="bg-white rounded-2xl shadow-xl shadow-gray-200/50 border border-gray-200 overflow-hidden">

                    {/* Email Step - Magic Link Primary */}
                    {step === 'email' && (
                        <form onSubmit={handleEmailSubmit} className="p-6 space-y-5">
                            {/* Mode indicator */}
                            <div className="flex items-center gap-2 text-sm text-gray-500 pb-4 border-b border-gray-100">
                                {usePassword ? (
                                    <>
                                        <Lock className="w-4 h-4" />
                                        <span>Sign in with password</span>
                                    </>
                                ) : (
                                    <>
                                        <Mail className="w-4 h-4 text-primary-500" />
                                        <span className="text-primary-600 font-medium">Sign in with email link</span>
                                        <span className="ml-auto text-xs bg-green-100 text-green-700 px-2 py-0.5 rounded-full">Recommended</span>
                                    </>
                                )}
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-gray-700 mb-2">
                                    Email Address
                                </label>
                                <input
                                    type="email"
                                    placeholder="you@benz-packaging.com"
                                    value={email}
                                    onChange={(e) => setEmail(e.target.value)}
                                    className="w-full px-4 py-3 bg-gray-50 border border-gray-200 rounded-xl text-gray-900 text-sm placeholder-gray-400 focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 focus:outline-none transition-all"
                                    autoFocus
                                    disabled={isLoading}
                                />
                            </div>

                            <button
                                type="submit"
                                className="w-full py-3.5 bg-primary-500 text-white font-semibold text-sm rounded-xl hover:bg-primary-600 transition-colors disabled:opacity-50 shadow-lg shadow-primary-500/25"
                                disabled={isLoading}
                            >
                                {isLoading ? (
                                    <Loader2 className="w-4 h-4 animate-spin mx-auto" />
                                ) : usePassword ? (
                                    'Continue'
                                ) : (
                                    'Send Sign-in Link'
                                )}
                            </button>

                            {/* Toggle button */}
                            <button
                                type="button"
                                onClick={() => setUsePassword(!usePassword)}
                                className="w-full flex items-center justify-center gap-2 py-2 text-sm text-gray-500 hover:text-gray-700 transition-colors"
                            >
                                {usePassword ? (
                                    <>
                                        <Mail className="w-4 h-4" />
                                        Use email link instead
                                    </>
                                ) : (
                                    <>
                                        <KeyRound className="w-4 h-4" />
                                        Use password instead
                                    </>
                                )}
                            </button>
                        </form>
                    )}

                    {/* Password Step */}
                    {step === 'password' && (
                        <form onSubmit={handlePasswordLogin} className="p-6 space-y-5">
                            <div className="text-center text-sm text-gray-500 pb-4 border-b border-gray-100">
                                <p className="text-gray-400 text-xs">Signing in as</p>
                                <p className="text-gray-900 font-medium mt-1">{email}</p>
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-gray-700 mb-2">
                                    Password
                                </label>
                                <input
                                    type="password"
                                    placeholder="Enter your password"
                                    value={password}
                                    onChange={(e) => setPassword(e.target.value)}
                                    className="w-full px-4 py-3 bg-gray-50 border border-gray-200 rounded-xl text-gray-900 text-sm placeholder-gray-400 focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 focus:outline-none transition-all"
                                    autoFocus
                                    disabled={isLoading}
                                />
                            </div>

                            <button
                                type="submit"
                                className="w-full py-3.5 bg-primary-500 text-white font-semibold text-sm rounded-xl hover:bg-primary-600 transition-colors disabled:opacity-50 shadow-lg shadow-primary-500/25"
                                disabled={isLoading || !password}
                            >
                                {isLoading ? (
                                    <Loader2 className="w-4 h-4 animate-spin mx-auto" />
                                ) : (
                                    'Sign In'
                                )}
                            </button>

                            <button
                                type="button"
                                onClick={() => {
                                    setStep('email');
                                    setPassword('');
                                }}
                                className="w-full flex items-center justify-center gap-2 text-sm text-gray-500 hover:text-gray-700 transition-colors"
                            >
                                <ArrowLeft className="w-4 h-4" />
                                Back
                            </button>
                        </form>
                    )}

                    {/* Link Sent Step */}
                    {step === 'link_sent' && (
                        <div className="p-6 space-y-6 text-center">
                            {/* Success Icon */}
                            <div className="flex justify-center">
                                <div className="w-20 h-20 rounded-full bg-green-100 flex items-center justify-center">
                                    <CheckCircle className="w-10 h-10 text-green-500" />
                                </div>
                            </div>

                            {/* Message */}
                            <div>
                                <h2 className="text-xl font-bold text-gray-900 mb-2">
                                    Check your inbox
                                </h2>
                                <p className="text-sm text-gray-500">
                                    We sent a sign-in link to
                                </p>
                                <p className="text-sm text-gray-900 font-semibold mt-1">
                                    {email}
                                </p>
                            </div>

                            {/* Open Email Button */}
                            {emailProvider && (
                                <button
                                    type="button"
                                    onClick={openEmailClient}
                                    className="w-full py-3.5 bg-primary-500 text-white font-semibold text-sm rounded-xl hover:bg-primary-600 transition-colors shadow-lg shadow-primary-500/25 flex items-center justify-center gap-2"
                                >
                                    <ExternalLink className="w-4 h-4" />
                                    Open {emailProvider.name}
                                </button>
                            )}

                            {/* Info */}
                            <div className="text-xs text-gray-400 pt-4 border-t border-gray-100">
                                <p>Click the link in the email to sign in.</p>
                                <p className="mt-1">The link expires in 1 hour.</p>
                            </div>

                            {/* Action buttons */}
                            <div className="flex flex-col gap-2 pt-2">
                                <button
                                    type="button"
                                    onClick={handleResendLink}
                                    disabled={isLoading}
                                    className="w-full py-2.5 bg-gray-100 text-gray-700 font-medium text-sm rounded-xl hover:bg-gray-200 transition-colors disabled:opacity-50"
                                >
                                    {isLoading ? (
                                        <Loader2 className="w-4 h-4 animate-spin mx-auto" />
                                    ) : (
                                        "Didn't receive it? Resend"
                                    )}
                                </button>

                                <button
                                    type="button"
                                    onClick={() => {
                                        setStep('email');
                                        setUsePassword(false);
                                    }}
                                    className="w-full flex items-center justify-center gap-2 text-sm text-gray-500 hover:text-gray-700 transition-colors py-2"
                                >
                                    <ArrowLeft className="w-4 h-4" />
                                    Try different email
                                </button>
                            </div>
                        </div>
                    )}
                </div>

                {/* Footer */}
                <p className="text-center text-xs text-gray-400 mt-6 px-4">
                    Thank you for using BenzDesk — together, we are building a more streamlined and efficient organisation.
                </p>
            </div>
        </div>
    );
}
