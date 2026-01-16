// ============================================================================
// Button Component
// Premium button with variants, loading states, and micro-animations
// ============================================================================

import React from 'react';
import { clsx } from 'clsx';
import { Loader2 } from 'lucide-react';

// ============================================================================
// Types
// ============================================================================

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
    variant?: 'primary' | 'secondary' | 'ghost' | 'danger' | 'success';
    size?: 'sm' | 'md' | 'lg';
    isLoading?: boolean;
    leftIcon?: React.ReactNode;
    rightIcon?: React.ReactNode;
    fullWidth?: boolean;
}

// ============================================================================
// Component
// ============================================================================

export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
    (
        {
            className,
            variant = 'primary',
            size = 'md',
            isLoading = false,
            leftIcon,
            rightIcon,
            fullWidth = false,
            disabled,
            children,
            ...props
        },
        ref
    ) => {
        const isDisabled = disabled || isLoading;

        return (
            <button
                ref={ref}
                disabled={isDisabled}
                className={clsx(
                    // Base styles
                    'relative inline-flex items-center justify-center font-semibold rounded-xl',
                    'transition-all duration-200 ease-out',
                    'focus:outline-none focus-visible:ring-2 focus-visible:ring-offset-2',
                    'focus-visible:ring-primary-500 focus-visible:ring-offset-dark-950',
                    'disabled:opacity-50 disabled:cursor-not-allowed',
                    'active:scale-[0.98] disabled:active:scale-100',

                    // Size variants
                    {
                        'px-3 py-1.5 text-sm gap-1.5': size === 'sm',
                        'px-5 py-2.5 text-sm gap-2': size === 'md',
                        'px-6 py-3 text-base gap-2.5': size === 'lg',
                    },

                    // Color variants
                    {
                        // Primary - gradient blue
                        'bg-gradient-to-r from-primary-600 to-primary-500 text-white shadow-lg shadow-primary-500/25 hover:shadow-primary-500/40 hover:from-primary-500 hover:to-primary-400':
                            variant === 'primary',

                        // Secondary - dark with border
                        'bg-dark-800 text-dark-100 border border-dark-700 hover:bg-dark-700 hover:border-dark-600':
                            variant === 'secondary',

                        // Ghost - transparent with hover
                        'bg-transparent text-dark-300 hover:bg-dark-800/50 hover:text-dark-50':
                            variant === 'ghost',

                        // Danger - red
                        'bg-gradient-to-r from-red-600 to-red-500 text-white shadow-lg shadow-red-500/25 hover:shadow-red-500/40 hover:from-red-500 hover:to-red-400':
                            variant === 'danger',

                        // Success - green
                        'bg-gradient-to-r from-green-600 to-green-500 text-white shadow-lg shadow-green-500/25 hover:shadow-green-500/40 hover:from-green-500 hover:to-green-400':
                            variant === 'success',
                    },

                    // Full width
                    fullWidth && 'w-full',

                    className
                )}
                {...props}
            >
                {/* Loading spinner */}
                {isLoading && (
                    <Loader2 className="w-4 h-4 animate-spin" />
                )}

                {/* Left icon */}
                {!isLoading && leftIcon && (
                    <span className="flex-shrink-0">{leftIcon}</span>
                )}

                {/* Content */}
                <span className={clsx(isLoading && 'opacity-0')}>{children}</span>

                {/* Right icon */}
                {!isLoading && rightIcon && (
                    <span className="flex-shrink-0">{rightIcon}</span>
                )}

                {/* Shine overlay */}
                {(variant === 'primary' || variant === 'danger' || variant === 'success') && (
                    <span className="absolute inset-0 rounded-xl bg-gradient-to-t from-transparent to-white/10 pointer-events-none" />
                )}
            </button>
        );
    }
);

Button.displayName = 'Button';

export default Button;
