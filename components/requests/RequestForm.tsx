// ============================================================================
// Request Form Component
// Clean form for creating requests with deadline and file uploads
// ============================================================================

'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Send, Paperclip, X, FileText } from 'lucide-react';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { useAuth } from '@/lib/AuthContext';
import { useToast, DateTimePicker } from '@/components/ui';
import type { CreateRequestInput, RequestCategory, Priority } from '@/types';
import { REQUEST_CATEGORY_LABELS, PRIORITY_LABELS } from '@/types';

// ============================================================================
// Types
// ============================================================================

interface RequestFormProps {
    onSuccess?: (requestId: string) => void;
}

interface FormErrors {
    title?: string;
    description?: string;
    category?: string;
    general?: string;
}

interface AttachmentPreview {
    file: File;
    preview?: string;
}

// ============================================================================
// Category Options - Grouped for manufacturing
// ============================================================================

const categoryGroups = [
    {
        label: 'Expenses & Payments',
        options: [
            { value: 'expense_reimbursement', label: 'Expense Reimbursement' },
            { value: 'travel_allowance', label: 'Travel Allowance (TA/DA)' },
            { value: 'transport_expense', label: 'Transport Expense' },
            { value: 'advance_request', label: 'Advance Request' },
            { value: 'petty_cash', label: 'Petty Cash' },
        ],
    },
    {
        label: 'Salary & HR',
        options: [
            { value: 'salary_payroll', label: 'Salary / Payroll Query' },
            { value: 'bank_account_update', label: 'Bank Account Update' },
        ],
    },
    {
        label: 'Vendors & Orders',
        options: [
            { value: 'purchase_order', label: 'Purchase Order Query' },
            { value: 'delivery_challan', label: 'Delivery Challan' },
            { value: 'invoice_query', label: 'Invoice Query' },
            { value: 'vendor_payment', label: 'Vendor Payment Status' },
        ],
    },
    {
        label: 'Tax & Compliance',
        options: [
            { value: 'gst_tax_query', label: 'GST / Tax Query' },
        ],
    },
    {
        label: 'Other',
        options: [
            { value: 'other', label: 'Other Query' },
        ],
    },
];

const priorityOptions = [
    { value: '1', label: 'Urgent - Need today', color: '#ef4444' },
    { value: '2', label: 'High - Within 2 days', color: '#f97316' },
    { value: '3', label: 'Normal - Within a week', color: '#a3a3a3' },
    { value: '4', label: 'Low - No rush', color: '#4ade80' },
];

// ============================================================================
// Component
// ============================================================================

