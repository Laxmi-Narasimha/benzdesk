// ============================================================================
// Modal Component
// Dialog overlay with animations and accessibility
// ============================================================================

'use client';

import React, { useEffect, useCallback } from 'react';
import { createPortal } from 'react-dom';
import { clsx } from 'clsx';
import { X } from 'lucide-react';
import { Button } from './Button';

// ============================================================================
// Types
// ============================================================================

export interface ModalProps {
    isOpen: boolean;
    onClose: () => void;
    title?: string;
    description?: string;
    children: React.ReactNode;
    size?: 'sm' | 'md' | 'lg' | 'xl' | 'full';
    showClose?: boolean;
    closeOnOverlayClick?: boolean;
    closeOnEscape?: boolean;
    footer?: React.ReactNode;
}

// ============================================================================
// Modal Component
// ============================================================================

export function Modal({
    isOpen,
    onClose,
    title,
    description,
    children,
    size = 'md',
    showClose = true,
    closeOnOverlayClick = true,
    closeOnEscape = true,
    footer,
}: ModalProps) {
    // Handle escape key
    const handleEscape = useCallback(
        (e: KeyboardEvent) => {
            if (e.key === 'Escape' && closeOnEscape) {
                onClose();
            }
        },
        [closeOnEscape, onClose]
    );

    // Add/remove escape listener
    useEffect(() => {
        if (isOpen) {
            document.addEventListener('keydown', handleEscape);
            document.body.style.overflow = 'hidden';
        }

        return () => {
            document.removeEventListener('keydown', handleEscape);
            document.body.style.overflow = '';
        };
    }, [isOpen, handleEscape]);

    // Handle overlay click
    const handleOverlayClick = (e: React.MouseEvent) => {
        if (e.target === e.currentTarget && closeOnOverlayClick) {
            onClose();
        }
    };

    if (!isOpen) return null;

    // Portal to body
    return createPortal(
        <div
            role="dialog"
            aria-modal="true"
            aria-labelledby={title ? 'modal-title' : undefined}
            aria-describedby={description ? 'modal-description' : undefined}
            className="fixed inset-0 z-50 flex items-center justify-center p-4"
        >
            {/* Overlay */}
            <div
                onClick={handleOverlayClick}
                className="absolute inset-0 bg-dark-950/80 backdrop-blur-sm animate-fade-in"
            />

            {/* Modal content */}
            <div
                className={clsx(
                    'relative w-full rounded-2xl animate-scale-in',
                    'bg-gradient-to-br from-dark-800/95 to-dark-900/95',
                    'backdrop-blur-xl border border-dark-700/50',
                    'shadow-glass max-h-[90vh] flex flex-col',

                    // Size variants
                    {
                        'max-w-sm': size === 'sm',
                        'max-w-md': size === 'md',
                        'max-w-lg': size === 'lg',
                        'max-w-2xl': size === 'xl',
                        'max-w-none m-4': size === 'full',
                    }
                )}
            >
                {/* Gradient overlay */}
                <div className="absolute inset-0 rounded-2xl bg-gradient-to-br from-white/5 to-transparent pointer-events-none" />

                {/* Header */}
                {(title || showClose) && (
                    <div className="relative flex items-start justify-between p-6 border-b border-dark-700/50">
                        <div>
                            {title && (
                                <h2
                                    id="modal-title"
                                    className="text-lg font-semibold text-dark-50"
                                >
                                    {title}
                                </h2>
                            )}
                            {description && (
                                <p
                                    id="modal-description"
                                    className="text-sm text-dark-400 mt-1"
                                >
                                    {description}
                                </p>
                            )}
                        </div>
                        {showClose && (
                            <button
                                type="button"
                                onClick={onClose}
                                className="p-1.5 rounded-lg text-dark-400 hover:text-dark-100 hover:bg-dark-700/50 transition-colors"
                            >
                                <X className="w-5 h-5" />
                            </button>
                        )}
                    </div>
                )}

                {/* Body */}
                <div className="relative flex-1 overflow-y-auto p-6">
                    {children}
                </div>

                {/* Footer */}
                {footer && (
                    <div className="relative p-4 border-t border-dark-700/50 flex items-center justify-end gap-3 bg-dark-900/50">
                        {footer}
                    </div>
                )}
            </div>
        </div>,
        document.body
    );
}

// ============================================================================
// Confirm Modal
// Pre-configured confirmation dialog
// ============================================================================

export interface ConfirmModalProps {
    isOpen: boolean;
    onClose: () => void;
    onConfirm: () => void;
    title: string;
    message: string;
    confirmText?: string;
    cancelText?: string;
    variant?: 'danger' | 'warning' | 'default';
    isLoading?: boolean;
}

export function ConfirmModal({
    isOpen,
    onClose,
    onConfirm,
    title,
    message,
    confirmText = 'Confirm',
    cancelText = 'Cancel',
    variant = 'default',
    isLoading = false,
}: ConfirmModalProps) {
    return (
        <Modal
            isOpen={isOpen}
            onClose={onClose}
            title={title}
            size="sm"
            closeOnOverlayClick={!isLoading}
            closeOnEscape={!isLoading}
            footer={
                <>
                    <Button
                        variant="secondary"
                        onClick={onClose}
                        disabled={isLoading}
                    >
                        {cancelText}
                    </Button>
                    <Button
                        variant={variant === 'danger' ? 'danger' : 'primary'}
                        onClick={onConfirm}
                        isLoading={isLoading}
                    >
                        {confirmText}
                    </Button>
                </>
            }
        >
            <p className="text-dark-300">{message}</p>
        </Modal>
    );
}

export default Modal;
