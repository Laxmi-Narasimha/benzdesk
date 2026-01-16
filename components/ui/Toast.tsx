// ============================================================================
// Toast Notification System
// Non-blocking notifications with auto-dismiss
// ============================================================================

'use client';

import React, { createContext, useContext, useState, useCallback } from 'react';
import { clsx } from 'clsx';
import { createPortal } from 'react-dom';
import { X, CheckCircle, AlertCircle, AlertTriangle, Info } from 'lucide-react';

// ============================================================================
// Types
// ============================================================================

export type ToastType = 'success' | 'error' | 'warning' | 'info';

export interface Toast {
    id: string;
    type: ToastType;
    title: string;
    message?: string;
    duration?: number;
}

interface ToastContextValue {
    toasts: Toast[];
    addToast: (toast: Omit<Toast, 'id'>) => void;
    removeToast: (id: string) => void;
    success: (title: string, message?: string) => void;
    error: (title: string, message?: string) => void;
    warning: (title: string, message?: string) => void;
    info: (title: string, message?: string) => void;
}

// ============================================================================
// Context
// ============================================================================

const ToastContext = createContext<ToastContextValue | undefined>(undefined);

// ============================================================================
// Toast Provider
// ============================================================================

export function ToastProvider({ children }: { children: React.ReactNode }) {
    const [toasts, setToasts] = useState<Toast[]>([]);

    const removeToast = useCallback((id: string) => {
        setToasts((prev) => prev.filter((t) => t.id !== id));
    }, []);

    const addToast = useCallback(
        (toast: Omit<Toast, 'id'>) => {
            const id = Math.random().toString(36).substring(2, 9);
            const duration = toast.duration ?? 5000;

            setToasts((prev) => [...prev, { ...toast, id }]);

            if (duration > 0) {
                setTimeout(() => removeToast(id), duration);
            }
        },
        [removeToast]
    );

    const success = useCallback(
        (title: string, message?: string) => {
            addToast({ type: 'success', title, message });
        },
        [addToast]
    );

    const error = useCallback(
        (title: string, message?: string) => {
            addToast({ type: 'error', title, message, duration: 8000 });
        },
        [addToast]
    );

    const warning = useCallback(
        (title: string, message?: string) => {
            addToast({ type: 'warning', title, message });
        },
        [addToast]
    );

    const info = useCallback(
        (title: string, message?: string) => {
            addToast({ type: 'info', title, message });
        },
        [addToast]
    );

    return (
        <ToastContext.Provider
            value={{ toasts, addToast, removeToast, success, error, warning, info }}
        >
            {children}
            <ToastContainer toasts={toasts} removeToast={removeToast} />
        </ToastContext.Provider>
    );
}

// ============================================================================
// Toast Hook
// ============================================================================

export function useToast(): ToastContextValue {
    const context = useContext(ToastContext);

    if (!context) {
        throw new Error('useToast must be used within a ToastProvider');
    }

    return context;
}

// ============================================================================
// Toast Container (Portal)
// ============================================================================

function ToastContainer({
    toasts,
    removeToast,
}: {
    toasts: Toast[];
    removeToast: (id: string) => void;
}) {
    if (typeof window === 'undefined') return null;

    return createPortal(
        <div className="fixed bottom-4 right-4 z-50 flex flex-col gap-3 max-w-md w-full pointer-events-none">
            {toasts.map((toast) => (
                <ToastItem key={toast.id} toast={toast} onClose={() => removeToast(toast.id)} />
            ))}
        </div>,
        document.body
    );
}

// ============================================================================
// Toast Item
// ============================================================================

const icons: Record<ToastType, React.ReactNode> = {
    success: <CheckCircle className="w-5 h-5 text-green-400" />,
    error: <AlertCircle className="w-5 h-5 text-red-400" />,
    warning: <AlertTriangle className="w-5 h-5 text-amber-400" />,
    info: <Info className="w-5 h-5 text-blue-400" />,
};

const borderColors: Record<ToastType, string> = {
    success: 'border-l-green-500',
    error: 'border-l-red-500',
    warning: 'border-l-amber-500',
    info: 'border-l-blue-500',
};

function ToastItem({ toast, onClose }: { toast: Toast; onClose: () => void }) {
    return (
        <div
            className={clsx(
                'pointer-events-auto w-full',
                'rounded-xl bg-dark-800/95 backdrop-blur-xl',
                'border border-dark-700/50 border-l-4',
                'shadow-glass animate-slide-up',
                'p-4 flex items-start gap-3',
                borderColors[toast.type]
            )}
        >
            {/* Icon */}
            <div className="flex-shrink-0 mt-0.5">{icons[toast.type]}</div>

            {/* Content */}
            <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-dark-50">{toast.title}</p>
                {toast.message && (
                    <p className="text-sm text-dark-400 mt-1">{toast.message}</p>
                )}
            </div>

            {/* Close button */}
            <button
                onClick={onClose}
                className="flex-shrink-0 p-1 rounded-lg text-dark-400 hover:text-dark-100 hover:bg-dark-700/50 transition-colors"
            >
                <X className="w-4 h-4" />
            </button>
        </div>
    );
}

export default ToastProvider;
