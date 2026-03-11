'use client';

import React, { useCallback, useEffect, useState } from 'react';
import { getSupabaseClient } from '@/lib/supabaseClient';
import {
    Users, Search, Save, X, Shield, Check, AlertTriangle,
    Phone, Mail, ChevronDown, Pencil, Trash2, Briefcase, RefreshCw,
} from 'lucide-react';

// ============================================================================
// Types & Constants
// ============================================================================

interface Employee {
    id: string;
    name: string;
    phone: string | null;
    email: string | null;
    role: string;
    band: string | null;
    created_at: string;
    mobitraq_enrolled_at: string | null;
}

const BANDS = [
    { value: 'executive', label: 'Executive' },
    { value: 'senior_executive', label: 'Sr. Executive' },
    { value: 'assistant', label: 'Assistant' },
    { value: 'assistant_manager', label: 'Asst. Manager' },
    { value: 'manager', label: 'Manager' },
    { value: 'senior_manager', label: 'Sr. Manager' },
    { value: 'agm', label: 'AGM' },
    { value: 'gm', label: 'GM' },
    { value: 'plant_head', label: 'Plant Head' },
    { value: 'vp', label: 'VP' },
    { value: 'director', label: 'Director' },
];

const BAND_COLORS: Record<string, string> = {
    executive: 'bg-slate-100 text-slate-700',
    senior_executive: 'bg-blue-100 text-blue-700',
    assistant: 'bg-cyan-100 text-cyan-700',
    assistant_manager: 'bg-teal-100 text-teal-700',
    manager: 'bg-emerald-100 text-emerald-700',
    senior_manager: 'bg-green-100 text-green-700',
    agm: 'bg-amber-100 text-amber-700',
    gm: 'bg-orange-100 text-orange-700',
    plant_head: 'bg-red-100 text-red-700',
    vp: 'bg-purple-100 text-purple-700',
    director: 'bg-indigo-100 text-indigo-700',
};

const getBandLabel = (band: string | null) =>
    band ? (BANDS.find(b => b.value === band)?.label || band) : 'Not Set';

// ============================================================================
// Page
// ============================================================================

