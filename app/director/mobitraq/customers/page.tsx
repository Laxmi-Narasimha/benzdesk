'use client';

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
    AlertTriangle, CheckCircle2, MapPin, Plus, RefreshCw, Search, Trash2, X,
} from 'lucide-react';
import { getSupabaseClient } from '@/lib/supabaseClient';

interface Customer {
    id: string;
    google_place_id: string | null;
    name: string;
    formatted_address: string | null;
    latitude: number | null;
    longitude: number | null;
    phone: string | null;
    website: string | null;
    notes: string | null;
    is_active: boolean;
    created_at: string;
}

interface PlacesPrediction {
    place_id: string;
    description: string;
    structured_formatting?: {
        main_text: string;
        secondary_text?: string;
    };
}

const GOOGLE_MAPS_BROWSER_KEY =
    process.env.NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY ?? '';

export default function CustomersPage() {
    const [customers, setCustomers] = useState<Customer[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [search, setSearch] = useState('');
    const [info, setInfo] = useState<string | null>(null);

    // Add-via-Place-ID modal
    const [showAdd, setShowAdd] = useState(false);
    const [adding, setAdding] = useState(false);

    const refresh = useCallback(async () => {
        setLoading(true);
        setError(null);
        try {
            const sb = getSupabaseClient();
            const { data, error: e } = await sb
                .from('customers')
                .select('*')
                .order('is_active', { ascending: false })
                .order('name', { ascending: true });
            if (e) throw e;
            setCustomers((data || []) as Customer[]);
        } catch (e: any) {
            setError(e?.message || String(e));
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        void refresh();
    }, [refresh]);

    const filtered = useMemo(() => {
        const q = search.trim().toLowerCase();
        if (!q) return customers;
        return customers.filter(
            (c) =>
                c.name.toLowerCase().includes(q) ||
                (c.formatted_address || '').toLowerCase().includes(q) ||
                (c.google_place_id || '').toLowerCase().includes(q),
        );
    }, [customers, search]);

    const flash = (msg: string) => {
        setInfo(msg);
        setTimeout(() => setInfo((m) => (m === msg ? null : m)), 4000);
    };

    const toggleActive = async (c: Customer) => {
        try {
            const sb = getSupabaseClient();
            const { error } = await sb
                .from('customers')
                .update({ is_active: !c.is_active })
                .eq('id', c.id);
            if (error) throw error;
            await refresh();
            flash(c.is_active ? 'Customer deactivated' : 'Customer re-activated');
        } catch (e: any) {
            setError(e?.message || String(e));
        }
    };

    return (
        <div className="space-y-6">
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
                <div>
                    <h1 className="text-2xl font-bold text-gray-900">Customers</h1>
                    <p className="text-sm text-gray-500">
                        Master list of customer sites, anchored to Google Place IDs.
                        Stops within 100m of these locations are auto-tagged on
                        the timeline.
                    </p>
                </div>
                <div className="flex items-center gap-2">
                    <button
                        onClick={() => void refresh()}
                        className="inline-flex items-center gap-2 px-3 py-2 text-sm bg-white border border-gray-200 rounded-lg hover:bg-gray-50"
                    >
                        <RefreshCw className="w-4 h-4" />
                        Refresh
                    </button>
                    <button
                        onClick={() => setShowAdd(true)}
                        className="inline-flex items-center gap-2 px-3 py-2 text-sm bg-primary-600 text-white rounded-lg hover:bg-primary-700"
                    >
                        <Plus className="w-4 h-4" />
                        Add customer
                    </button>
                </div>
            </div>

            {error && (
                <div className="flex items-start gap-3 p-4 bg-red-50 border border-red-200 rounded-xl text-red-800">
                    <AlertTriangle className="w-5 h-5 mt-0.5 flex-shrink-0 text-red-500" />
                    <div className="text-sm">{error}</div>
                </div>
            )}
            {info && (
                <div className="flex items-start gap-3 p-4 bg-green-50 border border-green-200 rounded-xl text-green-800">
                    <CheckCircle2 className="w-5 h-5 mt-0.5 flex-shrink-0 text-green-500" />
                    <div className="text-sm">{info}</div>
                </div>
            )}

            <div className="flex items-center gap-2 bg-white p-2 rounded-lg border border-gray-200">
                <Search className="w-4 h-4 text-gray-400 ml-2" />
                <input
                    type="text"
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                    placeholder="Search by name, address, or Place ID"
                    className="flex-1 px-2 py-1.5 text-sm outline-none bg-transparent"
                />
                {search && (
                    <button onClick={() => setSearch('')}>
                        <X className="w-4 h-4 text-gray-400" />
                    </button>
                )}
            </div>

            <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
                {loading ? (
                    <div className="p-12 text-center text-gray-500">Loading...</div>
                ) : filtered.length === 0 ? (
                    <div className="p-12 text-center text-gray-500">
                        <MapPin className="w-10 h-10 mx-auto text-gray-300 mb-2" />
                        <p className="font-medium">No customers yet</p>
                        <p className="text-sm mt-1 text-gray-400">
                            Click "Add customer" to bind a customer site to a Google Place.
                        </p>
                    </div>
                ) : (
                    <div className="overflow-x-auto">
                        <table className="w-full text-sm">
                            <thead className="bg-gray-50">
                                <tr>
                                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Name</th>
                                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Address</th>
                                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Place ID</th>
                                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                                    <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">Actions</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-100">
                                {filtered.map((c) => (
                                    <tr key={c.id} className="hover:bg-gray-50">
                                        <td className="px-4 py-3 font-medium text-gray-900">{c.name}</td>
                                        <td className="px-4 py-3 text-gray-700">{c.formatted_address || '—'}</td>
                                        <td className="px-4 py-3 font-mono text-xs text-gray-500">
                                            {c.google_place_id ? c.google_place_id.slice(0, 14) + '…' : '—'}
                                        </td>
                                        <td className="px-4 py-3">
                                            {c.is_active ? (
                                                <span className="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-700">
                                                    Active
                                                </span>
                                            ) : (
                                                <span className="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-600">
                                                    Inactive
                                                </span>
                                            )}
                                        </td>
                                        <td className="px-4 py-3 text-right">
                                            <button
                                                onClick={() => void toggleActive(c)}
                                                className="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200"
                                            >
                                                {c.is_active ? <Trash2 className="w-3 h-3" /> : <CheckCircle2 className="w-3 h-3" />}
                                                {c.is_active ? 'Deactivate' : 'Reactivate'}
                                            </button>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>

            {showAdd && (
                <AddCustomerModal
                    onClose={() => setShowAdd(false)}
                    onAdded={async () => {
                        setShowAdd(false);
                        await refresh();
                        flash('Customer added');
                    }}
                    setError={setError}
                    setBusy={setAdding}
                    busy={adding}
                />
            )}
        </div>
    );
}

// =============================================================================
// Add-customer modal — Places Autocomplete + Place Details fetch
// =============================================================================

function AddCustomerModal({
    onClose,
    onAdded,
    setError,
    setBusy,
    busy,
}: {
    onClose: () => void;
    onAdded: () => Promise<void>;
    setError: (m: string | null) => void;
    setBusy: (b: boolean) => void;
    busy: boolean;
}) {
    const [query, setQuery] = useState('');
    const [predictions, setPredictions] = useState<PlacesPrediction[]>([]);
    const [loadingSuggest, setLoadingSuggest] = useState(false);
    const [picked, setPicked] = useState<{
        place_id: string;
        name: string;
        formatted_address?: string;
        latitude?: number;
        longitude?: number;
        phone?: string;
        website?: string;
    } | null>(null);
    const [notes, setNotes] = useState('');
    const sessionTokenRef = useRef(generateSessionToken());
    const debounceRef = useRef<NodeJS.Timeout | null>(null);

    useEffect(() => {
        if (!GOOGLE_MAPS_BROWSER_KEY) return;
        // Load Google Maps JS for the AutocompleteService + PlacesService.
        // We use the JS SDK rather than the REST endpoint here so we
        // don't hit CORS issues from a browser context.
        ensureGoogleScript(GOOGLE_MAPS_BROWSER_KEY).catch(() => {
            setError('Failed to load Google Maps script');
        });
    }, [setError]);

    const onQueryChange = (val: string) => {
        setQuery(val);
        setPicked(null);
        if (debounceRef.current) clearTimeout(debounceRef.current);
        if (val.trim().length < 2) {
            setPredictions([]);
            return;
        }
        debounceRef.current = setTimeout(() => fetchPredictions(val), 250);
    };

    const fetchPredictions = async (val: string) => {
        const g = (window as any).google;
        if (!g?.maps?.places?.AutocompleteService) return;
        setLoadingSuggest(true);
        try {
            const svc = new g.maps.places.AutocompleteService();
            svc.getPlacePredictions(
                {
                    input: val,
                    sessionToken: sessionTokenRef.current,
                    componentRestrictions: { country: 'in' },
                },
                (preds: PlacesPrediction[] | null, status: string) => {
                    setLoadingSuggest(false);
                    if (status !== 'OK' || !preds) {
                        setPredictions([]);
                        return;
                    }
                    setPredictions(preds.slice(0, 6));
                },
            );
        } catch (e) {
            setLoadingSuggest(false);
        }
    };

    const pickPrediction = async (p: PlacesPrediction) => {
        const g = (window as any).google;
        if (!g?.maps?.places?.PlacesService) return;
        setBusy(true);
        try {
            // PlacesService needs a real (offscreen) Node attached.
            const dummy = document.createElement('div');
            const svc = new g.maps.places.PlacesService(dummy);
            svc.getDetails(
                {
                    placeId: p.place_id,
                    sessionToken: sessionTokenRef.current,
                    fields: [
                        'place_id',
                        'name',
                        'formatted_address',
                        'geometry.location',
                        'formatted_phone_number',
                        'website',
                    ],
                },
                (result: any, status: string) => {
                    setBusy(false);
                    if (status !== 'OK' || !result) {
                        setError(`Place Details failed: ${status}`);
                        return;
                    }
                    setQuery(result.name || p.description);
                    setPicked({
                        place_id: result.place_id,
                        name: result.name || p.description,
                        formatted_address: result.formatted_address,
                        latitude: result.geometry?.location?.lat?.(),
                        longitude: result.geometry?.location?.lng?.(),
                        phone: result.formatted_phone_number,
                        website: result.website,
                    });
                    setPredictions([]);
                    // Rotate session token after a pick — next typing
                    // is a fresh billing session.
                    sessionTokenRef.current = generateSessionToken();
                },
            );
        } catch (e) {
            setBusy(false);
            setError(String(e));
        }
    };

    const save = async () => {
        if (!picked) return;
        setBusy(true);
        try {
            const sb = getSupabaseClient();
            const { error } = await sb.from('customers').insert({
                google_place_id: picked.place_id,
                name: picked.name,
                formatted_address: picked.formatted_address,
                latitude: picked.latitude,
                longitude: picked.longitude,
                phone: picked.phone,
                website: picked.website,
                notes: notes.trim() || null,
                is_active: true,
            });
            if (error) {
                if ((error as any).code === '23505') {
                    setError('This Google Place is already in your customer list.');
                } else {
                    setError(error.message);
                }
                return;
            }
            await onAdded();
        } catch (e: any) {
            setError(e?.message || String(e));
        } finally {
            setBusy(false);
        }
    };

    return (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4">
            <div className="bg-white rounded-2xl shadow-2xl max-w-lg w-full p-6">
                <div className="flex items-center justify-between mb-4">
                    <h2 className="text-lg font-semibold text-gray-900">Add customer</h2>
                    <button onClick={onClose}>
                        <X className="w-5 h-5 text-gray-400" />
                    </button>
                </div>

                <p className="text-sm text-gray-500 mb-4">
                    Search for the customer's business or site on Google. Picking
                    a result binds the customer to a stable Google Place ID, so
                    visits get auto-detected on the timeline.
                </p>

                <div className="relative">
                    <input
                        type="text"
                        value={query}
                        onChange={(e) => onQueryChange(e.target.value)}
                        placeholder="e.g. Maxim SMT Technologies"
                        className="w-full px-3 py-2.5 border border-gray-200 rounded-lg outline-none focus:border-primary-500 text-sm"
                    />
                    {loadingSuggest && (
                        <div className="absolute right-3 top-3 text-xs text-gray-400">
                            Searching…
                        </div>
                    )}
                    {predictions.length > 0 && (
                        <div className="absolute z-10 mt-1 w-full bg-white border border-gray-200 rounded-lg shadow-lg max-h-60 overflow-y-auto">
                            {predictions.map((p) => (
                                <button
                                    key={p.place_id}
                                    onClick={() => void pickPrediction(p)}
                                    className="w-full text-left px-3 py-2 hover:bg-gray-50 border-b border-gray-100 last:border-b-0"
                                >
                                    <div className="font-medium text-sm text-gray-900">
                                        {p.structured_formatting?.main_text || p.description}
                                    </div>
                                    {p.structured_formatting?.secondary_text && (
                                        <div className="text-xs text-gray-500 mt-0.5">
                                            {p.structured_formatting.secondary_text}
                                        </div>
                                    )}
                                </button>
                            ))}
                        </div>
                    )}
                </div>

                {picked && (
                    <div className="mt-4 p-3 bg-gray-50 rounded-lg border border-gray-200">
                        <div className="flex items-start gap-2">
                            <CheckCircle2 className="w-4 h-4 text-green-500 mt-0.5" />
                            <div className="flex-1">
                                <div className="font-medium text-sm">{picked.name}</div>
                                {picked.formatted_address && (
                                    <div className="text-xs text-gray-600 mt-0.5">
                                        {picked.formatted_address}
                                    </div>
                                )}
                                {picked.latitude != null && (
                                    <div className="text-xs text-gray-400 mt-1 font-mono">
                                        {picked.latitude.toFixed(5)}, {picked.longitude!.toFixed(5)}
                                    </div>
                                )}
                            </div>
                        </div>
                    </div>
                )}

                <div className="mt-4">
                    <label className="text-xs font-medium text-gray-700">
                        Internal notes (optional)
                    </label>
                    <textarea
                        value={notes}
                        onChange={(e) => setNotes(e.target.value)}
                        rows={2}
                        className="mt-1 w-full px-3 py-2 border border-gray-200 rounded-lg text-sm outline-none focus:border-primary-500"
                        placeholder="e.g. Key account, decision-maker = Mr. Sharma"
                    />
                </div>

                <div className="flex items-center justify-end gap-2 mt-5">
                    <button
                        onClick={onClose}
                        className="px-4 py-2 text-sm text-gray-600 rounded-lg hover:bg-gray-100"
                    >
                        Cancel
                    </button>
                    <button
                        onClick={() => void save()}
                        disabled={!picked || busy}
                        className="px-4 py-2 text-sm bg-primary-600 text-white rounded-lg hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                        {busy ? 'Saving…' : 'Add customer'}
                    </button>
                </div>
            </div>
        </div>
    );
}

// =============================================================================
// Helpers
// =============================================================================

function generateSessionToken() {
    return (
        'tok-' +
        Math.random().toString(36).slice(2) +
        Date.now().toString(36)
    );
}

let _gPromise: Promise<void> | null = null;
function ensureGoogleScript(key: string): Promise<void> {
    if ((window as any).google?.maps?.places) return Promise.resolve();
    if (_gPromise) return _gPromise;
    _gPromise = new Promise<void>((resolve, reject) => {
        const existing = document.getElementById('google-maps-script');
        if (existing) {
            existing.addEventListener('load', () => resolve());
            existing.addEventListener('error', () => reject(new Error('Google Maps script failed')));
            return;
        }
        const script = document.createElement('script');
        script.id = 'google-maps-script';
        script.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(key)}&libraries=geometry,places`;
        script.async = true;
        script.defer = true;
        script.onload = () => resolve();
        script.onerror = () => reject(new Error('Google Maps script failed'));
        document.body.appendChild(script);
    });
    return _gPromise;
}
