/** @type {import('tailwindcss').Config} */
module.exports = {
    content: [
        './app/**/*.{js,ts,jsx,tsx,mdx}',
        './components/**/*.{js,ts,jsx,tsx,mdx}',
        './lib/**/*.{js,ts,jsx,tsx,mdx}',
    ],
    theme: {
        extend: {
            colors: {
                // Primary accent - professional blue
                primary: {
                    50: '#e7f5ff',
                    100: '#d0ebff',
                    200: '#a5d8ff',
                    300: '#74c0fc',
                    400: '#4dabf7',
                    500: '#228be6',
                    600: '#1c7ed6',
                    700: '#1971c2',
                    800: '#1864ab',
                    900: '#145591',
                    950: '#0d3b66',
                },
                // Semantic colors for request statuses
                status: {
                    open: '#40c057',
                    'in-progress': '#228be6',
                    waiting: '#fab005',
                    'pending-closure': '#e599f7',
                    closed: '#868e96',
                },
                // Priority colors
                priority: {
                    critical: '#fa5252',
                    high: '#fd7e14',
                    medium: '#fab005',
                    low: '#40c057',
                    minimal: '#868e96',
                },
                // Light mode grayscale (dark- prefix kept for compatibility)
                dark: {
                    50: '#212529',
                    100: '#343a40',
                    200: '#495057',
                    300: '#6c757d',
                    400: '#868e96',
                    500: '#adb5bd',
                    600: '#ced4da',
                    700: '#dee2e6',
                    800: '#e9ecef',
                    850: '#f1f3f5',
                    900: '#f8f9fa',
                    950: '#ffffff',
                },
            },
            fontFamily: {
                sans: ['Inter', 'system-ui', '-apple-system', 'sans-serif'],
                mono: ['JetBrains Mono', 'Fira Code', 'monospace'],
            },
            boxShadow: {
                'subtle': '0 1px 3px 0 rgba(0, 0, 0, 0.08)',
                'card': '0 2px 8px -2px rgba(0, 0, 0, 0.08)',
                'elevated': '0 8px 24px -6px rgba(0, 0, 0, 0.12)',
                'modal': '0 20px 40px -12px rgba(0, 0, 0, 0.2)',
            },
            animation: {
                'fade-in': 'fadeIn 0.2s ease-out',
                'slide-up': 'slideUp 0.2s ease-out',
                'slide-down': 'slideDown 0.2s ease-out',
                'slide-in-right': 'slideInRight 0.3s ease-out',
            },
            keyframes: {
                fadeIn: {
                    '0%': { opacity: '0' },
                    '100%': { opacity: '1' },
                },
                slideUp: {
                    '0%': { opacity: '0', transform: 'translateY(8px)' },
                    '100%': { opacity: '1', transform: 'translateY(0)' },
                },
                slideDown: {
                    '0%': { opacity: '0', transform: 'translateY(-8px)' },
                    '100%': { opacity: '1', transform: 'translateY(0)' },
                },
                slideInRight: {
                    '0%': { opacity: '0', transform: 'translateX(-100%)' },
                    '100%': { opacity: '1', transform: 'translateX(0)' },
                },
            },
            borderRadius: {
                'xl': '0.75rem',
                '2xl': '1rem',
            },
            screens: {
                'xs': '375px',
            },
        },
    },
    plugins: [],
};
