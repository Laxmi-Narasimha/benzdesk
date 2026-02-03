// ============================================================================
// Input Component
// Form input with validation states, icons, and premium styling
// ============================================================================

import React from 'react';
import { clsx } from 'clsx';
import { AlertCircle, CheckCircle, Eye, EyeOff } from 'lucide-react';

// ============================================================================
// Types
// ============================================================================

export interface InputProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'size'> {
    label?: string;
    error?: string;
    hint?: string;
    success?: boolean;
    leftIcon?: React.ReactNode;
    rightIcon?: React.ReactNode;
    size?: 'sm' | 'md' | 'lg';
    fullWidth?: boolean;
}

// ============================================================================
// Component
// ============================================================================

export const Input = React.forwardRef<HTMLInputElement, InputProps>(
    (
        {
            className,
            label,
            error,
            hint,
            success,
            leftIcon,
            rightIcon,
            size = 'md',
            fullWidth = true,
            type = 'text',
            id,
            ...props
        },
        ref
    ) => {
        const [showPassword, setShowPassword] = React.useState(false);
        const generatedId = React.useId();
        const inputId = id ?? generatedId;
        const isPassword = type === 'password';
        const inputType = isPassword && showPassword ? 'text' : type;

        return (
            <div className={clsx('space-y-1.5', fullWidth && 'w-full')}>
                {/* Label */}
                {label && (
                    <label
                        htmlFor={inputId}
                        className="block text-sm font-medium text-dark-300"
                    >
                        {label}
                    </label>
                )}

                {/* Input wrapper */}
                <div className="relative">
                    {/* Left icon */}
                    {leftIcon && (
                        <div className="absolute left-3 top-1/2 -translate-y-1/2 text-dark-400 pointer-events-none">
                            {leftIcon}
                        </div>
                    )}

                    {/* Input */}
                    <input
                        ref={ref}
                        id={inputId}
                        type={inputType}
                        className={clsx(
                            // Base styles
                            'w-full rounded-xl bg-dark-800/50 border text-dark-50',
                            'placeholder:text-dark-500',
                            'transition-all duration-200',
                            'focus:outline-none focus:ring-2 focus:ring-offset-0',

                            // Size variants
                            {
                                'px-3 py-2 text-sm': size === 'sm',
                                'px-4 py-3 text-sm': size === 'md',
                                'px-5 py-4 text-base': size === 'lg',
                            },

                            // Icon padding
                            {
                                'pl-10': leftIcon && size === 'sm',
                                'pl-11': leftIcon && size === 'md',
                                'pl-12': leftIcon && size === 'lg',
                                'pr-10': (rightIcon || isPassword) && size === 'sm',
                                'pr-11': (rightIcon || isPassword) && size === 'md',
                                'pr-12': (rightIcon || isPassword) && size === 'lg',
                            },

                            // State styles
                            {
                                'border-dark-700/50 focus:border-primary-500/50 focus:ring-primary-500/20 focus:bg-dark-800/70':
                                    !error && !success,
                                'border-red-500/50 focus:border-red-500 focus:ring-red-500/20':
                                    error,
                                'border-green-500/50 focus:border-green-500 focus:ring-green-500/20':
                                    success && !error,
                            },

                            // Disabled
                            'disabled:opacity-50 disabled:cursor-not-allowed disabled:bg-dark-800/30',

                            className
                        )}
                        {...props}
                    />

                    {/* Right icon / Password toggle / Status icon */}
                    <div className="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-2">
                        {/* Status icons */}
                        {error && (
                            <AlertCircle className="w-4 h-4 text-red-400" />
                        )}
                        {success && !error && (
                            <CheckCircle className="w-4 h-4 text-green-400" />
                        )}

                        {/* Password toggle */}
                        {isPassword && (
                            <button
                                type="button"
                                onClick={() => setShowPassword(!showPassword)}
                                className="text-dark-400 hover:text-dark-200 transition-colors focus:outline-none"
                                tabIndex={-1}
                            >
                                {showPassword ? (
                                    <EyeOff className="w-4 h-4" />
                                ) : (
                                    <Eye className="w-4 h-4" />
                                )}
                            </button>
                        )}

                        {/* Custom right icon */}
                        {rightIcon && !isPassword && !error && !success && (
                            <span className="text-dark-400 pointer-events-none">{rightIcon}</span>
                        )}
                    </div>
                </div>

                {/* Error message */}
                {error && (
                    <p className="text-sm text-red-400 flex items-center gap-1.5">
                        <AlertCircle className="w-3.5 h-3.5 flex-shrink-0" />
                        {error}
                    </p>
                )}

                {/* Hint */}
                {hint && !error && (
                    <p className="text-sm text-dark-500">{hint}</p>
                )}
            </div>
        );
    }
);

Input.displayName = 'Input';

export default Input;

// ============================================================================
// Textarea Component
// ============================================================================

export interface TextareaProps extends React.TextareaHTMLAttributes<HTMLTextAreaElement> {
    label?: string;
    error?: string;
    hint?: string;
    fullWidth?: boolean;
}

export const Textarea = React.forwardRef<HTMLTextAreaElement, TextareaProps>(
    (
        {
            className,
            label,
            error,
            hint,
            fullWidth = true,
            id,
            ...props
        },
        ref
    ) => {
        const generatedId = React.useId();
        const inputId = id ?? generatedId;

        return (
            <div className={clsx('space-y-1.5', fullWidth && 'w-full')}>
                {label && (
                    <label
                        htmlFor={inputId}
                        className="block text-sm font-medium text-dark-300"
                    >
                        {label}
                    </label>
                )}

                <textarea
                    ref={ref}
                    id={inputId}
                    className={clsx(
                        'w-full rounded-xl bg-dark-800/50 border text-dark-50',
                        'placeholder:text-dark-500 resize-none',
                        'px-4 py-3 text-sm min-h-[120px]',
                        'transition-all duration-200',
                        'focus:outline-none focus:ring-2 focus:ring-offset-0',
                        {
                            'border-dark-700/50 focus:border-primary-500/50 focus:ring-primary-500/20 focus:bg-dark-800/70':
                                !error,
                            'border-red-500/50 focus:border-red-500 focus:ring-red-500/20':
                                error,
                        },
                        'disabled:opacity-50 disabled:cursor-not-allowed',
                        className
                    )}
                    {...props}
                />

                {error && (
                    <p className="text-sm text-red-400 flex items-center gap-1.5">
                        <AlertCircle className="w-3.5 h-3.5 flex-shrink-0" />
                        {error}
                    </p>
                )}

                {hint && !error && (
                    <p className="text-sm text-dark-500">{hint}</p>
                )}
            </div>
        );
    }
);

Textarea.displayName = 'Textarea';
