// ============================================================================
// Select Component
// Dropdown select with search, validation, and premium styling
// ============================================================================

import React from 'react';
import { clsx } from 'clsx';
import { ChevronDown, AlertCircle, Check } from 'lucide-react';

// ============================================================================
// Types
// ============================================================================

export interface SelectOption {
    value: string;
    label: string;
    disabled?: boolean;
}

export interface SelectProps extends Omit<React.SelectHTMLAttributes<HTMLSelectElement>, 'size'> {
    label?: string;
    error?: string;
    hint?: string;
    options: SelectOption[];
    placeholder?: string;
    size?: 'sm' | 'md' | 'lg';
    fullWidth?: boolean;
}

// ============================================================================
// Native Select Component
// ============================================================================

export const Select = React.forwardRef<HTMLSelectElement, SelectProps>(
    (
        {
            className,
            label,
            error,
            hint,
            options,
            placeholder,
            size = 'md',
            fullWidth = true,
            id,
            ...props
        },
        ref
    ) => {
        const generatedId = React.useId();
        const selectId = id ?? generatedId;

        return (
            <div className={clsx('space-y-1.5', fullWidth && 'w-full')}>
                {label && (
                    <label
                        htmlFor={selectId}
                        className="block text-sm font-medium text-dark-300"
                    >
                        {label}
                    </label>
                )}

                <div className="relative">
                    <select
                        ref={ref}
                        id={selectId}
                        className={clsx(
                            'w-full appearance-none rounded-xl bg-dark-800/50 border text-dark-50',
                            'cursor-pointer',
                            'transition-all duration-200',
                            'focus:outline-none focus:ring-2 focus:ring-offset-0',

                            // Size variants
                            {
                                'px-3 py-2 text-sm pr-8': size === 'sm',
                                'px-4 py-3 text-sm pr-10': size === 'md',
                                'px-5 py-4 text-base pr-12': size === 'lg',
                            },

                            // State styles
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
                    >
                        {placeholder && (
                            <option value="" disabled>
                                {placeholder}
                            </option>
                        )}
                        {options.map((option) => (
                            <option
                                key={option.value}
                                value={option.value}
                                disabled={option.disabled}
                            >
                                {option.label}
                            </option>
                        ))}
                    </select>

                    {/* Dropdown arrow */}
                    <div className="absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none text-dark-400">
                        <ChevronDown className="w-4 h-4" />
                    </div>
                </div>

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

Select.displayName = 'Select';

export default Select;

// ============================================================================
// Custom Dropdown with Search (for larger option sets)
// ============================================================================

export interface CustomSelectProps {
    label?: string;
    error?: string;
    options: SelectOption[];
    value?: string;
    onChange?: (value: string) => void;
    placeholder?: string;
    searchable?: boolean;
    fullWidth?: boolean;
}

export function CustomSelect({
    label,
    error,
    options,
    value,
    onChange,
    placeholder = 'Select an option',
    searchable = false,
    fullWidth = true,
}: CustomSelectProps) {
    const [isOpen, setIsOpen] = React.useState(false);
    const [search, setSearch] = React.useState('');
    const containerRef = React.useRef<HTMLDivElement>(null);

    const selectedOption = options.find(o => o.value === value);

    const filteredOptions = searchable
        ? options.filter(o =>
            o.label.toLowerCase().includes(search.toLowerCase())
        )
        : options;

    // Close on outside click
    React.useEffect(() => {
        const handleClickOutside = (e: MouseEvent) => {
            if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
                setIsOpen(false);
                setSearch('');
            }
        };

        document.addEventListener('mousedown', handleClickOutside);
        return () => document.removeEventListener('mousedown', handleClickOutside);
    }, []);

    return (
        <div ref={containerRef} className={clsx('space-y-1.5 relative', fullWidth && 'w-full')}>
            {label && (
                <label className="block text-sm font-medium text-dark-300">
                    {label}
                </label>
            )}

            {/* Trigger */}
            <button
                type="button"
                onClick={() => setIsOpen(!isOpen)}
                className={clsx(
                    'w-full flex items-center justify-between',
                    'px-4 py-3 rounded-xl bg-dark-800/50 border text-sm',
                    'transition-all duration-200',
                    'focus:outline-none focus:ring-2 focus:ring-offset-0',
                    {
                        'border-dark-700/50 focus:border-primary-500/50 focus:ring-primary-500/20':
                            !error,
                        'border-red-500/50 focus:border-red-500 focus:ring-red-500/20':
                            error,
                    }
                )}
            >
                <span className={clsx(
                    selectedOption ? 'text-dark-50' : 'text-dark-500'
                )}>
                    {selectedOption?.label || placeholder}
                </span>
                <ChevronDown className={clsx(
                    'w-4 h-4 text-dark-400 transition-transform duration-200',
                    isOpen && 'rotate-180'
                )} />
            </button>

            {/* Dropdown */}
            {isOpen && (
                <div className="absolute z-50 w-full mt-2 rounded-xl glass-card shadow-xl overflow-hidden animate-fade-in">
                    {/* Search input */}
                    {searchable && (
                        <div className="p-2 border-b border-dark-700/50">
                            <input
                                type="text"
                                value={search}
                                onChange={(e) => setSearch(e.target.value)}
                                placeholder="Search..."
                                className="w-full px-3 py-2 text-sm bg-dark-700/50 border border-dark-600/50 rounded-lg text-dark-50 placeholder:text-dark-500 focus:outline-none focus:border-primary-500/50"
                                autoFocus
                            />
                        </div>
                    )}

                    {/* Options */}
                    <div className="max-h-60 overflow-y-auto py-1">
                        {filteredOptions.length === 0 ? (
                            <div className="px-4 py-3 text-sm text-dark-500 text-center">
                                No options found
                            </div>
                        ) : (
                            filteredOptions.map((option) => (
                                <button
                                    key={option.value}
                                    type="button"
                                    onClick={() => {
                                        onChange?.(option.value);
                                        setIsOpen(false);
                                        setSearch('');
                                    }}
                                    disabled={option.disabled}
                                    className={clsx(
                                        'w-full flex items-center justify-between px-4 py-2.5 text-sm',
                                        'transition-colors',
                                        {
                                            'bg-primary-500/10 text-primary-400': value === option.value,
                                            'text-dark-200 hover:bg-dark-700/50 hover:text-dark-50': value !== option.value,
                                            'opacity-50 cursor-not-allowed': option.disabled,
                                        }
                                    )}
                                >
                                    <span>{option.label}</span>
                                    {value === option.value && (
                                        <Check className="w-4 h-4" />
                                    )}
                                </button>
                            ))
                        )}
                    </div>
                </div>
            )}

            {error && (
                <p className="text-sm text-red-400 flex items-center gap-1.5">
                    <AlertCircle className="w-3.5 h-3.5 flex-shrink-0" />
                    {error}
                </p>
            )}
        </div>
    );
}
