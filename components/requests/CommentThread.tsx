// ============================================================================
// Comment Thread Component (Chat Style)
// WhatsApp/iMessage style chat bubbles - employee left, admin right
// ============================================================================

'use client';

import React, { useState, useRef, useEffect } from 'react';
import { clsx } from 'clsx';
import { formatDistanceToNow, format } from 'date-fns';
import { Send, Lock, MessageSquare, User, Shield } from 'lucide-react';
import { Button, Textarea, useToast } from '@/components/ui';
import { useAuth } from '@/lib/AuthContext';
import type { RequestComment } from '@/types';

// ============================================================================
// Types
// ============================================================================

interface CommentThreadProps {
    comments: RequestComment[];
    onAddComment: (body: string, isInternal: boolean) => Promise<void>;
    canAddInternal?: boolean;
    requestCreatorId: string;
}

// ============================================================================
// Chat Bubble Component
// ============================================================================

function ChatBubble({
    comment,
    isOwn,
    isRequester,
    showAvatar,
}: {
    comment: RequestComment;
    isOwn: boolean;
    isRequester: boolean;
    showAvatar: boolean;
}) {
    // Determine alignment: requester on left, admin on right
    const isLeft = isRequester;

    return (
        <div
            className={clsx(
                'flex gap-2 animate-fade-in',
                isLeft ? 'flex-row' : 'flex-row-reverse'
            )}
        >
            {/* Avatar */}
            <div className={clsx('flex-shrink-0 mt-1', !showAvatar && 'invisible')}>
                <div
                    className={clsx(
                        'w-8 h-8 rounded-full flex items-center justify-center',
                        isRequester
                            ? 'bg-green-100 text-green-600'
                            : 'bg-primary-100 text-primary-600'
                    )}
                >
                    {isRequester ? (
                        <User className="w-4 h-4" />
                    ) : (
                        <Shield className="w-4 h-4" />
                    )}
                </div>
            </div>

            {/* Bubble */}
            <div
                className={clsx(
                    'max-w-[75%] sm:max-w-[70%]',
                    isLeft ? 'mr-auto' : 'ml-auto'
                )}
            >
                {/* Name/Role label */}
                {showAvatar && (
                    <div className={clsx(
                        'flex items-center gap-2 mb-1 px-1',
                        isLeft ? 'justify-start' : 'justify-end'
                    )}>
                        <span className={clsx(
                            'text-xs font-medium',
                            isRequester ? 'text-green-600' : 'text-primary-600'
                        )}>
                            {isOwn ? 'You' : isRequester ? 'Employee' : 'Admin'}
                        </span>
                        {comment.is_internal && (
                            <span className="flex items-center gap-0.5 text-xs text-amber-600">
                                <Lock className="w-3 h-3" />
                                Internal
                            </span>
                        )}
                    </div>
                )}

                {/* Message bubble */}
                <div
                    className={clsx(
                        'relative px-4 py-2.5 rounded-2xl shadow-sm',
                        // Bubble styling
                        isLeft
                            ? 'bg-gray-100 text-gray-900 rounded-tl-md'
                            : 'bg-primary-500 text-white rounded-tr-md',
                        // Internal note styling
                        comment.is_internal && 'bg-amber-50 text-amber-900 border border-amber-200',
                    )}
                >
                    <p className="text-sm whitespace-pre-wrap break-words leading-relaxed">
                        {comment.body}
                    </p>
                </div>

                {/* Timestamp */}
                <div className={clsx(
                    'mt-1 px-1',
                    isLeft ? 'text-left' : 'text-right'
                )}>
                    <span className="text-xs text-gray-400" suppressHydrationWarning>
                        {format(new Date(comment.created_at), 'MMM d, h:mm a')}
                    </span>
                </div>
            </div>
        </div>
    );
}

// ============================================================================
// Component
// ============================================================================

