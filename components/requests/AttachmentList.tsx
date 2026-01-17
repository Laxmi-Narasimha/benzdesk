// ============================================================================
// Attachment List Component
// Displays and allows uploading attachments
// ============================================================================

'use client';

import React, { useState, useRef } from 'react';
import { clsx } from 'clsx';
import { formatDistanceToNow } from 'date-fns';
import {
    FileText,
    Image as ImageIcon,
    Download,
    Paperclip,
    Plus,
    Loader2,
    ExternalLink,
} from 'lucide-react';
import { Button, useToast } from '@/components/ui';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { useAuth } from '@/lib/AuthContext';
import type { RequestAttachment } from '@/types';

// ============================================================================
// Types
// ============================================================================

interface AttachmentListProps {
    attachments: RequestAttachment[];
    requestId: string;
    canUpload?: boolean;
    onUpload?: (attachment: RequestAttachment) => void;
}

// ============================================================================
// File Type Icons
// ============================================================================

function getFileIcon(mimeType: string) {
    if (mimeType.startsWith('image/')) {
        return <ImageIcon className="w-5 h-5 text-green-400" />;
    }
    if (mimeType === 'application/pdf') {
        return <FileText className="w-5 h-5 text-red-400" />;
    }
    if (mimeType.includes('word')) {
        return <FileText className="w-5 h-5 text-blue-400" />;
    }
    if (mimeType.includes('excel') || mimeType.includes('spreadsheet')) {
        return <FileText className="w-5 h-5 text-green-400" />;
    }
    return <FileText className="w-5 h-5 text-dark-400" />;
}

function formatFileSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

// ============================================================================
// Component
// ============================================================================

