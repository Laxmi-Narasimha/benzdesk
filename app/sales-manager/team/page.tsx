// ============================================================================
// Sales Manager — My Team Page
// Shows all team members and their recent request activity
// ============================================================================

'use client';

import React, { useState, useEffect } from 'react';
import { Users } from 'lucide-react';
import { Card, CardHeader, Skeleton } from '@/components/ui';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { useAuth } from '@/lib/AuthContext';
import { getDisplayName } from '@/types';

export default function SalesManagerTeamPage() {
    const { user } = useAuth();
    const [loading, setLoading] = useState(true);
    const [members, setMembers] = useState<any[]>([]);

    useEffect(() => {
        if (!user) return;
        async function fetchTeam() {
            try {
                const supabase = getSupabaseClient();
                const { data: teamData } = await supabase
                    .from('manager_team')
                    .select('member_user_id')
                    .eq('manager_user_id', user!.id);

                if (!teamData || teamData.length === 0) {
                    setLoading(false);
                    return;
                }

                const memberIds = teamData.map(t => t.member_user_id);

                // Get request counts per member
                const { data: requests } = await supabase
                    .from('requests')
                    .select('created_by, status, amount')
                    .in('created_by', memberIds);

                const memberStats = memberIds.map(memberId => {
                    const memberRequests = (requests || []).filter(r => r.created_by === memberId);
                    const pending = memberRequests.filter(r => r.status === 'pending_manager_approval').length;
                    const approved = memberRequests.filter(r => r.status !== 'pending_manager_approval').length;
                    const totalAmount = memberRequests.reduce((s, r) => s + (r.amount || 0), 0);
                    return { id: memberId, pending, approved, totalAmount, total: memberRequests.length };
                });

                setMembers(memberStats);
            } catch (err) {
                console.error('Error fetching team:', err);
            } finally {
                setLoading(false);
            }
        }
        fetchTeam();
    }, [user]);

    return (
        <div className="max-w-5xl mx-auto space-y-6">
            <div>
                <h1 className="text-2xl font-bold text-dark-50">My Team</h1>
                <p className="text-dark-400 mt-1">Overview of your team members and their request activity</p>
            </div>

            <Card padding="lg">
                <CardHeader title="Team Members" />
                {loading ? (
                    <div className="space-y-3 mt-4">
                        {[1, 2, 3].map(i => <Skeleton key={i} height={80} variant="rounded" />)}
                    </div>
                ) : members.length === 0 ? (
                    <div className="text-center py-12">
                        <Users className="w-12 h-12 text-dark-700 mx-auto mb-3" />
                        <p className="text-dark-400">No team members assigned yet.</p>
                        <p className="text-dark-600 text-sm mt-1">Contact the director to add members to your team.</p>
                    </div>
                ) : (
                    <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                        {members.map((member) => (
                            <div key={member.id} className="p-4 rounded-xl bg-dark-800/50 border border-dark-700/50">
                                <div className="flex items-center gap-3 mb-3">
                                    <div className="w-10 h-10 rounded-full bg-primary-500/20 flex items-center justify-center text-primary-400 font-bold text-sm">
                                        {member.id.charAt(0).toUpperCase()}
                                    </div>
                                    <div className="flex-1 min-w-0">
                                        <p className="font-medium text-dark-100 text-sm truncate">
                                            {getDisplayName(member.id) || member.id}
                                        </p>
                                        <p className="text-xs text-dark-500">{member.total} total requests</p>
                                    </div>
                                </div>
                                <div className="grid grid-cols-2 gap-2 text-center">
                                    <div className="p-2 rounded-lg bg-amber-500/10">
                                        <p className="text-lg font-bold text-amber-400">{member.pending}</p>
                                        <p className="text-xs text-dark-500">Pending</p>
                                    </div>
                                    <div className="p-2 rounded-lg bg-green-500/10">
                                        <p className="text-lg font-bold text-green-400">{member.approved}</p>
                                        <p className="text-xs text-dark-500">Forwarded</p>
                                    </div>
                                </div>
                                {member.totalAmount > 0 && (
                                    <p className="text-xs text-dark-500 mt-2 text-center">
                                        Total: ₹{member.totalAmount.toLocaleString('en-IN')}
                                    </p>
                                )}
                            </div>
                        ))}
                    </div>
                )}
            </Card>
        </div>
    );
}