export default function EmployeeManagementPage() {
    const [employees, setEmployees] = useState<Employee[]>([]);
    const [loading, setLoading] = useState(true);
    const [search, setSearch] = useState('');
    const [bandFilter, setBandFilter] = useState('all');
    const [editing, setEditing] = useState<string | null>(null);
    const [form, setForm] = useState({ name: '', phone: '', band: '', role: '' });
    const [deleting, setDeleting] = useState<string | null>(null);
    const [saving, setSaving] = useState(false);
    const [toast, setToast] = useState<{ msg: string; ok: boolean } | null>(null);
    const [hasEmailCol, setHasEmailCol] = useState(false);

    const flash = useCallback((msg: string, ok: boolean) => {
        setToast({ msg, ok });
        setTimeout(() => setToast(null), 3500);
    }, []);

    // ── Load ───────────────────────────────────────────────────────────
    const load = useCallback(async () => {
        setLoading(true);
        try {
            const sb = getSupabaseClient();
            // Only show employees who have enrolled in MobiTraq (logged in via the app)
            let query = sb.from('employees')
                .select('id, name, phone, email, role, band, created_at, mobitraq_enrolled_at')
                .not('mobitraq_enrolled_at', 'is', null)
                .order('name', { ascending: true });

            let { data, error } = await query;

            if (error && error.message.includes('does not exist')) {
                // email or mobitraq_enrolled_at column doesn't exist yet, query without them
                const fallback = await sb.from('employees')
                    .select('id, name, phone, role, band, created_at')
                    .order('name', { ascending: true });
                data = fallback.data as any;
                error = fallback.error;
                setHasEmailCol(false);
            } else {
                setHasEmailCol(true);
            }

            if (error) throw error;
            setEmployees((data || []) as Employee[]);
        } catch (e) {
            console.error(e);
            flash('Failed to load employees', false);
        } finally {
            setLoading(false);
        }
    }, [flash]);

    useEffect(() => { void load(); }, [load]);

    // ── Edit ───────────────────────────────────────────────────────────
    const startEdit = (e: Employee) => {
        setEditing(e.id);
        setForm({ name: e.name, phone: e.phone || '', band: e.band || 'executive', role: e.role || 'employee' });
    };

    const saveEdit = async () => {
        if (!editing || !form.name.trim()) return;
        setSaving(true);
        try {
            const sb = getSupabaseClient();
            const { error } = await sb.from('employees')
                .update({ name: form.name.trim(), phone: form.phone || null, band: form.band, role: form.role })
                .eq('id', editing);
            if (error) throw error;
            flash('Saved ✓', true);
            setEditing(null);
            await load();
        } catch (e) {
            console.error(e);
            flash('Update failed', false);
        } finally { setSaving(false); }
    };

    // ── Delete ─────────────────────────────────────────────────────────
    const doDelete = async (id: string) => {
        try {
            const sb = getSupabaseClient();
            const { error } = await sb.from('employees').delete().eq('id', id);
            if (error) throw error;
            flash('Removed ✓', true);
            setDeleting(null);
            await load();
        } catch (e) {
            console.error(e);
            flash('Delete failed — may have related data', false);
        }
    };

    // ── Filter ─────────────────────────────────────────────────────────
    const q = search.toLowerCase();
    const filtered = employees.filter(e => {
        const matchSearch = !q || e.name.toLowerCase().includes(q) || (e.email?.toLowerCase().includes(q)) || (e.phone?.includes(q));
        const matchBand = bandFilter === 'all' || e.band === bandFilter;
        return matchSearch && matchBand;
    });

    // ── UI ──────────────────────────────────────────────────────────────
    return (
        <div className="max-w-5xl mx-auto space-y-5">
            {toast && (
                <div className={`fixed top-4 right-4 z-50 flex items-center gap-2 px-4 py-2.5 rounded-lg shadow-lg text-sm font-medium ${toast.ok ? 'bg-green-600 text-white' : 'bg-red-600 text-white'}`}>
                    {toast.ok ? <Check className="w-4 h-4" /> : <AlertTriangle className="w-4 h-4" />} {toast.msg}
                </div>
            )}

            <div className="flex items-center justify-between">
                <div>
                    <h1 className="text-xl font-bold text-gray-900 flex items-center gap-2">
                        <Users className="w-5 h-5 text-primary-600" /> Employees
                    </h1>
                    <p className="text-gray-500 text-xs mt-0.5">
                        {employees.length} total · Band changes apply instantly to expense limits
                    </p>
                </div>
                <button onClick={() => load()} className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-white border border-gray-200 rounded-lg hover:bg-gray-50">
                    <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin' : ''}`} /> Refresh
                </button>
            </div>

            <div className="flex gap-2">
                <div className="relative flex-1">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
                    <input type="text" placeholder="Search name, email, or phone..." value={search} onChange={e => setSearch(e.target.value)}
                        className="w-full pl-9 pr-3 py-2 bg-white border border-gray-200 rounded-lg text-sm outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent" />
                </div>
                <div className="relative">
                    <select value={bandFilter} onChange={e => setBandFilter(e.target.value)}
                        className="appearance-none pl-3 pr-7 py-2 bg-white border border-gray-200 rounded-lg text-sm outline-none focus:ring-2 focus:ring-primary-500 cursor-pointer">
                        <option value="all">All Bands</option>
                        {BANDS.map(b => <option key={b.value} value={b.value}>{b.label}</option>)}
                    </select>
                    <ChevronDown className="absolute right-2 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-gray-400 pointer-events-none" />
                </div>
            </div>

            {loading ? (
                <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-500" /></div>
            ) : filtered.length === 0 ? (
                <div className="text-center py-16 bg-white rounded-xl border border-gray-200">
                    <Users className="w-10 h-10 mx-auto text-gray-300 mb-2" />
                    <p className="text-gray-500 text-sm">No employees found</p>
                </div>
            ) : (
                <div className="bg-white rounded-xl border border-gray-200 divide-y divide-gray-100">
                    {filtered.map(emp => {
                        const isEd = editing === emp.id;
                        const isDel = deleting === emp.id;

                        return (
                            <div key={emp.id} className={`px-5 py-4 ${isEd ? 'bg-primary-50/40' : 'hover:bg-gray-50'} transition-colors`}>
                                <div className="flex items-center gap-4">
                                    <div className="w-10 h-10 rounded-full bg-gradient-to-br from-primary-500 to-primary-600 flex items-center justify-center flex-shrink-0">
                                        <span className="text-white font-bold text-sm">{emp.name.charAt(0).toUpperCase()}</span>
                                    </div>

                                    <div className="flex-1 min-w-0">
                                        {isEd ? (
                                            <div className="flex flex-col sm:flex-row gap-2">
                                                <input type="text" value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} placeholder="Name"
                                                    className="px-2 py-1 border border-gray-300 rounded text-sm flex-1 focus:ring-1 focus:ring-primary-500 outline-none" />
                                                <input type="text" value={form.phone} onChange={e => setForm(f => ({ ...f, phone: e.target.value }))} placeholder="Phone"
                                                    className="px-2 py-1 border border-gray-300 rounded text-sm w-36 focus:ring-1 focus:ring-primary-500 outline-none" />
                                            </div>
                                        ) : (
                                            <>
                                                <div className="flex items-center gap-2">
                                                    <p className="font-medium text-gray-900 text-sm truncate">{emp.name}</p>
                                                    {emp.mobitraq_enrolled_at && (
                                                        <span className="px-1.5 py-0.5 rounded text-[10px] font-medium bg-green-100 text-green-700">📱 MobiTraq</span>
                                                    )}
                                                </div>
                                                <div className="flex items-center gap-3 mt-0.5">
                                                    {hasEmailCol && emp.email && (
                                                        <span className="text-xs text-gray-400 flex items-center gap-1 truncate">
                                                            <Mail className="w-3 h-3" /> {emp.email}
                                                        </span>
                                                    )}
                                                    {emp.phone && (
                                                        <span className="text-xs text-gray-400 flex items-center gap-1">
                                                            <Phone className="w-3 h-3" /> {emp.phone}
                                                        </span>
                                                    )}
                                                </div>
                                            </>
                                        )}
                                    </div>

                                    <div className="flex-shrink-0">
                                        {isEd ? (
                                            <select value={form.band} onChange={e => setForm(f => ({ ...f, band: e.target.value }))}
                                                className="px-2 py-1 border border-gray-300 rounded text-xs bg-white focus:ring-1 focus:ring-primary-500 outline-none">
                                                {BANDS.map(b => <option key={b.value} value={b.value}>{b.label}</option>)}
                                            </select>
                                        ) : (
                                            <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium ${BAND_COLORS[emp.band || ''] || 'bg-gray-100 text-gray-500'}`}>
                                                <Briefcase className="w-3 h-3" /> {getBandLabel(emp.band)}
                                            </span>
                                        )}
                                    </div>

                                    <div className="flex-shrink-0">
                                        {isEd ? (
                                            <select value={form.role} onChange={e => setForm(f => ({ ...f, role: e.target.value }))}
                                                className="px-2 py-1 border border-gray-300 rounded text-xs bg-white focus:ring-1 focus:ring-primary-500 outline-none">
                                                <option value="employee">Employee</option>
                                                <option value="admin">Admin</option>
                                            </select>
                                        ) : emp.role === 'admin' ? (
                                            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-700">
                                                <Shield className="w-3 h-3" /> Admin
                                            </span>
                                        ) : null}
                                    </div>

                                    <div className="flex items-center gap-1 flex-shrink-0">
                                        {isEd ? (
                                            <>
                                                <button onClick={saveEdit} disabled={saving}
                                                    className="px-2.5 py-1 text-xs font-medium text-white bg-primary-600 rounded hover:bg-primary-700 disabled:opacity-50">
                                                    <Save className="w-3.5 h-3.5 inline mr-0.5" /> {saving ? '...' : 'Save'}
                                                </button>
                                                <button onClick={() => setEditing(null)}
                                                    className="px-2.5 py-1 text-xs font-medium text-gray-600 bg-gray-100 rounded hover:bg-gray-200">
                                                    <X className="w-3.5 h-3.5" />
                                                </button>
                                            </>
                                        ) : isDel ? (
                                            <>
                                                <button onClick={() => doDelete(emp.id)}
                                                    className="px-2.5 py-1 text-xs font-medium text-white bg-red-600 rounded hover:bg-red-700">
                                                    <Trash2 className="w-3.5 h-3.5 inline mr-0.5" /> Yes
                                                </button>
                                                <button onClick={() => setDeleting(null)}
                                                    className="px-2.5 py-1 text-xs font-medium text-gray-600 bg-gray-100 rounded hover:bg-gray-200">No</button>
                                            </>
                                        ) : (
                                            <>
                                                <button onClick={() => startEdit(emp)} className="p-1.5 text-gray-400 hover:text-primary-600 hover:bg-primary-50 rounded" title="Edit">
                                                    <Pencil className="w-3.5 h-3.5" />
                                                </button>
                                                <button onClick={() => setDeleting(emp.id)} className="p-1.5 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded" title="Remove">
                                                    <Trash2 className="w-3.5 h-3.5" />
                                                </button>
                                            </>
                                        )}
                                    </div>
                                </div>

                                {isDel && (
                                    <p className="text-xs text-red-600 mt-2 ml-14">
                                        <AlertTriangle className="w-3 h-3 inline mr-1" />
                                        Remove <strong>{emp.name}</strong>? This cannot be undone.
                                    </p>
                                )}
                            </div>
                        );
                    })}
                </div>
            )}
        </div>
    );
}
