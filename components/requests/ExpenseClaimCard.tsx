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
    Fuel,
    Utensils,
    Home,
    CarFront,
    Coffee
} from 'lucide-react';
import { Card, Button, Badge, useToast, Spinner } from '@/components/ui';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { useAuth } from '@/lib/AuthContext';
import { notifyStatusChange } from '@/lib/notificationTrigger';

interface ExpenseClaimCardProps {
    requestId: string;
    onStatusChange?: () => void;
    onCategoriesLoaded?: (categories: string[]) => void;
}

export function ExpenseClaimCard({ requestId, onStatusChange, onCategoriesLoaded }: ExpenseClaimCardProps) {
    const { canManageRequests, user } = useAuth();
    const { success, error: showError } = useToast();
    
    const [loading, setLoading] = useState(true);
    const [updating, setUpdating] = useState(false);
    const [claim, setClaim] = useState<any>(null);
    const [items, setItems] = useState<any[]>([]);
    const [attachments, setAttachments] = useState<any[]>([]);

    useEffect(() => {
        async function fetchData() {
            try {
                const supabase = getSupabaseClient();
                
                // 1. Fetch the claim
                const { data: claimData, error: claimError } = await supabase
                    .from('expense_claims')
                    .select('*')
                    .eq('id', requestId)
                    .single();
                
                if (claimError) {
                    if (claimError.code !== 'PGRST116') {
                        console.error('Error fetching expense claim:', claimError);
                    }
                    return;
                }
                setClaim(claimData);

                // 2. Fetch the items
                const { data: itemsData, error: itemsError } = await supabase
                    .from('expense_items')
                    .select('*')
                    .eq('claim_id', requestId)
                    .order('created_at', { ascending: true });

                if (itemsError) {
                    console.error('Error fetching expense items:', itemsError);
                } else {
                    setItems(itemsData || []);
                    if (onCategoriesLoaded && itemsData && itemsData.length > 0) {
                        const uniqueCats = Array.from(new Set(itemsData.map((item: any) => item.category)));
                        const prettyCats = uniqueCats.map((cat: string) => getCategoryDisplayName(cat));
                        onCategoriesLoaded(prettyCats);
                    }
                }

                // 3. Fetch the attachments (receipts)
                const { data: attachmentsData, error: attachError } = await supabase
                    .from('expense_claim_attachments')
                    .select('*')
                    .eq('claim_id', requestId)
                    .order('uploaded_at', { ascending: true });

                if (attachError) {
                    console.error('Error fetching expense attachments:', attachError);
                } else if (attachmentsData && attachmentsData.length > 0) {
                    // Generate signed URLs for all attachments
                    const withUrls = await Promise.all(attachmentsData.map(async (att) => {
                        try {
                            const { data: urlData } = await supabase.storage
                                .from(att.bucket)
                                .createSignedUrl(att.path, 3600);
                            return { ...att, url: urlData?.signedUrl };
                        } catch (e) {
                            console.warn('Could not get URL for attachment:', att.path, e);
                            return att;
                        }
                    }));
                    setAttachments(withUrls);
                }

            } catch (err) {
                console.error('Failed to load expense claim details', err);
            } finally {
                setLoading(false);
            }
        }
        fetchData();
    }, [requestId]);

    const handleApproval = async (newStatus: 'approved' | 'rejected') => {
        if (!claim || !canManageRequests) return;
        setUpdating(true);
        try {
            const supabase = getSupabaseClient();
            
            // 1. Update expense_claims status
            const { error: expError } = await supabase
                .from('expense_claims')
                .update({ status: newStatus })
                .eq('id', claim.id);
                
            if (expError) throw expError;

            // 2. Update requests status to 'closed'
            const { error: reqError } = await supabase
                .from('requests')
                .update({ status: 'closed' })
                .eq('id', claim.id);

            if (reqError) throw reqError;

            setClaim((prev: Record<string, unknown> | null) => prev ? ({ ...prev, status: newStatus }) : null);
            success('Claim Updated', `Expense claim has been ${newStatus}.`);
            
            // 3. Send Push Notification to the employee
            if (claim.employee_id && user?.email) {
                await notifyStatusChange(
                    claim.employee_id,
                    '',
                    claim.id,
                    `Expense Claim Update`,
                    newStatus,
                    user.email
                );
            }

            if (onStatusChange) onStatusChange();
            
        } catch (err) {
            console.error('Failed to update expense claim', err);
            showError('Error', 'Could not update expense claim status');
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

    if (!claim) return null;

    const isPending = claim.status === 'submitted' || claim.status === 'pending';

    const getCategoryIcon = (category: string) => {
        switch (category.toLowerCase()) {
            case 'fuel':
            case 'fuel_car':
            case 'fuel_bike':
                return <Fuel className="w-4 h-4" />;
            case 'food':
            case 'food_da':
                return <Utensils className="w-4 h-4" />;
            case 'accommodation':
            case 'hotel':
                return <Home className="w-4 h-4" />;
            case 'travel':
            case 'local_conveyance':
            case 'local_travel':
            case 'travel_allowance':
                return <CarFront className="w-4 h-4" />;
            case 'parking':
            case 'toll':
                return <Route className="w-4 h-4" />;
            case 'laundry':
                return <Receipt className="w-4 h-4" />;
            case 'petty_cash':
            case 'advance_request':
            case 'salary_payroll_query':
            case 'vendor_payment_status':
            case 'invoice_query':
            case 'expense_reimbursement':
                return <IndianRupee className="w-4 h-4" />;
            case 'stationary':
            case 'delivery_challan':
            case 'purchase_order_query':
                return <Paperclip className="w-4 h-4" />;
            default:
                return <Receipt className="w-4 h-4" />;
        }
    };

    const getCategoryColor = (category: string) => {
        switch (category.toLowerCase()) {
            case 'fuel':
            case 'fuel_car':
            case 'fuel_bike':
                return 'bg-orange-50 text-orange-600 border-orange-100';
            case 'food':
            case 'food_da':
                return 'bg-emerald-50 text-emerald-600 border-emerald-100';
            case 'accommodation':
            case 'hotel':
                return 'bg-indigo-50 text-indigo-600 border-indigo-100';
            case 'travel':
            case 'local_conveyance':
            case 'local_travel':
            case 'travel_allowance':
                return 'bg-blue-50 text-blue-600 border-blue-100';
            case 'petty_cash':
            case 'advance_request':
            case 'salary_payroll_query':
            case 'expense_reimbursement':
                return 'bg-purple-50 text-purple-600 border-purple-100';
            default:
                return 'bg-gray-50 text-gray-600 border-gray-100';
        }
    };

    const getCategoryDisplayName = (category: string) => {
        const catMap: Record<string, string> = {
            'food_da': 'Food DA',
            'hotel': 'Hotel',
            'local_travel': 'Local Travel',
            'fuel_car': 'Fuel (Car)',
            'fuel_bike': 'Fuel (Bike)',
            'laundry': 'Laundry',
            'toll': 'Toll/Parking',
            'expense_reimbursement': 'Expense Reimbursement',
            'travel_allowance': 'Travel Allowance',
            'transport_expense': 'Transport Expense',
            'advance_request': 'Advance Request',
            'petty_cash': 'Petty Cash',
            'salary_payroll_query': 'Salary Query',
            'bank_account_update': 'Bank Update',
            'purchase_order_query': 'PO Query',
            'delivery_challan': 'Delivery Challan',
            'invoice_query': 'Invoice Query',
            'vendor_payment_status': 'Vendor Payment',
            'gst_tax_query': 'GST/Tax Query',
            'other_query': 'Other Query',
            'other': 'Other'
        };
        const lower = category.toLowerCase();
        if (catMap[lower]) return catMap[lower];
        
        // Fallback string conversion for unknown keys
        return category.split('_').map((w: string) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
    };

    return (
        <div className="mb-6 relative overflow-hidden rounded-2xl border border-gray-200/60 bg-gradient-to-br from-white to-gray-50 shadow-sm">
            {/* Top glassmorphism highlight */}
            <div className="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-emerald-400 via-teal-500 to-cyan-500 opacity-80" />
            
            <div className="p-5 sm:p-6">
                <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-6">
                    <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-xl bg-teal-100/80 flex items-center justify-center text-teal-600 shadow-sm border border-teal-200/50">
                            <Receipt className="w-5 h-5" />
                        </div>
                        <div>
                            <div className="flex items-center gap-2">
                                <h3 className="text-lg font-bold text-gray-900 leading-tight">Expense Claim Details</h3>
                                {/* Source Badge */}
                                <span className="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-semibold rounded-full bg-teal-50 text-teal-600 border border-teal-100">
                                    <Smartphone className="w-2.5 h-2.5" />
                                    MobiTraq
                                </span>
                            </div>
                            <p className="text-sm text-gray-500 font-medium">Claim Date: {new Date(claim.claim_date).toLocaleDateString()}</p>
                        </div>
                    </div>
                    
                    <Badge 
                        variant="default"
                        color={claim.status === 'approved' ? 'green' : claim.status === 'rejected' ? 'red' : 'yellow'}
                        className="text-sm px-3 py-1 shadow-sm uppercase"
                    >
                        {claim.status}
                    </Badge>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-x-8 gap-y-4 mb-6">
                    {/* Amount Block */}
                    <div className="flex items-start gap-4 p-4 rounded-xl bg-white border border-gray-100 shadow-sm transition-all hover:shadow-md md:col-span-2">
                        <div className="p-2.5 bg-green-50 rounded-lg text-green-600 border border-green-100">
                            <IndianRupee className="w-5 h-5" />
                        </div>
                        <div className="flex-1">
                            <p className="text-sm text-gray-500 mb-1">Total Claim Amount</p>
                            <p className="text-2xl font-bold text-gray-900 tracking-tight">₹{claim.total_amount?.toLocaleString('en-IN') || '0.00'}</p>
                        </div>
                    </div>
                </div>

                {/* Items List */}
                {items.length > 0 && (
                    <div className="mb-6">
                        <h4 className="text-sm font-semibold text-gray-700 mb-3 flex items-center gap-2">
                            <Receipt className="w-4 h-4 text-gray-400" />
                            Claim Items ({items.length})
                        </h4>
                        <div className="space-y-3">
                            {items.map((item, idx) => {
                                const prettyCat = getCategoryDisplayName(item.category);
                                const isLocationItem = item.description && /^\[.+→.+view .+\]|^\[.+→.+via .+\]/.test(item.description);
                                
                                return (
                                    <div key={item.id || idx} className="p-4 rounded-xl border border-gray-100 bg-white shadow-sm flex flex-col sm:flex-row gap-4 items-start sm:items-center">
                                        <div className={clsx('p-2.5 rounded-lg border', getCategoryColor(item.category))}>
                                            {getCategoryIcon(item.category)}
                                        </div>
                                        <div className="flex-1 min-w-0">
                                            <div className="flex items-center justify-between mb-1">
                                                <span className="font-semibold text-gray-900">{prettyCat}</span>
                                                <span className="font-bold text-gray-900">₹{item.amount.toLocaleString('en-IN')}</span>
                                            </div>
                                            
                                            {isLocationItem ? (
                                                <div className="flex flex-wrap items-center gap-2 mt-1.5">
                                                    <span className="inline-flex items-center gap-1 text-[11px] font-medium text-gray-600 bg-gray-50 border border-gray-200 px-2 py-0.5 rounded-full">
                                                        <MapPin className="w-3 h-3 text-blue-500" />
                                                        {item.description.match(/\[(.+?)→/)?.[1]?.trim()}
                                                    </span>
                                                    <span className="text-gray-400 text-[10px]">→</span>
                                                    <span className="inline-flex items-center gap-1 text-[11px] font-medium text-gray-600 bg-gray-50 border border-gray-200 px-2 py-0.5 rounded-full">
                                                        <MapPin className="w-3 h-3 text-green-500" />
                                                        {item.description.match(/→(.+?)via|→(.+?)view/)?.[1]?.trim() || item.description.match(/→([^\]]+)\]/)?.[1]?.trim()}
                                                    </span>
                                                    {(item.description.match(/via (.+?)\]/) || item.description.match(/view (.+?)\]/)) && (
                                                        <span className="inline-flex items-center gap-1 text-[11px] font-medium text-blue-600 bg-blue-50 border border-blue-100 px-2 py-0.5 rounded-full">
                                                            <Route className="w-3 h-3" />
                                                            {item.description.match(/via (.+?)\]/)?.[1]?.trim() || item.description.match(/view (.+?)\]/)?.[1]?.trim()}
                                                        </span>
                                                    )}
                                                    {/* Show any extra notes after the bracket */}
                                                    {item.description.replace(/\[.+?\]\s*/, '').trim() && (
                                                        <span className="text-[11px] text-gray-500 ml-1 block w-full mt-1">
                                                            {item.description.replace(/\[.+?\]\s*/, '').trim()}
                                                        </span>
                                                    )}
                                                </div>
                                            ) : (
                                                <p className="text-xs text-gray-500 mt-1">{item.description || 'No description provided.'}</p>
                                            )}
                                        </div>
                                    </div>
                                );
                            })}
                        </div>
                    </div>
                )}

                {/* Attachments Display */}
                {attachments.length > 0 && (
                    <div className="mb-6">
                        <h4 className="text-sm font-semibold text-gray-700 mb-3 flex items-center gap-2">
                            <Paperclip className="w-4 h-4 text-gray-400" />
                            Attached Receipts ({attachments.length})
                        </h4>
                        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4">
                            {attachments.map((att, idx) => {
                                const isImage = /\.(jpg|jpeg|png|gif|webp)$/i.test(att.path);
                                return (
                                    <div key={att.id || idx} className="relative group">
                                        {isImage && att.url ? (
                                            <a href={att.url} target="_blank" rel="noopener noreferrer" className="block relative aspect-square rounded-xl overflow-hidden border border-gray-200 shadow-sm bg-gray-50 hover:shadow-md transition-all">
                                                <img 
                                                    src={att.url} 
                                                    alt={att.original_filename} 
                                                    className="w-full h-full object-cover"
                                                />
                                                <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                                                    <ExternalLink className="w-6 h-6 text-white" />
                                                </div>
                                            </a>
                                        ) : (
                                            <a 
                                                href={att.url} 
                                                target="_blank" 
                                                rel="noopener noreferrer"
                                                className="flex flex-col items-center justify-center aspect-square bg-gray-50 hover:bg-gray-100 border border-gray-200 rounded-xl p-4 transition-colors text-center"
                                            >
                                                <Paperclip className="w-8 h-8 text-gray-400 mb-2" />
                                                <span className="text-[10px] font-medium text-gray-600 line-clamp-2 w-full break-words">
                                                    {att.original_filename}
                                                </span>
                                            </a>
                                        )}
                                    </div>
                                );
                            })}
                        </div>
                    </div>
                )}
            </div>
        </div>
    );
}

export default ExpenseClaimCard;