export function AttachmentList({
    attachments,
    requestId,
    canUpload = false,
    onUpload,
}: AttachmentListProps) {
    const { user } = useAuth();
    const { success, error: showError } = useToast();
    const fileInputRef = useRef<HTMLInputElement>(null);

    const [uploading, setUploading] = useState(false);
    const [downloading, setDownloading] = useState<number | null>(null);

    // ============================================================================
    // Download Handler
    // ============================================================================

    const handleDownload = async (attachment: RequestAttachment) => {
        setDownloading(attachment.id);

        try {
            const supabase = getSupabaseClient();

            const { data, error } = await supabase.storage
                .from(attachment.bucket)
                .download(attachment.path);

            if (error) throw error;

            // Create download link
            const url = URL.createObjectURL(data);
            const a = document.createElement('a');
            a.href = url;
            a.download = attachment.original_filename;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        } catch (err: any) {
            console.error('Download error:', err);
            showError('Download Failed', 'Unable to download the file');
        } finally {
            setDownloading(null);
        }
    };

    // ============================================================================
    // Upload Handler
    // ============================================================================

    const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const files = e.target.files;
        if (!files || files.length === 0 || !user) return;

        const file = files[0];

        // Validate
        const allowedTypes = [
            'application/pdf',
            'image/jpeg',
            'image/png',
            'image/gif',
            'application/msword',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'application/vnd.ms-excel',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ];

        if (!allowedTypes.includes(file.type)) {
            showError('Invalid File', 'This file type is not allowed');
            return;
        }

        if (file.size > 10 * 1024 * 1024) {
            showError('File Too Large', 'Maximum file size is 10MB');
            return;
        }

        setUploading(true);

        try {
            const supabase = getSupabaseClient();

            // Generate unique path
            const fileExt = file.name.split('.').pop();
            const fileName = `${crypto.randomUUID()}.${fileExt}`;
            const filePath = `requests/${requestId}/${fileName}`;

            // Upload to storage
            const { error: uploadError } = await supabase.storage
                .from('benzdesk')
                .upload(filePath, file);

            if (uploadError) throw uploadError;

            // Insert attachment record
            const { data: attachment, error: insertError } = await supabase
                .from('request_attachments')
                .insert({
                    request_id: requestId,
                    uploaded_by: user.id,
                    bucket: 'benzdesk',
                    path: filePath,
                    original_filename: file.name,
                    mime_type: file.type,
                    size_bytes: file.size,
                })
                .select()
                .single();

            if (insertError) throw insertError;

            success('Upload Complete', 'File uploaded successfully');
            onUpload?.(attachment);

            // Send push notification about the new attachment
            // Fetch request details to get creator and title
            const { data: request } = await supabase
                .from('requests')
                .select('id, title, created_by')
                .eq('id', requestId)
                .single();

            if (request) {
                // Dynamic import to avoid bundling issues
                import('@/lib/notificationTrigger').then(async ({ notifyNewAttachment, sendNotification }) => {
                    console.log('[Push Trigger] Notifying about new attachment');

                    // If uploader is the creator, notify admins
                    // If uploader is admin, notify creator
                    if (user.id === request.created_by) {
                        // User uploaded -> notify admins
                        const { data: admins } = await supabase
                            .from('user_roles')
                            .select('user_id')
                            .in('role', ['accounts_admin', 'director'])
                            .eq('is_active', true);

                        if (admins) {
                            for (const admin of admins) {
                                await sendNotification({
                                    user_id: admin.user_id,
                                    title: `📎 New attachment uploaded`,
                                    body: `${file.name}\nOn: ${request.title}`,
                                    url: `/admin/request?id=${requestId}`,
                                    tag: `attachment-${requestId}`,
                                });
                            }
                        }
                    } else {
                        // Admin uploaded -> notify creator
                        await sendNotification({
                            user_id: request.created_by,
                            title: `📎 Admin attached a file`,
                            body: `${file.name}\nOn: ${request.title}`,
                            url: `/app/request?id=${requestId}`,
                            tag: `attachment-${requestId}`,
                        });
                    }
                }).catch((err) => {
                    console.error('[Push Trigger] Failed to send attachment notification:', err);
                });
            }
        } catch (err: any) {
            console.error('Upload error:', err);
            showError('Upload Failed', err.message || 'Unable to upload the file');
        } finally {
            setUploading(false);
            e.target.value = '';
        }
    };

    // ============================================================================
    // Render
    // ============================================================================

    return (
        <div className="space-y-3">
            {/* Attachment list */}
            {attachments.length === 0 ? (
                <p className="text-sm text-dark-500 text-center py-4">No attachments</p>
            ) : (
                <div className="space-y-2">
                    {attachments.map((attachment) => (
                        <div
                            key={attachment.id}
                            className="flex items-center gap-3 p-3 rounded-lg bg-dark-800/50 border border-dark-700/50 hover:border-dark-600/50 transition-colors"
                        >
                            {/* Icon */}
                            <div className="flex-shrink-0">
                                {getFileIcon(attachment.mime_type)}
                            </div>

                            {/* File info */}
                            <div className="flex-1 min-w-0">
                                <p className="text-sm font-medium text-dark-200 truncate">
                                    {attachment.original_filename}
                                </p>
                                <p className="text-xs text-dark-500">
                                    {formatFileSize(attachment.size_bytes)} •{' '}
                                    {formatDistanceToNow(new Date(attachment.uploaded_at), { addSuffix: true })}
                                </p>
                            </div>

                            {/* Download button */}
                            <button
                                onClick={() => handleDownload(attachment)}
                                disabled={downloading === attachment.id}
                                className="flex-shrink-0 p-2 rounded-lg text-dark-400 hover:text-dark-100 hover:bg-dark-700/50 transition-colors disabled:opacity-50"
                            >
                                {downloading === attachment.id ? (
                                    <Loader2 className="w-4 h-4 animate-spin" />
                                ) : (
                                    <Download className="w-4 h-4" />
                                )}
                            </button>
                        </div>
                    ))}
                </div>
            )}

            {/* Upload button */}
            {canUpload && (
                <>
                    <input
                        ref={fileInputRef}
                        type="file"
                        onChange={handleUpload}
                        accept=".pdf,.jpg,.jpeg,.png,.gif,.doc,.docx,.xls,.xlsx"
                        className="hidden"
                    />
                    <Button
                        variant="secondary"
                        size="sm"
                        fullWidth
                        onClick={() => fileInputRef.current?.click()}
                        isLoading={uploading}
                        leftIcon={<Plus className="w-4 h-4" />}
                    >
                        Add Attachment
                    </Button>
                </>
            )}
        </div>
    );
}

export default AttachmentList;