export function CommentThread({
    comments,
    onAddComment,
    canAddInternal = false,
    requestCreatorId,
}: CommentThreadProps) {
    const { user, canManageRequests } = useAuth();
    const { error: showError } = useToast();
    const scrollRef = useRef<HTMLDivElement>(null);

    const [newComment, setNewComment] = useState('');
    const [isInternal, setIsInternal] = useState(false);
    const [isSubmitting, setIsSubmitting] = useState(false);

    // Filter comments based on visibility
    const visibleComments = comments.filter(
        (c) => !c.is_internal || canManageRequests
    );

    // Scroll to bottom on new comments
    useEffect(() => {
        if (scrollRef.current) {
            scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
        }
    }, [visibleComments.length]);

    // ============================================================================
    // Submit Handler
    // ============================================================================

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();

        if (!newComment.trim()) return;

        setIsSubmitting(true);

        try {
            await onAddComment(newComment.trim(), isInternal);
            setNewComment('');
            setIsInternal(false);
        } catch (err) {
            // Error already shown by parent
        } finally {
            setIsSubmitting(false);
        }
    };

    // Check if we should show avatar (first message from this sender or different from previous)
    const shouldShowAvatar = (index: number, comment: RequestComment) => {
        if (index === 0) return true;
        const prevComment = visibleComments[index - 1];
        return prevComment.author_id !== comment.author_id;
    };

    // ============================================================================
    // Render
    // ============================================================================

    return (
        <div className="flex flex-col bg-white rounded-xl border border-gray-200 shadow-sm">
            {/* Chat header */}
            <div className="flex items-center gap-2 px-4 py-3 bg-gray-50 border-b border-gray-200">
                <MessageSquare className="w-5 h-5 text-gray-500" />
                <h3 className="text-sm font-semibold text-gray-900">Conversation</h3>
                <span className="text-xs text-gray-500 ml-auto">
                    {visibleComments.length} message{visibleComments.length !== 1 ? 's' : ''}
                </span>
            </div>

            {/* Messages area - limited height so input is always visible */}
            <div
                ref={scrollRef}
                className="overflow-y-auto p-4 space-y-4 min-h-[150px] max-h-[250px] sm:max-h-[350px] bg-gradient-to-b from-gray-50/50 to-white"
            >
                {visibleComments.length === 0 ? (
                    <div className="flex flex-col items-center justify-center h-full py-8 text-center">
                        <div className="w-12 h-12 rounded-full bg-gray-100 flex items-center justify-center mb-3">
                            <MessageSquare className="w-6 h-6 text-gray-400" />
                        </div>
                        <p className="text-gray-500 text-sm">No messages yet</p>
                        <p className="text-gray-400 text-xs mt-1">Start the conversation below</p>
                    </div>
                ) : (
                    visibleComments.map((comment, index) => {
                        const isOwn = comment.author_id === user?.id;
                        const isRequester = comment.author_id === requestCreatorId;

                        return (
                            <ChatBubble
                                key={comment.id}
                                comment={comment}
                                isOwn={isOwn}
                                isRequester={isRequester}
                                showAvatar={shouldShowAvatar(index, comment)}
                            />
                        );
                    })
                )}
            </div>

            {/* New message form */}
            <div className="p-4 bg-gray-50 border-t border-gray-200">
                <form onSubmit={handleSubmit} className="space-y-3">
                    {/* Internal toggle (admin only) */}
                    {canAddInternal && (
                        <label className="inline-flex items-center gap-2 cursor-pointer">
                            <input
                                type="checkbox"
                                checked={isInternal}
                                onChange={(e) => setIsInternal(e.target.checked)}
                                disabled={isSubmitting}
                                className="w-4 h-4 rounded border-gray-300 bg-white text-amber-500 focus:ring-amber-500"
                            />
                            <span className="text-sm text-gray-600 flex items-center gap-1">
                                <Lock className="w-3.5 h-3.5" />
                                Internal note (hidden from employee)
                            </span>
                        </label>
                    )}

                    <div className="flex gap-2">
                        <Textarea
                            placeholder={
                                isInternal
                                    ? 'Add an internal note...'
                                    : 'Type your message...'
                            }
                            value={newComment}
                            onChange={(e) => setNewComment(e.target.value)}
                            disabled={isSubmitting}
                            className={clsx(
                                'flex-1 min-h-[60px] max-h-[120px] resize-none',
                                'bg-white border-gray-300 text-gray-900 placeholder:text-gray-400',
                                isInternal && 'bg-amber-50 border-amber-300'
                            )}
                            onKeyDown={(e) => {
                                if (e.key === 'Enter' && !e.shiftKey) {
                                    e.preventDefault();
                                    handleSubmit(e);
                                }
                            }}
                        />
                        <Button
                            type="submit"
                            size="sm"
                            isLoading={isSubmitting}
                            disabled={!newComment.trim()}
                            className="self-end px-4 py-3"
                        >
                            <Send className="w-4 h-4" />
                        </Button>
                    </div>

                    <p className="text-xs text-gray-400">
                        Press Enter to send, Shift+Enter for new line
                    </p>
                </form>
            </div>
        </div>
    );
}

export default CommentThread;
