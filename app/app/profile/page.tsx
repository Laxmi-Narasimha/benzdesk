// ============================================================================
// Employee Profile & Settings Page
// ============================================================================

'use client';

import React, { useState, useEffect } from 'react';
import { useAuth } from '@/lib/AuthContext';
import { supabase } from '@/lib/supabaseClient';
import { Button, Card, useToast } from '@/components/ui';
import { User, Shield, Loader2, Save, Map, Receipt, Fuel } from 'lucide-react';

interface EmployeeData {
    id: string;
    name: string;
    phone: string | null;
    band: string;
}

interface BandLimit {
    category: string;
    daily_limit: number;
    unit: string;
}

export default function ProfilePage() {
    const { user } = useAuth();
    const { success, error: showError } = useToast();

    const [isLoading, setIsLoading] = useState(true);
    const [isSaving, setIsSaving] = useState(false);
    
    const [employee, setEmployee] = useState<EmployeeData | null>(null);
    const [limits, setLimits] = useState<BandLimit[]>([]);
    
    // Form fields
    const [name, setName] = useState('');

    useEffect(() => {
        if (!user) return;

        async function loadProfile() {
            try {
                // 1. Fetch employee
                const { data: empData, error: empError } = await supabase
                    .from('employees')
                    .select('id, name, phone, band')
                    .eq('id', user!.id)
                    .single();

                if (empError) throw empError;
                
                setEmployee(empData);
                setName(empData.name || '');

                // 2. Fetch limits for this band
                if (empData.band) {
                    const { data: limitData, error: limitError } = await supabase
                        .from('band_limits')
                        .select('category, daily_limit, unit')
                        .eq('band', empData.band)
                        .order('category');

                    if (!limitError && limitData) {
                        setLimits(limitData);
                    }
                }
            } catch (err: any) {
                console.error("Failed to load profile:", err);
                showError('Error', err.message || 'Failed to load profile data');
            } finally {
                setIsLoading(false);
            }
        }

        loadProfile();
    }, [user, showError]);

    const handleSave = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!user || !name.trim()) return;

        setIsSaving(true);
        try {
            const { error } = await supabase
                .from('employees')
                .update({ name: name.trim() })
                .eq('id', user.id);

            if (error) throw error;
            success('Saved', 'Your profile name has been updated.');
        } catch (err: any) {
            console.error('Update failed:', err);
            showError('Error', err.message || 'Could not update profile');
        } finally {
            setIsSaving(false);
        }
    };

    if (isLoading) {
        return (
            <div className="flex items-center justify-center min-h-[50vh]">
                <Loader2 className="w-8 h-8 animate-spin text-primary-500" />
            </div>
        );
    }

    const formatLimit = (limit: number) => {
        if (limit === 99999 || limit === 0) return 'Actuals';
        return `₹${limit.toLocaleString('en-IN')}`;
    };

    const getIconForCategory = (category: string) => {
        const cat = category.toLowerCase();
        if (cat.includes('hotel') || cat.includes('lodg')) return <Map className="w-5 h-5 text-indigo-500" />;
        if (cat.includes('food') || cat.includes('board') || cat.includes('meal')) return <Receipt className="w-5 h-5 text-amber-500" />;
        if (cat.includes('fuel')) return <Fuel className="w-5 h-5 text-red-500" />;
        return <Receipt className="w-5 h-5 text-gray-500" />;
    };

    return (
        <div className="max-w-4xl mx-auto space-y-6">
            <div className="flex items-center justify-between">
                <div>
                    <h1 className="text-2xl font-bold text-dark-50">Profile Settings</h1>
                    <p className="text-dark-400 mt-1">
                        Manage your personal info and view travel limits
                    </p>
                </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                
                {/* Left Col: Edit Profile */}
                <div className="md:col-span-1 space-y-6">
                    <Card className="p-6">
                        <h2 className="text-lg font-semibold text-white flex items-center gap-2 mb-4">
                            <User className="w-5 h-5 text-primary-400" />
                            Personal Info
                        </h2>
                        
                        <form onSubmit={handleSave} className="space-y-4">
                            <div>
                                <label className="block text-sm font-medium text-dark-300 mb-1">
                                    Email Address
                                </label>
                                <input
                                    type="email"
                                    value={user?.email || ''}
                                    disabled
                                    className="w-full px-3 py-2 bg-dark-800 border border-dark-700 rounded-lg text-dark-400 text-sm cursor-not-allowed"
                                />
                                <p className="text-xs text-dark-500 mt-1">Email cannot be changed.</p>
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-dark-300 mb-1">
                                    Display Name
                                </label>
                                <input
                                    type="text"
                                    value={name}
                                    onChange={(e) => setName(e.target.value)}
                                    placeholder="Your Full Name"
                                    className="w-full px-3 py-2 bg-dark-900 border border-dark-700 rounded-lg text-white text-sm focus:border-primary-500 focus:ring-1 focus:ring-primary-500"
                                    required
                                />
                            </div>

                            <Button 
                                type="submit" 
                                isLoading={isSaving}
                                leftIcon={<Save className="w-4 h-4" />}
                                className="w-full mt-2"
                            >
                                Save Changes
                            </Button>
                        </form>
                    </Card>

                    <Card className="p-6 bg-gradient-to-br from-dark-800 to-dark-900 border-dark-700">
                        <h2 className="text-lg font-semibold text-white flex items-center gap-2 mb-2">
                            <Shield className="w-5 h-5 text-emerald-400" />
                            Policy Band
                        </h2>
                        <p className="text-sm text-dark-400 mb-4">
                            Your expense limits are determined by your assigned employee band.
                        </p>
                        <div className="inline-flex px-3 py-1 items-center justify-center bg-primary-500/10 border border-primary-500/20 text-primary-400 font-bold rounded-lg uppercase tracking-wider text-sm">
                            {employee?.band || 'Unassigned'}
                        </div>
                    </Card>
                </div>

                {/* Right Col: Travel Limits */}
                <div className="md:col-span-2">
                    <Card className="p-0 overflow-hidden">
                        <div className="p-6 border-b border-dark-800">
                            <h2 className="text-lg font-semibold text-white">Travel Policy Limits</h2>
                            <p className="text-sm text-dark-400 mt-1">
                                Maximum reimbursable amounts for the <strong className="text-primary-400 capitalize">{employee?.band}</strong> band. 
                            </p>
                        </div>
                        
                        {limits.length === 0 ? (
                            <div className="p-6 text-center text-dark-400 text-sm">
                                No limits defined for your band.
                            </div>
                        ) : (
                            <div className="divide-y divide-dark-800">
                                {limits.map((limit) => (
                                    <div key={limit.category} className="p-4 sm:px-6 flex items-center justify-between hover:bg-dark-800/50 transition-colors">
                                        <div className="flex items-center gap-4">
                                            <div className="w-10 h-10 rounded-xl bg-dark-800 border border-dark-700 flex items-center justify-center">
                                                {getIconForCategory(limit.category)}
                                            </div>
                                            <div>
                                                <p className="font-medium text-dark-50 capitalize">
                                                    {limit.category.replace(/_/g, ' ')}
                                                </p>
                                                <p className="text-xs text-dark-400 mt-0.5 uppercase tracking-wider">
                                                    Per {limit.unit}
                                                </p>
                                            </div>
                                        </div>
                                        <div className="text-right">
                                            <p className="text-lg font-bold text-dark-50">
                                                {formatLimit(limit.daily_limit)}
                                            </p>
                                        </div>
                                    </div>
                                ))}
                            </div>
                        )}
                    </Card>
                </div>

            </div>
        </div>
    );
}
