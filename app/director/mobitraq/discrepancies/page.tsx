'use client';

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { AlertTriangle, CheckCircle2, IndianRupee, Receipt, RefreshCw, Route, Save, Trash2, User } from 'lucide-react';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { useAuth } from '@/lib/AuthContext';

interface Employee {
    id: string;
    name: string;
    email: string | null;
    phone: string | null;
}

interface SessionRow {
    id: string;
    session_name: string | null;
    employee_id: string;
    start_time: string;
    end_time: string | null;
    total_km: number | null;
    status: string;
}

interface SessionRollup {
    session_id: string;
    distance_km: number | null;
    point_count: number | null;
}

interface SessionOption extends SessionRow {
    current_km: number;
    point_count: number;
}

interface LinkedExpense {
    requestId: string | null;
    claimId: string | null;
    itemId: string | null;
    amount: number | null;
    notes: string | null;
    description: string | null;
    status: string | null;
    category: string | null;
}

interface AdjustmentResult {
    old_km: number;
    corrected_km: number;
    delta_km: number;
    rate_per_km: number;
    amount: number;
    display_formula: string;
    affected_claim_count: number;
    affected_request_count: number;
    affected_trip_expense_count: number;
}

interface DuplicateExpenseGroup {
    group_key: string;
    employee_id: string;
    employee_name: string;
    employee_email: string | null;
    session_id: string;
    session_date: string | null;
    session_start_time: string | null;
    total_count: number;
    duplicate_count: number;
    kept_source: string;
    kept_expense_id: string;
    kept_amount: number;
    duplicate_sources: string[] | null;
    duplicate_expense_ids: string[];
    duplicate_request_ids: string[] | null;
    duplicate_amount_total: number;
    duplicate_rows: DuplicateExpenseRow[] | null;
    all_rows: DuplicateExpenseRow[] | null;
    first_created_at: string;
    last_created_at: string;
}

interface DuplicateExpenseRow {
    source: string;
    expense_id: string;
    request_id: string | null;
    amount: number;
    status: string | null;
    expense_date: string | null;
    created_at: string;
    kept?: boolean;
}

interface DuplicateResolveResult {
    removed_duplicate_count: number;
    deleted_expense_claim_count: number;
    deleted_trip_expense_count: number;
    deleted_request_count: number;
}

const getIstDateString = (date: Date = new Date()) =>
    date.toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });

const formatTime = (iso: string) =>
    new Date(iso).toLocaleTimeString('en-IN', {
        timeZone: 'Asia/Kolkata',
        hour: '2-digit',
        minute: '2-digit',
    });

const formatKm = (value: number) => value.toFixed(1);

const formatCurrency = (value: number) =>
    `Rs ${Number(value || 0).toLocaleString('en-IN', { maximumFractionDigits: 0 })}`;

const formatDateTime = (iso: string | null) => {
    if (!iso) return 'Time missing';
    return new Date(iso).toLocaleString('en-IN', {
        timeZone: 'Asia/Kolkata',
        day: '2-digit',
        month: 'short',
        hour: '2-digit',
        minute: '2-digit',
    });
};

const parseAmount = (value: unknown) => {
    const num = Number(value);
    return Number.isFinite(num) ? num : null;
};

