'use client';

import React, { useState, useEffect } from 'react';
import { productsData, Category, Product } from '@/lib/data/products';
import { clsx } from 'clsx';
import {
    Search,
    CheckCircle2,
    Award,
    ShieldCheck,
    Leaf,
    Package,
    ChevronRight,
    Menu,
    ChevronDown,
    ArrowRight,
    Star
} from 'lucide-react';

// ============================================================================
// Helpers & Sub-components
// ============================================================================

const HighlightText = ({ text }: { text: string }) => {
    return <span dangerouslySetInnerHTML={{
        __html: text.replace(
            /(ISO\s?\d{4}(?::\d{4})?|FDA\s?(?:approved)?|DIN\s?[\w\d:-]+|MIL-[\w-]+|ASTM\s?[\w\d-]+|DMF-free|OHSAS\s?\d{4}(?::\d{4})?)/gi,
            '<span class="font-bold text-amber-700 bg-amber-100/80 px-1.5 py-0.5 rounded box-decoration-clone border border-amber-200/50">$1</span>'
        )
    }} />;
};

const CertificationBadge = ({ label, icon: Icon, colorClass }: { label: string, icon: any, colorClass: string }) => (
    <span className={clsx(
        "inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold border transition-transform hover:scale-105 cursor-default shadow-sm",
        colorClass
    )}>
        <Icon className="w-3.5 h-3.5" />
        {label}
    </span>
);

const CertificationBadges = ({ features }: { features: string[] }) => {
    const allText = features.join(' ');

    // Config for badges to make them distinct
    const configs = [
        { regex: /ISO\s?9001/, label: 'ISO 9001', icon: Award, color: 'bg-blue-50 text-blue-700 border-blue-200' },
        { regex: /ISO\s?14001/, label: 'ISO 14001', icon: Leaf, color: 'bg-green-50 text-green-700 border-green-200' },
        { regex: /FDA/, label: 'FDA Approved', icon: ShieldCheck, color: 'bg-rose-50 text-rose-700 border-rose-200' },
        { regex: /DMF-free/i, label: 'DMF Free', icon: CheckCircle2, color: 'bg-teal-50 text-teal-700 border-teal-200' },
        { regex: /MIL-/, label: 'MIL Spec', icon: Star, color: 'bg-slate-50 text-slate-700 border-slate-200' },
        { regex: /Biodegradable/i, label: 'Biodegradable', icon: Leaf, color: 'bg-emerald-50 text-emerald-700 border-emerald-200' },
        { regex: /Recyclable/i, label: 'Recyclable', icon: Package, color: 'bg-indigo-50 text-indigo-700 border-indigo-200' },
    ];

    const activeBadges = configs.filter(c => allText.match(c.regex));

    if (activeBadges.length === 0) return null;

    return (
        <div className="flex flex-wrap gap-2 mb-5">
            {activeBadges.map((badge, i) => (
                <CertificationBadge
                    key={i}
                    label={badge.label}
                    icon={badge.icon}
                    colorClass={badge.color}
                />
            ))}
        </div>
    );
};

const FeatureList = ({ features }: { features: string[] }) => {
    const [isExpanded, setIsExpanded] = useState(false);
    const hasMore = features.length > 3;
    const displayFeatures = isExpanded ? features : features.slice(0, 3);

    return (
        <div className="space-y-3">
            <ul className="space-y-2.5">
                {displayFeatures.map((feature, idx) => (
                    <li key={idx} className="flex gap-3 text-sm text-gray-600 leading-relaxed group/item">
                        <div className="shrink-0 mt-1.5 w-1.5 h-1.5 rounded-full bg-primary-400 group-hover/item:bg-primary-600 transition-colors" />
                        <div className="group-hover/item:text-gray-900 transition-colors">
                            <HighlightText text={feature} />
                        </div>
                    </li>
                ))}
            </ul>
            {hasMore && (
                <button
                    onClick={() => setIsExpanded(!isExpanded)}
                    className="text-xs font-semibold text-primary-600 hover:text-primary-700 flex items-center gap-1 mt-2 transition-colors"
                >
                    {isExpanded ? 'Show Less' : `Show ${features.length - 3} More Features`}
                    <ChevronDown className={clsx("w-3 h-3 transition-transform", isExpanded && "rotate-180")} />
                </button>
            )}
        </div>
    );
};

