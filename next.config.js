/** @type {import('next').NextConfig} */
const nextConfig = {
  // Static export for robust Cloudflare Pages deployment
  // Using query params instead of dynamic routes for compatibility
  output: 'export',

  // Disable image optimization
  images: {
    unoptimized: true,
  },

  // Trailing slashes for static hosting
  trailingSlash: true,

  // Strict mode
  reactStrictMode: true,

  // TypeScript
  typescript: {
    ignoreBuildErrors: true,
  },

  // ESLint
  eslint: {
    ignoreDuringBuilds: true,
  },
};

module.exports = nextConfig;
