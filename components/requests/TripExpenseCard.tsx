'use client';

import React, { useEffect, useState } from 'react';
import { clsx } from 'clsx';
import { 
    Receipt, 
    MapPin, 
    Calendar, 
    IndianRupee, 
    AlertTriangle,
    CheckCircle2,
    XCircle,
    Paperclip,
    ExternalLink,
    Smartphone,
    Globe,
    Route,
    Fuel
} from 'lucide-react';
import { Card, Button, Badge, useToast, Spinner } from '@/components/ui';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { useAuth } from '@/lib/AuthContext';
import { notifyStatusChange } from '@/lib/notificationTrigger';

interface TripExpenseCardProps {
    requestId: string;
    onStatusChange?: () => void;
}

export function TripExpenseCard({ requestId, onStatusChange }: TripExpenseCardProps) {
    const { canManageRequests, user } = useAuth();
    const { success, error: showError } = useToast();
    
    const [loading, setLoading] = useState(true);
    const [updating, setUpdating] = useState(false);
    const [expense, setExpense] = useState<any>(null);
    const [receiptUrl, setReceiptUrl] = useState<string | null>(null);

    useEffect(() => {
        async function fetchExpense() {
            try {
                const supabase = getSupabaseClient();
                // Join trip_expenses with trips — now also fetches total_km for per-km limit calculation
                const { data, error } = await supabase
                    .from('trip_expenses')
                    .select('*, trips(from_location, to_location, created_at, employee_id, total_km, vehicle_type)')
                    .eq('id', requestId)
                    .single();
                
                if (error) {
                    if (error.code !== 'PGRST116') {
                        console.error('Error fetching trip expense:', error);
                    }
                    return;
                }
                setExpense(data);

                // Fetch signed URL for receipt if available
                if (data?.receipt_path) {
                    try {
                        const { data: urlData } = await supabase.storage
                            .from('benzmobitraq-receipts')
                            .createSignedUrl(data.receipt_path, 3600);
                        if (urlData?.signedUrl) setReceiptUrl(urlData.signedUrl);
                    } catch (e) {
                        console.warn('Could not get receipt URL:', e);
                    }
                }
            } catch (err) {
                console.error('Failed to load trip expense details', err);
            } finally {
                setLoading(false);
            }
        }
        fetchExpense();
    }, [requestId]);

    const handleApproval = async (newStatus: 'approved' | 'rejected') => {
        if (!expense || !canManageRequests) return;
        setUpdating(true);
        try {
            const supabase = getSupabaseClient();
            
            // 1. Update trip_expenses status
            const { error: expError } = await supabase
                .from('trip_expenses')
                .update({ status: newStatus })
                .eq('id', expense.id);
                
            if (expError) throw expError;

            // 2. Update requests status to 'closed'
            const { error: reqError } = await supabase
                .from('requests')
                .update({ status: 'closed' })
                .eq('id', expense.id);

            if (reqError) throw reqError;

            setExpense((prev: Record<string, unknown> | null) => prev ? ({ ...prev, status: newStatus }) : null);
            success('Expense Updated', `Expense has been ${newStatus}.`);
            
            // 3. Send Push Notification to the employee
            if (expense.trips?.employee_id && user?.email) {
                const prettyCat = expense.category.split('_').map((w: string) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
                await notifyStatusChange(
                    expense.trips.employee_id,
                    '',
                    expense.id,
                    `Trip Expense: ${prettyCat}`,
                    newStatus,
                    user.email
                );
            }

            if (onStatusChange) onStatusChange();
            
        } catch (err) {
            console.error('Failed to update expense', err);
            showError('Error', 'Could not update expense status');
        } finally {
            setUpdating(false);
        }
    };

    if (loading) {
        return (
            <div className="flex justify-center p-6 bg-white/50 backdrop-blur-sm rounded-2xl border border-gray-100">
                <Spinner size="sm" />
            </div>
        );
    }

    if (!expense) return null;

    const trip = expense.trips;
    const isPending = expense.status === 'pending';

    // Pretty category names
    const prettyCategory = expense.category.split('_').map((w: string) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');

    // Calculate effective limit for per_km categories
    const isPerKm = expense.category === 'fuel_car' || expense.category === 'fuel_bike';
    const ratePerKm = expense.limit_amount ?? 0;
    const tripKm = trip?.total_km ?? 0;
    const effectiveLimit = isPerKm && tripKm > 0 ? ratePerKm * tripKm : expense.limit_amount;
    const isOverLimit = effectiveLimit != null && effectiveLimit > 0 && expense.amount > effectiveLimit;

    // Detect if receipt is an image
    const isImageReceipt = expense.receipt_path && 
        /\.(jpg|jpeg|png|gif|webp)$/i.test(expense.receipt_path);

    return (
        <div className="mb-6 relative overflow-hidden rounded-2xl border border-gray-200/60 bg-gradient-to-br from-white to-gray-50 shadow-sm">
            {/* Top glassmorphism highlight */}
            <div className="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-blue-400 via-indigo-500 to-purple-500 opacity-80" />
            
            <div className="p-5 sm:p-6">
                <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-6">
                    <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-xl bg-blue-100/80 flex items-center justify-center text-blue-600 shadow-sm border border-blue-200/50">
                            <Receipt className="w-5 h-5" />
                        </div>
                        <div>
                            <div className="flex items-center gap-2">
                                <h3 className="text-lg font-bold text-gray-900 leading-tight">{prettyCategory}</h3>
                                {/* Source Badge */}
                                <span className="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-semibold rounded-full bg-indigo-50 text-indigo-600 border border-indigo-100">
                                    <Smartphone className="w-2.5 h-2.5" />
                                    MobiTraq
                                </span>
                            </div>
                            {/* Parse [From → To via Mode] format from mobile app */}
                            {expense.description && /^\[.+→.+via .+\]/.test(expense.description) ? (
                                <div className="flex items-center gap-2 mt-1">
                                    <span className="inline-flex items-center gap-1 text-xs font-medium text-gray-600 bg-gray-100 px-2 py-0.5 rounded-full">
                                        <MapPin className="w-3 h-3 text-blue-500" />
                                        {expense.description.match(/\[(.+?)→/)?.[1]?.trim()}
                                    </span>
                                    <span className="text-gray-400 text-xs">→</span>
                                    <span className="inline-flex items-center gap-1 text-xs font-medium text-gray-600 bg-gray-100 px-2 py-0.5 rounded-full">
                                        <MapPin className="w-3 h-3 text-green-500" />
                                        {expense.description.match(/→(.+?)via/)?.[1]?.trim()}
                                    </span>
                                    <span className="inline-flex items-center gap-1 text-xs font-medium text-blue-600 bg-blue-50 px-2 py-0.5 rounded-full">
                                        <Route className="w-3 h-3" />
                                        {expense.description.match(/via (.+?)\]/)?.[1]?.trim()}
                                    </span>
                                    {/* Show any extra notes after the bracket */}
                                    {expense.description.replace(/\[.+?\]\s*/, '').trim() && (
                                        <span className="text-xs text-gray-500 ml-1">
                                            {expense.description.replace(/\[.+?\]\s*/, '').trim()}
                                        </span>
                                    )}
                                </div>
                            ) : (
                                <p className="text-sm text-gray-500 font-medium">{expense.description || 'Expense Claim'}</p>
                            )}
                        </div>
                    </div>
                    
                    <Badge 
                        variant="default"
                        color={expense.status === 'approved' ? 'green' : expense.status === 'rejected' ? 'red' : 'yellow'}
                        className="text-sm px-3 py-1 shadow-sm"
                    >
                        {expense.status.toUpperCase()}
                    </Badge>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-x-8 gap-y-4 mb-6">
                    {/* Amount Block */}
                    <div className="flex items-start gap-4 p-4 rounded-xl bg-white border border-gray-100 shadow-sm transition-all hover:shadow-md">
                        <div className="p-2.5 bg-green-50 rounded-lg text-green-600 border border-green-100">
                            <IndianRupee className="w-5 h-5" />
                        </div>
                        <div>
                            <p className="text-sm text-gray-500 mb-1">Claim Amount</p>
                            <p className="text-xl font-bold text-gray-900 tracking-tight">₹{expense.amount.toLocaleString('en-IN')}</p>
                            <p className="text-sm font-semibold text-gray-600 mt-1 mb-2">Category: {prettyCategory}</p>
                            {isOverLimit ? (
                                <div className="space-y-1">
                                    <p className="inline-flex text-xs px-2 py-1 items-center gap-1 rounded bg-red-100 text-red-600 font-bold border border-red-200">
                                        <AlertTriangle className="w-3 h-3" /> OVER LIMIT
                                    </p>
                                    {isPerKm && tripKm > 0 ? (
                                        <p className="text-xs text-red-500 font-medium">
                                            ₹{ratePerKm}/km × {tripKm.toFixed(1)} km = ₹{effectiveLimit?.toFixed(0)} allowed
                                        </p>
                                    ) : (
                                        <p className="text-xs text-red-500 font-medium">Limit: ₹{effectiveLimit?.toLocaleString('en-IN')}</p>
                                    )}
                                </div>
                            ) : effectiveLimit != null && effectiveLimit > 0 ? (
                                <div className="space-y-1">
                                    <p className="inline-flex text-xs px-2 py-1 items-center gap-1 rounded bg-green-100 text-green-700 font-bold border border-green-200">
                                        <CheckCircle2 className="w-3 h-3" /> UNDER LIMIT
                                    </p>
                                    {isPerKm && tripKm > 0 ? (
                                        <p className="text-xs text-green-600 font-medium">
                                            ₹{ratePerKm}/km × {tripKm.toFixed(1)} km = ₹{effectiveLimit?.toFixed(0)} allowed
                                        </p>
                                    ) : (
                                        <p className="text-xs text-green-600 font-medium">Limit: ₹{effectiveLimit?.toLocaleString('en-IN')}</p>
                                    )}
                                </div>
                            ) : null}
                        </div>
                    </div>

                    {/* Trip Block */}
                    {trip && (
                        <div className="flex items-start gap-4 p-4 rounded-xl bg-white border border-gray-100 shadow-sm transition-all hover:shadow-md">
                            <div className="p-2.5 bg-indigo-50 rounded-lg text-indigo-600 border border-indigo-100">
                                <MapPin className="w-5 h-5" />
                            </div>
                            <div className="flex-1 min-w-0">
                                <p className="text-sm text-gray-500 mb-1">Associated Trip</p>
                                <p className="text-base font-semibold text-gray-900 truncate">
                                    {trip.from_location} → {trip.to_location}
                                </p>
                                <div className="flex items-center gap-3 mt-1">
                                    <p className="text-xs text-gray-400 flex items-center gap-1">
                                        <Calendar className="w-3 h-3" />
                                        {new Date(trip.created_at).toLocaleDateString()}
                                    </p>
                                    {tripKm > 0 && (
                                        <p className="text-xs text-blue-500 font-medium flex items-center gap-1">
                                            <Route className="w-3 h-3" />
                                            {tripKm.toFixed(1)} km
                                        </p>
                                    )}
                                    {trip.vehicle_type && (
                                        <p className="text-xs text-gray-400 flex items-center gap-1">
                                            <Fuel className="w-3 h-3" />
                                            {trip.vehicle_type.charAt(0).toUpperCase() + trip.vehicle_type.slice(1)}
                                        </p>
                                    )}
                                </div>
                            </div>
                        </div>
                    )}
                </div>

                {/* Inline Attachment Display */}
                {receiptUrl && (
                    <div className="mb-6">
                        <div className="flex items-center gap-2 mb-2">
                            <Paperclip className="w-4 h-4 text-gray-400" />
                            <p className="text-sm font-semibold text-gray-600">Attached Receipt</p>
                        </div>
                        {isImageReceipt ? (
                            <a href={receiptUrl} target="_blank" rel="noopener noreferrer" className="block">
                                <img 
                                    src={receiptUrl} 
                                    alt="Receipt" 
                                    className="max-w-sm max-h-64 rounded-xl border border-gray-200 shadow-sm hover:shadow-md transition-shadow cursor-pointer object-contain"
                                />
                            </a>
                        ) : (
                            <a 
                                href={receiptUrl} 
                                target="_blank" 
                                rel="noopener noreferrer"
                                className="inline-flex items-center gap-2 px-4 py-3 bg-gray-50 hover:bg-gray-100 text-gray-700 text-sm font-medium rounded-xl border border-gray-200 transition-colors"
                            >
                                <Paperclip className="w-4 h-4 text-gray-500" />
                                <span>View Document</span>
                                <ExternalLink className="w-3 h-3 text-gray-400 ml-1" />
                            </a>
                        )}
                    </div>
                )}
            </div>
        </div>
    );
}

export default TripExpenseCard;