export default function DistanceDiscrepancyPage() {
    const router = useRouter();
    const searchParams = useSearchParams();
    const dateParam = searchParams?.get('date');

    const { canManageRequests } = useAuth();
    const [employees, setEmployees] = useState<Employee[]>([]);
    const [selectedEmployee, setSelectedEmployee] = useState('');
    const [selectedDate, setSelectedDate] = useState<string>('');

    // Client-side init to prevent hydration mismatch
    useEffect(() => {
        setSelectedDate(dateParam || getIstDateString());
    }, [dateParam]);
    const [sessions, setSessions] = useState<SessionOption[]>([]);
    const [selectedSessionId, setSelectedSessionId] = useState('');
    const [linkedExpense, setLinkedExpense] = useState<LinkedExpense | null>(null);
    const [correctedKm, setCorrectedKm] = useState('');
    const [ratePerKm, setRatePerKm] = useState('7.50');
    const [reason, setReason] = useState('');
    const [loading, setLoading] = useState(true);
    const [sessionsLoading, setSessionsLoading] = useState(false);
    const [submitting, setSubmitting] = useState(false);
    const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);
    const [result, setResult] = useState<AdjustmentResult | null>(null);
    const [duplicateGroups, setDuplicateGroups] = useState<DuplicateExpenseGroup[]>([]);
    const [duplicatesLoading, setDuplicatesLoading] = useState(false);
    const [resolvingDuplicateKey, setResolvingDuplicateKey] = useState<string | null>(null);
    const [duplicateResult, setDuplicateResult] = useState<DuplicateResolveResult | null>(null);
    const [activePanel, setActivePanel] = useState<'correction' | 'duplicates'>('correction');

    const selectedSession = useMemo(
        () => sessions.find((session) => session.id === selectedSessionId) || null,
        [selectedSessionId, sessions]
    );

    const correctedValue = Number(correctedKm);
    const rateValue = Number(ratePerKm);
    const deltaKm = selectedSession && Number.isFinite(correctedValue)
        ? correctedValue - selectedSession.current_km
        : 0;

    const displayFormula = selectedSession && Number.isFinite(correctedValue)
        ? `${formatKm(selectedSession.current_km)}${deltaKm >= 0 ? '+' : '-'}${formatKm(Math.abs(deltaKm))}=${formatKm(correctedValue)}`
        : '';

    const previewAmount = Number.isFinite(correctedValue) && Number.isFinite(rateValue)
        ? correctedValue * rateValue
        : 0;

    const duplicatePendingCount = useMemo(
        () => duplicateGroups.reduce((sum, group) => sum + Number(group.duplicate_count || 0), 0),
        [duplicateGroups]
    );

    const flash = useCallback((ok: boolean, text: string) => {
        setMessage({ ok, text });
    }, []);

    const loadEmployees = useCallback(async () => {
        setLoading(true);
        try {
            const sb = getSupabaseClient();
            const { data, error } = await sb
                .from('employees')
                .select('id, name, email, phone')
                .order('name', { ascending: true });

            if (error) throw error;
            const rows = (data || []) as Employee[];
            setEmployees(rows);
            if (!selectedEmployee && rows.length > 0) {
                setSelectedEmployee(rows[0].id);
            }
        } catch (error) {
            console.error(error);
            flash(false, 'Could not load MobiTraq employees.');
        } finally {
            setLoading(false);
        }
    }, [flash, selectedEmployee]);

    const loadSessions = useCallback(async () => {
        if (!selectedEmployee || !selectedDate) return;

        setSessionsLoading(true);
        setSelectedSessionId('');
        setLinkedExpense(null);
        setCorrectedKm('');
        setResult(null);

        try {
            const sb = getSupabaseClient();
            const startOfDay = `${selectedDate}T00:00:00+05:30`;
            const endOfDay = `${selectedDate}T23:59:59+05:30`;

            const { data: sessionRows, error: sessionError } = await sb
                .from('shift_sessions')
                .select('id, session_name, employee_id, start_time, end_time, total_km, final_km, status')
                .eq('employee_id', selectedEmployee)
                .gte('start_time', startOfDay)
                .lte('start_time', endOfDay)
                .order('start_time', { ascending: true });

            if (sessionError) throw sessionError;

            const rows = (sessionRows || []) as SessionRow[];
            const ids = rows.map((row) => row.id);
            let rollups: SessionRollup[] = [];

            if (ids.length > 0) {
                // session_rollups stays for the point_count audit signal
                // (raw haversine distance is intentionally retained on
                // this page so admins can SEE the discrepancy that drove
                // them here). The displayed "current_km" however reads
                // from shift_sessions.final_km — the locked billing total
                // — per Stage 1 of the distance rewrite.
                const { data: rollupRows, error: rollupError } = await sb
                    .from('session_rollups')
                    .select('session_id, distance_km, point_count')
                    .in('session_id', ids);

                if (rollupError) throw rollupError;
                rollups = (rollupRows || []) as SessionRollup[];
            }

            const options = rows.map((row) => {
                const rollup = rollups.find((item) => item.session_id === row.id);
                // Billing-truthful number: final_km if present, else legacy total_km.
                // We do NOT fall back to rollup.distance_km for current_km.
                const finalKm = Number((row as any).final_km ?? 0);
                const totalKm = Number(row.total_km ?? 0);
                const billed = finalKm > 0 ? finalKm : totalKm;
                return {
                    ...row,
                    current_km: billed,
                    point_count: Number(rollup?.point_count ?? 0),
                };
            });

            setSessions(options);
            if (options.length > 0) {
                setSelectedSessionId(options[0].id);
                setCorrectedKm(formatKm(options[0].current_km));
            }
        } catch (error) {
            console.error(error);
            flash(false, 'Could not load sessions for this employee/date.');
        } finally {
            setSessionsLoading(false);
        }
    }, [flash, selectedDate, selectedEmployee]);

    const loadDuplicateExpenses = useCallback(async () => {
        if (!canManageRequests) return;

        setDuplicatesLoading(true);
        try {
            const sb = getSupabaseClient();
            const { data, error } = await sb.rpc('get_mobitraq_duplicate_session_expenses');
            if (error) throw error;

            setDuplicateGroups(((data || []) as DuplicateExpenseGroup[]).map((group) => ({
                ...group,
                duplicate_expense_ids: group.duplicate_expense_ids || [],
                duplicate_sources: group.duplicate_sources || [],
                duplicate_request_ids: group.duplicate_request_ids || [],
                duplicate_rows: (group.duplicate_rows || []).map((row) => ({
                    ...row,
                    amount: Number(row.amount || 0),
                })),
                all_rows: (group.all_rows || []).map((row) => ({
                    ...row,
                    amount: Number(row.amount || 0),
                })),
                duplicate_count: Number(group.duplicate_count || 0),
                total_count: Number(group.total_count || 0),
                kept_amount: Number(group.kept_amount || 0),
                duplicate_amount_total: Number(group.duplicate_amount_total || 0),
            })));
        } catch (error: any) {
            console.error(error);
            flash(false, error?.message || 'Could not load duplicate session expenses.');
        } finally {
            setDuplicatesLoading(false);
        }
    }, [canManageRequests, flash]);

    const loadLinkedExpense = useCallback(async () => {
        if (!selectedSession) {
            setLinkedExpense(null);
            return;
        }

        try {
            const sb = getSupabaseClient();
            const sessionId = selectedSession.id;

            const [{ data: requests }, { data: claims }] = await Promise.all([
                sb
                    .from('requests')
                    .select('id, amount, status, description')
                    .eq('created_by', selectedSession.employee_id)
                    .ilike('description', `%${sessionId}%`)
                    .limit(1),
                sb
                    .from('expense_claims')
                    .select('id, total_amount, status, notes')
                    .eq('employee_id', selectedSession.employee_id)
                    .ilike('notes', `%${sessionId}%`)
                    .limit(1),
            ]);

            const request = (requests || [])[0] as any;
            const claim = (claims || [])[0] as any;
            let item: any = null;

            if (claim?.id) {
                const { data: items } = await sb
                    .from('expense_items')
                    .select('id, claim_id, category, amount, description')
                    .eq('claim_id', claim.id)
                    .ilike('description', `%${sessionId}%`)
                    .limit(1);
                item = (items || [])[0];
            }

            const amount = parseAmount(item?.amount ?? claim?.total_amount ?? request?.amount);
            const detectedRate = amount && selectedSession.current_km > 0
                ? amount / selectedSession.current_km
                : null;

            if (detectedRate && Number.isFinite(detectedRate)) {
                setRatePerKm(detectedRate.toFixed(2));
            }

            setLinkedExpense({
                requestId: request?.id || null,
                claimId: claim?.id || null,
                itemId: item?.id || null,
                amount,
                notes: claim?.notes || null,
                description: item?.description || request?.description || null,
                status: claim?.status || request?.status || null,
                category: item?.category || null,
            });
        } catch (error) {
            console.error(error);
            setLinkedExpense(null);
        }
    }, [selectedSession]);

    useEffect(() => {
        void loadEmployees();
    }, [loadEmployees]);

    useEffect(() => {
        void loadDuplicateExpenses();
    }, [loadDuplicateExpenses]);

    useEffect(() => {
        void loadSessions();
    }, [loadSessions]);

    useEffect(() => {
        if (selectedSession) {
            setCorrectedKm(formatKm(selectedSession.current_km));
            void loadLinkedExpense();
        }
    }, [loadLinkedExpense, selectedSession]);

    const applyAdjustment = async () => {
        if (!selectedSession || !Number.isFinite(correctedValue) || correctedValue < 0) {
            flash(false, 'Enter a valid corrected kilometer value.');
            return;
        }

        if (Math.abs(deltaKm) < 0.01) {
            flash(false, 'Corrected kilometers are the same as the current value.');
            return;
        }

        if (!reason.trim()) {
            flash(false, 'Add a short reason before saving the correction.');
            return;
        }

        setSubmitting(true);
        setResult(null);

        try {
            const sb = getSupabaseClient();
            const { data, error } = await sb.rpc('apply_mobitraq_distance_discrepancy', {
                p_session_id: selectedSession.id,
                p_corrected_km: correctedValue,
                p_display_formula: displayFormula,
                p_rate_per_km: Number.isFinite(rateValue) && rateValue > 0 ? rateValue : null,
                p_reason: reason.trim(),
            });

            if (error) throw error;

            setResult(data as AdjustmentResult);
            flash(true, 'Distance discrepancy updated across session, rollups, and linked expense rows.');
            setSessions((current) =>
                current.map((session) =>
                    session.id === selectedSession.id
                        ? { ...session, current_km: correctedValue }
                        : session
                )
            );
        } catch (error: any) {
            console.error(error);
            flash(false, error?.message || 'Could not apply the discrepancy correction.');
        } finally {
            setSubmitting(false);
        }
    };

    const resolveDuplicateExpenses = async (group: DuplicateExpenseGroup) => {
        if (!group.session_id || group.duplicate_expense_ids.length === 0) {
            flash(false, 'No duplicate expense rows were selected for cleanup.');
            return;
        }

        setResolvingDuplicateKey(group.group_key);
        setDuplicateResult(null);

        try {
            const sb = getSupabaseClient();
            const { data, error } = await sb.rpc('resolve_mobitraq_duplicate_session_expenses', {
                p_session_id: group.session_id,
                p_duplicate_expense_ids: group.duplicate_expense_ids,
                p_reason: 'Duplicate post-session expense cleanup from discrepancies page',
            });

            if (error) throw error;

            setDuplicateResult(data as DuplicateResolveResult);
            flash(true, `Removed ${group.duplicate_count} duplicate session expense${group.duplicate_count === 1 ? '' : 's'} for ${group.employee_name}.`);
            await loadDuplicateExpenses();
            await loadSessions();
        } catch (error: any) {
            console.error(error);
            flash(false, error?.message || 'Could not remove duplicate session expenses.');
        } finally {
            setResolvingDuplicateKey(null);
        }
    };

    if (!canManageRequests) {
        return (
            <div className="rounded-2xl border border-red-200 bg-red-50 p-6 text-red-700">
                Admin or director access is required.
            </div>
        );
    }

    return (
        <div className="space-y-6 text-slate-900">
            <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
                <div>
                    <div className="flex flex-wrap items-center gap-3">
                        <h1 className="text-2xl font-bold text-slate-900">Distance Discrepancy</h1>
                        {duplicatePendingCount > 0 && (
                            <span className="inline-flex h-7 min-w-7 items-center justify-center rounded-full bg-red-600 px-2 text-xs font-bold text-white">
                                {duplicatePendingCount}
                            </span>
                        )}
                    </div>
                    <p className="text-sm text-slate-500">
                        Correct session kilometers and clear duplicate post-session expenses from one place.
                    </p>
                </div>
                <div className="flex flex-wrap gap-2">
                    <button
                        onClick={() => {
                            setActivePanel('duplicates');
                            void loadDuplicateExpenses();
                        }}
                        disabled={duplicatesLoading}
                        className={`inline-flex items-center justify-center gap-2 rounded-lg border px-4 py-2 text-sm font-semibold shadow-sm disabled:opacity-60 ${activePanel === 'duplicates' ? 'border-red-600 bg-red-600 text-white' : 'border-red-200 bg-white text-red-700 hover:bg-red-50'}`}
                    >
                        <RefreshCw className={`h-4 w-4 ${duplicatesLoading ? 'animate-spin' : ''}`} />
                        Duplicates
                        {duplicatePendingCount > 0 && (
                            <span className={`ml-1 inline-flex h-5 min-w-5 items-center justify-center rounded-full px-1.5 text-[10px] font-bold ${activePanel === 'duplicates' ? 'bg-white text-red-700' : 'bg-red-600 text-white'}`}>
                                {duplicatePendingCount}
                            </span>
                        )}
                    </button>
                    <button
                        onClick={() => {
                            setActivePanel('correction');
                            void loadSessions();
                        }}
                        disabled={sessionsLoading || !selectedEmployee}
                        className={`inline-flex items-center justify-center gap-2 rounded-lg border px-4 py-2 text-sm font-semibold shadow-sm disabled:opacity-60 ${activePanel === 'correction' ? 'border-blue-600 bg-blue-600 text-white' : 'border-slate-200 bg-white text-slate-700 hover:bg-slate-50'}`}
                    >
                        <RefreshCw className={`h-4 w-4 ${sessionsLoading ? 'animate-spin' : ''}`} />
                        Correction
                    </button>
                </div>
            </div>

            {message && (
                <div className={`rounded-xl border px-4 py-3 text-sm ${message.ok ? 'border-green-200 bg-green-50 text-green-700' : 'border-red-200 bg-red-50 text-red-700'}`}>
                    {message.text}
                </div>
            )}

            <div className="grid grid-cols-1 gap-6 xl:grid-cols-12">
                <div className={activePanel === 'duplicates' ? 'xl:col-span-12' : 'flex flex-col gap-4 xl:col-span-4'}>
                    <section className={activePanel === 'duplicates' ? 'rounded-xl border border-slate-200 bg-white p-4 shadow-sm' : 'hidden'}>
                        <div className="mb-4 flex items-center justify-between gap-3">
                            <div className="flex items-center gap-2">
                                <Receipt className="h-5 w-5 text-red-600" />
                                <h2 className="font-semibold">Duplicate Session Expenses</h2>
                            </div>
                            <div className="flex items-center gap-2">
                                {duplicatePendingCount > 0 && (
                                    <span className="inline-flex h-6 min-w-6 items-center justify-center rounded-full bg-red-600 px-2 text-xs font-bold text-white">
                                        {duplicatePendingCount}
                                    </span>
                                )}
                                <button
                                    type="button"
                                    onClick={() => setActivePanel('correction')}
                                    className="rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 hover:bg-slate-50"
                                >
                                    Back
                                </button>
                            </div>
                        </div>
                        <p className="mb-3 text-xs text-slate-500">
                            Flagged only when the same employee, same session ID, and same amount were lodged more than once.
                        </p>

                        {duplicatesLoading ? (
                            <div className="rounded-lg border border-slate-100 bg-slate-50 px-3 py-6 text-center text-sm text-slate-500">
                                Checking duplicate session expenses...
                            </div>
                        ) : duplicateGroups.length === 0 ? (
                            <div className="rounded-lg border border-slate-100 bg-slate-50 px-3 py-6 text-center text-sm text-slate-500">
                                No duplicate session expenses pending.
                            </div>
                        ) : (
                            <div className="grid grid-cols-1 gap-3 lg:grid-cols-2 2xl:grid-cols-3">
                                {duplicateGroups.map((group) => (
                                    <div key={group.group_key} className="rounded-lg border border-slate-200 bg-slate-50 p-3">
                                        <div className="flex items-start justify-between gap-3">
                                            <div className="min-w-0">
                                                <div className="truncate font-semibold text-slate-900">{group.employee_name}</div>
                                                <div className="text-xs text-slate-600">
                                                    {group.session_date || 'Session date missing'} - {group.total_count} same-value rows, {group.duplicate_count} duplicate
                                                </div>
                                            </div>
                                            <span className="rounded-full bg-red-600 px-2 py-0.5 text-xs font-bold text-white">
                                                {group.duplicate_count}
                                            </span>
                                        </div>
                                        <div className="mt-3 grid grid-cols-2 gap-2 text-xs">
                                            <div className="rounded-md border border-green-100 bg-white p-2">
                                                <div className="text-slate-500">Original kept</div>
                                                <div className="font-semibold text-slate-900">{formatCurrency(group.kept_amount)}</div>
                                            </div>
                                            <div className="rounded-md border border-red-100 bg-white p-2">
                                                <div className="text-slate-500">Extra to remove</div>
                                                <div className="font-semibold text-red-700">{formatCurrency(group.duplicate_amount_total)}</div>
                                            </div>
                                        </div>
                                        <div className="mt-2 break-all font-mono text-[10px] text-slate-500">
                                            Session {group.session_id}
                                        </div>
                                        <div className="mt-3 space-y-2">
                                            {(group.all_rows || []).map((row) => (
                                                <div
                                                    key={`${row.source}-${row.expense_id}`}
                                                    className={`rounded-md border bg-white p-2 text-xs ${row.kept ? 'border-green-200' : 'border-red-200'}`}
                                                >
                                                    <div className="flex items-center justify-between gap-2">
                                                        <span className={`font-semibold ${row.kept ? 'text-green-700' : 'text-red-700'}`}>
                                                            {row.kept ? 'Original kept' : 'Duplicate to remove'}
                                                        </span>
                                                        <span className="font-bold text-slate-900">{formatCurrency(row.amount)}</span>
                                                    </div>
                                                    <div className="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-slate-500">
                                                        <span>{row.source === 'trip_expense' ? 'Trip Expense' : 'Expense Claim'}</span>
                                                        <span>{formatDateTime(row.created_at)}</span>
                                                        <span>{row.status || 'status missing'}</span>
                                                    </div>
                                                    <div className="mt-1 break-all font-mono text-[10px] text-slate-400">
                                                        {row.expense_id}
                                                    </div>
                                                </div>
                                            ))}
                                        </div>
                                        <div className="mt-3 flex gap-2">
                                            <button
                                                type="button"
                                                onClick={() => {
                                                    setSelectedEmployee(group.employee_id);
                                                    if (group.session_date) {
                                                        setSelectedDate(group.session_date);
                                                        router.replace(`?date=${group.session_date}`);
                                                    }
                                                }}
                                                className="flex-1 rounded-lg border border-slate-200 bg-white px-3 py-2 text-xs font-semibold text-slate-700 hover:bg-slate-50"
                                            >
                                                View Session
                                            </button>
                                            <button
                                                type="button"
                                                onClick={() => resolveDuplicateExpenses(group)}
                                                disabled={resolvingDuplicateKey === group.group_key}
                                                className="inline-flex flex-1 items-center justify-center gap-2 rounded-lg bg-red-600 px-3 py-2 text-xs font-semibold text-white hover:bg-red-700 disabled:opacity-60"
                                            >
                                                <Trash2 className="h-3.5 w-3.5" />
                                                {resolvingDuplicateKey === group.group_key ? 'Removing...' : 'Remove Duplicate'}
                                            </button>
                                        </div>
                                    </div>
                                ))}
                            </div>
                        )}

                        {duplicateResult && (
                            <div className="mt-3 rounded-xl border border-green-200 bg-green-50 p-3 text-xs text-green-800">
                                Removed {duplicateResult.removed_duplicate_count} duplicate expense row(s), {duplicateResult.deleted_request_count} mirrored request row(s).
                            </div>
                        )}
                    </section>

                    <section className={activePanel === 'correction' ? 'rounded-2xl border border-slate-200 bg-white p-5 shadow-sm' : 'hidden'}>
                    <div className="mb-4 flex items-center gap-2">
                        <User className="h-5 w-5 text-blue-600" />
                        <h2 className="font-semibold">Select Employee & Date</h2>
                    </div>

                    <div className="space-y-4">
                        <label className="block">
                            <span className="mb-1 block text-xs font-semibold uppercase tracking-wide text-slate-500">Employee</span>
                            <select
                                value={selectedEmployee}
                                onChange={(event) => setSelectedEmployee(event.target.value)}
                                className="w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-100"
                                disabled={loading}
                            >
                                {employees.map((employee) => (
                                    <option key={employee.id} value={employee.id}>
                                        {employee.name} {employee.email ? `- ${employee.email}` : ''}
                                    </option>
                                ))}
                            </select>
                        </label>

                        <label className="block">
                            <span className="mb-1 block text-xs font-semibold uppercase tracking-wide text-slate-500">Session Date</span>
                            <input
                                type="date"
                                value={selectedDate}
                                onChange={(event) => {
                                    const newDate = event.target.value;
                                    setSelectedDate(newDate);
                                    const params = new URLSearchParams(searchParams.toString());
                                    if (newDate) {
                                        params.set('date', newDate);
                                    } else {
                                        params.delete('date');
                                    }
                                    router.replace(`?${params.toString()}`);
                                }}
                                className="w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-100"
                            />
                        </label>

                        <div className="rounded-xl border border-slate-100 bg-slate-50 p-3">
                            <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">Sessions</div>
                            {sessionsLoading ? (
                                <div className="py-6 text-center text-sm text-slate-500">Loading sessions...</div>
                            ) : sessions.length === 0 ? (
                                <div className="py-6 text-center text-sm text-slate-500">No sessions found for this date.</div>
                            ) : (
                                <div className="space-y-2">
                                    {sessions.map((session, index) => (
                                        <button
                                            key={session.id}
                                            type="button"
                                            onClick={() => setSelectedSessionId(session.id)}
                                            className={`w-full rounded-lg border px-3 py-3 text-left transition ${selectedSessionId === session.id ? 'border-blue-400 bg-blue-50' : 'border-slate-200 bg-white hover:border-blue-200'}`}
                                        >
                                            <div className="flex items-center justify-between gap-3">
                                                <div>
                                                    <div className="font-semibold text-slate-900">
                                                        #{index + 1} {session.session_name || 'Regular Session'}
                                                    </div>
                                                    <div className="text-xs text-slate-500">
                                                        {formatTime(session.start_time)} - {session.end_time ? formatTime(session.end_time) : 'Active'}
                                                    </div>
                                                </div>
                                                <div className="text-right">
                                                    <div className="font-bold text-blue-700">{formatKm(session.current_km)} km</div>
                                                    <div className="text-xs text-slate-500">{session.point_count} points</div>
                                                </div>
                                            </div>
                                        </button>
                                    ))}
                                </div>
                            )}
                        </div>
                    </div>
                    </section>
                </div>

                <section className={activePanel === 'correction' ? 'xl:col-span-8 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm' : 'hidden'}>
                    <div className="mb-5 flex items-center gap-2">
                        <Route className="h-5 w-5 text-blue-600" />
                        <h2 className="font-semibold">Correction</h2>
                    </div>

                    {!selectedSession ? (
                        <div className="rounded-xl border border-dashed border-slate-200 p-8 text-center text-slate-500">
                            Select a session to adjust.
                        </div>
                    ) : (
                        <div className="space-y-5">
                            <div className="grid grid-cols-1 gap-3 md:grid-cols-4">
                                <div className="rounded-xl border border-slate-100 bg-slate-50 p-4">
                                    <div className="text-xs font-semibold uppercase text-slate-500">Current</div>
                                    <div className="mt-1 text-2xl font-bold">{formatKm(selectedSession.current_km)} km</div>
                                </div>
                                <div className="rounded-xl border border-slate-100 bg-slate-50 p-4">
                                    <div className="text-xs font-semibold uppercase text-slate-500">Corrected</div>
                                    <div className="mt-1 text-2xl font-bold">{Number.isFinite(correctedValue) ? formatKm(correctedValue) : '0.0'} km</div>
                                </div>
                                <div className="rounded-xl border border-slate-100 bg-slate-50 p-4">
                                    <div className="text-xs font-semibold uppercase text-slate-500">Delta</div>
                                    <div className={`mt-1 text-2xl font-bold ${deltaKm >= 0 ? 'text-green-700' : 'text-red-700'}`}>
                                        {deltaKm >= 0 ? '+' : ''}{formatKm(deltaKm)} km
                                    </div>
                                </div>
                                <div className="rounded-xl border border-slate-100 bg-slate-50 p-4">
                                    <div className="text-xs font-semibold uppercase text-slate-500">Fuel Amount</div>
                                    <div className="mt-1 flex items-center text-2xl font-bold">
                                        <IndianRupee className="h-5 w-5" />
                                        {previewAmount.toFixed(2)}
                                    </div>
                                </div>
                            </div>

                            <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
                                <label className="block">
                                    <span className="mb-1 block text-xs font-semibold uppercase tracking-wide text-slate-500">Corrected Kilometers</span>
                                    <input
                                        type="number"
                                        min="0"
                                        step="0.1"
                                        value={correctedKm}
                                        onChange={(event) => setCorrectedKm(event.target.value)}
                                        className="w-full rounded-lg border border-slate-200 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-100"
                                    />
                                </label>
                                <label className="block">
                                    <span className="mb-1 block text-xs font-semibold uppercase tracking-wide text-slate-500">Rate Per Km</span>
                                    <input
                                        type="number"
                                        min="0"
                                        step="0.01"
                                        value={ratePerKm}
                                        onChange={(event) => setRatePerKm(event.target.value)}
                                        className="w-full rounded-lg border border-slate-200 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-100"
                                    />
                                </label>
                            </div>

                            <label className="block">
                                <span className="mb-1 block text-xs font-semibold uppercase tracking-wide text-slate-500">Reason</span>
                                <textarea
                                    value={reason}
                                    onChange={(event) => setReason(event.target.value)}
                                    rows={3}
                                    placeholder="Example: Phone switched off during return route; corrected from manager-approved route evidence."
                                    className="w-full rounded-lg border border-slate-200 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-100"
                                />
                            </label>

                            <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
                                <div className="mb-1 flex items-center gap-2 font-semibold">
                                    <AlertTriangle className="h-4 w-4" />
                                    Preview before save
                                </div>
                                The visible formula will be saved as <span className="font-mono font-semibold">{displayFormula || '0.0+0.0=0.0'}</span>. This correction updates the session row, session rollup, daily rollup, matching expense claim/item, matching request, and trip expense if one is linked.
                            </div>

                            {linkedExpense && (
                                <div className="rounded-xl border border-slate-200 bg-slate-50 p-4 text-sm">
                                    <div className="mb-2 font-semibold text-slate-800">Linked Expense</div>
                                    <div className="grid grid-cols-1 gap-2 md:grid-cols-3">
                                        <div>
                                            <div className="text-xs uppercase text-slate-500">Claim</div>
                                            <div className="font-mono text-xs">{linkedExpense.claimId || 'Not found'}</div>
                                        </div>
                                        <div>
                                            <div className="text-xs uppercase text-slate-500">Request</div>
                                            <div className="font-mono text-xs">{linkedExpense.requestId || 'Not found'}</div>
                                        </div>
                                        <div>
                                            <div className="text-xs uppercase text-slate-500">Current Amount</div>
                                            <div className="font-semibold">{linkedExpense.amount != null ? `₹${linkedExpense.amount.toFixed(2)}` : 'Not found'}</div>
                                        </div>
                                    </div>
                                    {linkedExpense.description && (
                                        <div className="mt-3 text-xs text-slate-500">{linkedExpense.description}</div>
                                    )}
                                </div>
                            )}

                            <button
                                onClick={applyAdjustment}
                                disabled={submitting}
                                className="inline-flex items-center justify-center gap-2 rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-blue-700 disabled:opacity-60"
                            >
                                <Save className="h-4 w-4" />
                                {submitting ? 'Applying...' : 'Apply Correction'}
                            </button>

                            {result && (
                                <div className="rounded-xl border border-green-200 bg-green-50 p-4 text-sm text-green-800">
                                    <div className="mb-2 flex items-center gap-2 font-semibold">
                                        <CheckCircle2 className="h-4 w-4" />
                                        Correction saved
                                    </div>
                                    {result.display_formula} km at ₹{Number(result.rate_per_km).toFixed(2)}/km = ₹{Number(result.amount).toFixed(2)}. Updated {result.affected_claim_count} claim, {result.affected_request_count} request, and {result.affected_trip_expense_count} trip expense rows.
                                </div>
                            )}
                        </div>
                    )}
                </section>
            </div>
        </div>
    );
}
