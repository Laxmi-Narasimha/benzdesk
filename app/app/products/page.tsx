'use client';

import { ProductGuide } from '@/components/products/ProductGuide';
import { PackageSearch } from 'lucide-react';

export default function ProductGuidePage() {
    return (
        <div className="space-y-6 h-[calc(100vh-theme(spacing.40))]">
            <div className="mb-6">
                <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-3">
                    <div className="p-2 bg-primary-100 rounded-lg">
                        <PackageSearch className="w-6 h-6 text-primary-600" />
                    </div>
                    Product Guide & Certifications
                </h1>
                <p className="mt-1 text-sm text-gray-500 ml-12">
                    Comprehensive catalog of Benz Packaging solutions, specifications, and compliance standards.
                </p>
            </div>

            <ProductGuide />
        </div>
    );
}