const ProductCard = ({ product }: { product: Product }) => {
    return (
        <div className="bg-white rounded-2xl border border-gray-200/75 shadow-sm hover:shadow-xl hover:border-primary-200/75 transition-all duration-300 overflow-hidden group flex flex-col h-full animate-in fade-in slide-in-from-bottom-4">
            <div className="p-6 flex-1 flex flex-col">
                <div className="flex items-start justify-between mb-4">
                    <div>
                        <h3 className="text-xl font-bold text-gray-900 group-hover:text-primary-600 transition-colors">
                            {product.name}
                        </h3>
                        {/* Fake category tag if available or just spacing */}
                        <div className="h-1 w-12 bg-primary-500 rounded-full mt-2 opacity-0 group-hover:opacity-100 transition-opacity" />
                    </div>
                    <div className="p-2.5 bg-gray-50 rounded-xl group-hover:bg-primary-50 transition-colors rotate-0 group-hover:rotate-12 duration-300">
                        <Package className="w-6 h-6 text-gray-400 group-hover:text-primary-500" />
                    </div>
                </div>

                <CertificationBadges features={product.features} />

                {product.features.length > 0 && (
                    <div className="mt-2 flex-1">
                        <FeatureList features={product.features} />
                    </div>
                )}
            </div>

            {/* Sub Products (Bottom Section) */}
            {product.subProducts && (
                <div className="bg-gray-50/50 border-t border-gray-100 p-4 space-y-3">
                    <p className="text-xs font-bold text-gray-400 uppercase tracking-wider px-2">Variations / Types</p>
                    <div className="grid gap-3">
                        {product.subProducts.map(sub => (
                            <div key={sub.id} className="bg-white rounded-xl p-4 border border-gray-200/60 shadow-sm hover:border-primary-200 transition-colors">
                                <h4 className="font-semibold text-gray-800 mb-2 flex items-center gap-2">
                                    <span className="w-1.5 h-1.5 rounded-full bg-primary-500" />
                                    {sub.name}
                                </h4>
                                <CertificationBadges features={sub.features} />
                                <FeatureList features={sub.features} />
                            </div>
                        ))}
                    </div>
                </div>
            )}
        </div>
    );
};

// ============================================================================
// Main Component
// ============================================================================