export function RequestForm({ onSuccess }: RequestFormProps) {
    const router = useRouter();
    const { user } = useAuth();
    const { success, error: showError } = useToast();

    const [isSubmitting, setIsSubmitting] = useState(false);
    const [errors, setErrors] = useState<FormErrors>({});
    const [attachments, setAttachments] = useState<AttachmentPreview[]>([]);

    const [formData, setFormData] = useState<CreateRequestInput>({
        title: '',
        description: '',
        category: 'other' as RequestCategory,
        priority: 3 as Priority,
        deadline: null,
    });

    // ============================================================================
    // Validation
    // ============================================================================

    const validateForm = (): boolean => {
        const newErrors: FormErrors = {};

        if (!formData.title.trim()) {
            newErrors.title = 'Please enter a title';
        } else if (formData.title.length < 5) {
            newErrors.title = 'Title is too short';
        }

        if (!formData.description.trim()) {
            newErrors.description = 'Please describe your request';
        } else if (formData.description.length < 10) {
            newErrors.description = 'Please provide more details';
        }

        if (!formData.category || formData.category === 'other') {
            // Allow 'other' but encourage specific selection
        }

        setErrors(newErrors);
        return Object.keys(newErrors).length === 0;
    };

    // ============================================================================
    // File Handling
    // ============================================================================

    const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        const files = e.target.files;
        if (!files) return;

        const maxSize = 10 * 1024 * 1024; // 10MB

        const validFiles: AttachmentPreview[] = [];

        Array.from(files).forEach((file) => {
            if (file.size > maxSize) {
                showError('File too large', `${file.name} exceeds 10MB limit`);
                return;
            }

            const preview = file.type.startsWith('image/')
                ? URL.createObjectURL(file)
                : undefined;

            validFiles.push({ file, preview });
        });

        setAttachments((prev) => [...prev, ...validFiles]);
        e.target.value = '';
    };

    const removeAttachment = (index: number) => {
        setAttachments((prev) => {
            const attachment = prev[index];
            if (attachment.preview) {
                URL.revokeObjectURL(attachment.preview);
            }
            return prev.filter((_, i) => i !== index);
        });
    };

    const formatFileSize = (bytes: number): string => {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
        return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
    };

    // ============================================================================
    // Submit Handler
    // ============================================================================

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();

        if (!validateForm()) return;
        if (!user) return;

        setIsSubmitting(true);
        setErrors({});

        try {
            const supabase = getSupabaseClient();

            // Create the request
            const { data: request, error: createError } = await supabase
                .from('requests')
                .insert({
                    title: formData.title.trim(),
                    description: formData.description.trim(),
                    category: formData.category,
                    priority: formData.priority,
                    deadline: formData.deadline || null,
                    created_by: user.id,
                })
                .select()
                .single();

            if (createError) throw createError;

            // Upload attachments if any
            if (attachments.length > 0 && request) {
                for (const attachment of attachments) {
                    const fileExt = attachment.file.name.split('.').pop();
                    const fileName = `${crypto.randomUUID()}.${fileExt}`;
                    const filePath = `requests/${request.id}/${fileName}`;

                    const { error: uploadError } = await supabase.storage
                        .from('benzdesk')
                        .upload(filePath, attachment.file);

                    if (uploadError) {
                        console.error('Upload error:', uploadError);
                        continue;
                    }

                    await supabase.from('request_attachments').insert({
                        request_id: request.id,
                        uploaded_by: user.id,
                        bucket: 'benzdesk',
                        path: filePath,
                        original_filename: attachment.file.name,
                        mime_type: attachment.file.type,
                        size_bytes: attachment.file.size,
                    });
                }
            }

            success('Request Submitted', 'Your request has been sent to the accounts team');

            if (onSuccess) {
                onSuccess(request.id);
            } else {
                router.push(`/app/request?id=${request.id}`);
            }

            // Send push notification to admins
            // We don't await this to avoid blocking the UI
            import('@/lib/notificationTrigger').then(({ notifyNewRequest }) => {
                console.log('[Push Trigger] Notifying admins of new request:', request.id);
                notifyNewRequest(
                    request.id,
                    request.title,
                    request.category,
                    user.email || 'Employee'
                ).then(() => {
                    console.log('[Push Trigger] Notification sent successfully');
                }).catch((err) => {
                    console.error('[Push Trigger] Failed to send notification:', err);
                });
            }).catch((err) => {
                console.error('[Push Trigger] Failed to import notification module:', err);
            });
        } catch (err: any) {
            console.error('Error creating request:', err);
            setErrors({ general: err.message || 'Failed to create request' });
            showError('Error', 'Failed to submit request. Please try again.');
        } finally {
            setIsSubmitting(false);
        }
    };

    // ============================================================================
    // Render
    // ============================================================================

    return (
        <div className="max-w-2xl mx-auto">
            <form onSubmit={handleSubmit} className="space-y-6">

                {/* Step 1: Category - What type of request */}
                <div className="bg-white border border-gray-200 rounded-xl p-6 shadow-sm">
                    <label className="block text-sm font-semibold text-gray-900 mb-3">
                        1. What type of request is this?
                    </label>
                    <select
                        value={formData.category}
                        onChange={(e) => setFormData({ ...formData, category: e.target.value as RequestCategory })}
                        className="w-full px-4 py-3 bg-gray-50 border border-gray-300 rounded-lg text-gray-900 text-base focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 focus:outline-none cursor-pointer"
                        disabled={isSubmitting}
                    >
                        {categoryGroups.map((group) => (
                            <optgroup key={group.label} label={group.label}>
                                {group.options.map((option) => (
                                    <option key={option.value} value={option.value}>
                                        {option.label}
                                    </option>
                                ))}
                            </optgroup>
                        ))}
                    </select>
                </div>

                {/* Step 2: Title - Brief summary */}
                <div className="bg-white border border-gray-200 rounded-xl p-6 shadow-sm">
                    <label className="block text-sm font-semibold text-gray-900 mb-3">
                        2. Give a brief title
                    </label>
                    <input
                        type="text"
                        placeholder="e.g., Expense reimbursement for client visit"
                        value={formData.title}
                        onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                        className="w-full px-4 py-3 bg-gray-50 border border-gray-300 rounded-lg text-gray-900 text-base placeholder-gray-400 focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 focus:outline-none"
                        disabled={isSubmitting}
                    />
                    {errors.title && (
                        <p className="mt-2 text-sm text-red-600">{errors.title}</p>
                    )}
                </div>

                {/* Step 3: Description - Detailed explanation */}
                <div className="bg-white border border-gray-200 rounded-xl p-6 shadow-sm">
                    <label className="block text-sm font-semibold text-gray-900 mb-3">
                        3. Provide details
                    </label>
                    <textarea
                        placeholder="Please explain your request in detail. Include all relevant information such as amounts, dates, reference numbers, vendor names, etc."
                        value={formData.description}
                        onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                        className="w-full px-4 py-3 bg-gray-50 border border-gray-300 rounded-lg text-gray-900 text-base placeholder-gray-400 focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 focus:outline-none resize-none"
                        rows={5}
                        disabled={isSubmitting}
                    />
                    {errors.description && (
                        <p className="mt-2 text-sm text-red-600">{errors.description}</p>
                    )}
                </div>

                {/* Step 4: Attachments - Supporting documents */}
                <div className="bg-white border border-gray-200 rounded-xl p-6 shadow-sm">
                    <label className="block text-sm font-semibold text-gray-900 mb-3">
                        <span className="flex items-center gap-2">
                            <Paperclip className="w-4 h-4" />
                            4. Attach supporting documents (optional)
                        </span>
                    </label>

                    {/* Upload area */}
                    <label className="flex flex-col items-center justify-center w-full p-6 border-2 border-dashed border-gray-300 rounded-lg bg-gray-50 hover:border-primary-400 hover:bg-primary-50/30 cursor-pointer transition-colors">
                        <Paperclip className="w-8 h-8 text-gray-400 mb-2" />
                        <span className="text-sm text-gray-600 text-center">
                            Click to upload or drag files here
                        </span>
                        <span className="text-xs text-gray-400 mt-1 text-center">
                            Bills, receipts, challans, invoices (max 10MB each)
                        </span>
                        <input
                            type="file"
                            multiple
                            onChange={handleFileChange}
                            disabled={isSubmitting}
                            className="hidden"
                        />
                    </label>

                    {/* Uploaded files */}
                    {attachments.length > 0 && (
                        <div className="mt-4 space-y-2">
                            {attachments.map((attachment, index) => (
                                <div
                                    key={index}
                                    className="flex items-center justify-between p-3 bg-gray-50 border border-gray-200 rounded-lg"
                                >
                                    <div className="flex items-center gap-3 min-w-0">
                                        {attachment.preview ? (
                                            <img
                                                src={attachment.preview}
                                                alt=""
                                                className="w-10 h-10 object-cover rounded"
                                            />
                                        ) : (
                                            <div className="w-10 h-10 flex items-center justify-center bg-gray-200 rounded">
                                                <FileText className="w-5 h-5 text-gray-500" />
                                            </div>
                                        )}
                                        <div className="min-w-0">
                                            <p className="text-sm text-gray-900 truncate">
                                                {attachment.file.name}
                                            </p>
                                            <p className="text-xs text-gray-500">
                                                {formatFileSize(attachment.file.size)}
                                            </p>
                                        </div>
                                    </div>
                                    <button
                                        type="button"
                                        onClick={() => removeAttachment(index)}
                                        className="p-2 text-gray-400 hover:text-red-500 transition-colors"
                                    >
                                        <X className="w-4 h-4" />
                                    </button>
                                </div>
                            ))}
                        </div>
                    )}
                </div>

                {/* Step 5: Priority/Urgency */}
                <div className="bg-white border border-gray-200 rounded-xl p-6 shadow-sm">
                    <label className="block text-sm font-semibold text-gray-900 mb-3">
                        5. How urgent is this?
                    </label>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                        {priorityOptions.map((option) => (
                            <button
                                key={option.value}
                                type="button"
                                onClick={() => setFormData({ ...formData, priority: Number(option.value) as Priority })}
                                className={`px-4 py-3 rounded-lg border text-left transition-all ${String(formData.priority) === option.value
                                    ? 'border-primary-500 bg-primary-50 ring-2 ring-primary-500/20'
                                    : 'border-gray-200 bg-gray-50 hover:border-gray-300'
                                    }`}
                                disabled={isSubmitting}
                            >
                                <div className="flex items-center gap-3">
                                    <div
                                        className="w-3 h-3 rounded-full"
                                        style={{ backgroundColor: option.color }}
                                    />
                                    <span className="text-sm text-gray-700">{option.label}</span>
                                </div>
                            </button>
                        ))}
                    </div>
                </div>

                {/* Step 6: Deadline */}
                <div className="bg-white border border-gray-200 rounded-xl p-6 shadow-sm">
                    <label className="block text-sm font-semibold text-gray-900 mb-3">
                        6. Set a deadline (optional)
                    </label>
                    <DateTimePicker
                        value={formData.deadline ?? null}
                        onChange={(value) => setFormData({ ...formData, deadline: value })}
                        disabled={isSubmitting}
                        placeholder="Select date and time if needed"
                    />
                    <p className="mt-3 text-xs text-amber-600 flex items-center gap-1.5 bg-amber-50 px-3 py-2 rounded-lg">
                        <span className="font-medium">⚠️ Choose responsibly</span> — Setting realistic deadlines helps us process all requests efficiently.
                    </p>
                </div>

                {/* Error */}
                {errors.general && (
                    <div className="p-4 bg-red-50 border border-red-200 rounded-lg text-red-600 text-sm">
                        {errors.general}
                    </div>
                )}

                {/* Submit */}
                <div className="flex flex-col sm:flex-row gap-3 pt-2">
                    <button
                        type="button"
                        onClick={() => router.back()}
                        className="px-6 py-3 text-gray-500 hover:text-gray-900 transition-colors order-2 sm:order-1"
                        disabled={isSubmitting}
                    >
                        Cancel
                    </button>
                    <button
                        type="submit"
                        className="flex-1 flex items-center justify-center gap-2 px-6 py-3.5 bg-primary-500 text-white font-medium rounded-lg hover:bg-primary-600 transition-colors disabled:opacity-40 order-1 sm:order-2"
                        disabled={isSubmitting}
                    >
                        {isSubmitting ? (
                            <div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                        ) : (
                            <>
                                Submit Request
                                <Send className="w-4 h-4" />
                            </>
                        )}
                    </button>
                </div>
            </form>
        </div>
    );
}

export default RequestForm;

