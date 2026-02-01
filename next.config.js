/** @type {import('next').NextConfig} */
const nextConfig = {
  // Static export for Cloudflare Pages
  // Required for static hosting without server adapter
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