export function ProductGuide() {
    const [selectedCategoryId, setSelectedCategoryId] = useState<string>(productsData[0].id);
    const [searchQuery, setSearchQuery] = useState('');
    const [scrolled, setScrolled] = useState(false);

    const activeCategory = productsData.find(c => c.id === selectedCategoryId);

    // Handle scroll for sticky header shadow
    useEffect(() => {
        const handleScroll = () => setScrolled(window.scrollY > 20);
        window.addEventListener('scroll', handleScroll);
        return () => window.removeEventListener('scroll', handleScroll);
    }, []);

    const searchResults = searchQuery
        ? productsData.flatMap(cat =>
            cat.products.filter(p =>
                p.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
                p.features.some(f => f.toLowerCase().includes(searchQuery.toLowerCase())) ||
                p.subProducts?.some(sp => sp.name.toLowerCase().includes(searchQuery.toLowerCase()))
            ).map(p => ({ ...p, categoryName: cat.name }))
        )
        : [];

    return (
        <div className="flex flex-col h-[calc(100vh-theme(spacing.24))] md:flex-row gap-6 lg:gap-8">

            {/* Mobile: Sticky Horizontal Category Nav */}
            <div className={clsx(
                "md:hidden -mx-4 px-4 pt-2 pb-2 sticky top-0 z-30 bg-gray-50/95 backdrop-blur-sm transition-all border-b",
                scrolled ? "border-gray-200 shadow-sm" : "border-transparent"
            )}>
                <div className="flex overflow-x-auto gap-2 pb-2 hide-scrollbar snap-x">
                    {productsData.map((category) => (
                        <button
                            key={category.id}
                            onClick={() => {
                                setSelectedCategoryId(category.id);
                                setSearchQuery('');
                                window.scrollTo({ top: 0, behavior: 'smooth' });
                            }}
                            className={clsx(
                                "flex-shrink-0 px-4 py-2 rounded-full text-sm font-medium whitespace-nowrap transition-all border snap-start",
                                selectedCategoryId === category.id
                                    ? "bg-primary-600 text-white border-primary-600 shadow-md shadow-primary-500/20"
                                    : "bg-white text-gray-600 border-gray-200 hover:border-gray-300"
                            )}
                        >
                            {category.name.replace(/^\d+\.\s*/, '')}
                        </button>
                    ))}
                </div>
            </div>

            {/* Desktop Sidebar */}
            <aside className="hidden md:block w-72 lg:w-80 shrink-0">
                <div className="bg-white rounded-2xl shadow-sm border border-gray-200 overflow-hidden sticky top-4 max-h-[calc(100vh-theme(spacing.32))] flex flex-col">
                    <div className="p-5 bg-gradient-to-br from-gray-50 to-white border-b border-gray-100">
                        <h2 className="font-bold text-gray-800 flex items-center gap-2.5 text-lg">
                            <div className="p-1.5 bg-primary-100 text-primary-600 rounded-lg">
                                <Menu className="w-4 h-4" />
                            </div>
                            Categories
                        </h2>
                    </div>
                    <div className="overflow-y-auto flex-1 p-3 space-y-1 custom-scrollbar">
                        {productsData.map((category) => (
                            <button
                                key={category.id}
                                onClick={() => {
                                    setSelectedCategoryId(category.id);
                                    setSearchQuery('');
                                }}
                                className={clsx(
                                    'w-full text-left px-4 py-3 rounded-xl text-sm transition-all duration-200 border border-transparent',
                                    selectedCategoryId === category.id && !searchQuery
                                        ? 'bg-primary-50 text-primary-700 font-bold shadow-sm border-primary-100 translate-x-1'
                                        : 'text-gray-600 hover:bg-gray-50 hover:text-gray-900 hover:border-gray-100'
                                )}
                            >
                                <div className="flex items-center justify-between">
                                    <span>{category.name}</span>
                                    {selectedCategoryId === category.id && !searchQuery && (
                                        <ChevronRight className="w-4 h-4 text-primary-500" />
                                    )}
                                </div>
                            </button>
                        ))}
                    </div>
                </div>
            </aside>

            {/* Main Content */}
            <main className="flex-1 min-w-0 overflow-y-auto pr-2 custom-scrollbar pb-20">
                {/* Search Bar */}
                <div className="relative mb-8 group">
                    <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                        <Search className="h-5 w-5 text-gray-400 group-focus-within:text-primary-500 transition-colors" />
                    </div>
                    <input
                        type="text"
                        placeholder="Search products, specifications, or certifications..."
                        value={searchQuery}
                        onChange={(e) => setSearchQuery(e.target.value)}
                        className="block w-full pl-11 pr-4 py-4 bg-white border border-gray-200 rounded-2xl leading-5 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-500/50 focus:border-primary-500 transition-all shadow-sm group-hover:shadow-md"
                    />
                    <div className="absolute inset-y-0 right-0 pr-4 flex items-center">
                        <kbd className="hidden md:inline-flex items-center border border-gray-200 rounded px-2 text-xs font-sans font-medium text-gray-400">
                            /
                        </kbd>
                    </div>
                </div>

                {searchQuery ? (
                    <div className="animate-in fade-in duration-500">
                        <div className="flex items-center justify-between mb-6">
                            <h2 className="text-xl font-bold text-gray-900 flex items-center gap-2">
                                <Search className="w-5 h-5 text-primary-500" />
                                Search Results
                            </h2>
                            <span className="px-3 py-1 bg-gray-100 text-gray-600 rounded-full text-xs font-semibold">
                                {searchResults.length} found
                            </span>
                        </div>

                        {searchResults.length > 0 ? (
                            <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
                                {searchResults.map((product: any) => (
                                    <div key={product.id} className="relative group">
                                        <div className="absolute -top-3 left-6 bg-gray-800 text-white text-[10px] uppercase font-bold px-3 py-1 rounded-full z-10 shadow-lg group-hover:scale-110 transition-transform">
                                            {product.categoryName}
                                        </div>
                                        <ProductCard product={product} />
                                    </div>
                                ))}
                            </div>
                        ) : (
                            <div className="flex flex-col items-center justify-center py-16 bg-white rounded-3xl border-2 border-dashed border-gray-100 text-center">
                                <div className="w-20 h-20 bg-gray-50 rounded-full flex items-center justify-center mb-4">
                                    <Search className="w-10 h-10 text-gray-300" />
                                </div>
                                <h3 className="text-lg font-bold text-gray-900 mb-1">No products found</h3>
                                <p className="text-gray-500 max-w-xs mx-auto">
                                    We couldn't find anything matching "{searchQuery}". Try different keywords.
                                </p>
                            </div>
                        )}
                    </div>
                ) : (
                    activeCategory && (
                        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-2 duration-500">
                            {/* Hero Banner for Category */}
                            <div className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-primary-600 to-indigo-700 text-white shadow-xl shadow-primary-900/20">
                                <div className="absolute top-0 right-0 w-64 h-64 bg-white/10 rounded-full blur-3xl -mr-32 -mt-32 pointer-events-none" />
                                <div className="absolute bottom-0 left-0 w-48 h-48 bg-black/10 rounded-full blur-2xl -ml-24 -mb-24 pointer-events-none" />

                                <div className="relative p-8 md:p-10">
                                    <h1 className="text-2xl md:text-4xl font-extrabold mb-3 tracking-tight">
                                        {activeCategory.name}
                                    </h1>
                                    <p className="text-primary-100 text-sm md:text-base max-w-2xl leading-relaxed opacity-90">
                                        Benz Packaging offers industry-leading solutions in this category.
                                        Browse specs, certifications, and variants below.
                                    </p>

                                    <div className="mt-6 flex flex-wrap gap-3">
                                        <div className="flex items-center gap-2 px-3 py-1.5 bg-white/10 rounded-full backdrop-blur-sm text-xs font-medium border border-white/10">
                                            <ShieldCheck className="w-3.5 h-3.5" />
                                            Quality Certified
                                        </div>
                                        <div className="flex items-center gap-2 px-3 py-1.5 bg-white/10 rounded-full backdrop-blur-sm text-xs font-medium border border-white/10">
                                            <Leaf className="w-3.5 h-3.5" />
                                            Eco-Friendly Lines
                                        </div>
                                    </div>
                                </div>
                            </div>

                            <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
                                {activeCategory.products.map((product) => (
                                    <ProductCard key={product.id} product={product} />
                                ))}
                            </div>

                            {/* Trust Footer */}
                            <div className="mt-12 py-8 border-t border-gray-100 text-center">
                                <p className="text-gray-400 text-sm flex items-center justify-center gap-2 mb-2">
                                    <ShieldCheck className="w-4 h-4 text-emerald-500" />
                                    <span>Manufactured to International Standards</span>
                                </p>
                                <p className="text-xs text-gray-300">
                                    ISO 9001:2015 • ISO 14001:2015 • OHsas 18001:2007
                                </p>
                            </div>
                        </div>
                    )
                )}
            </main>
        </div>
    );
}
