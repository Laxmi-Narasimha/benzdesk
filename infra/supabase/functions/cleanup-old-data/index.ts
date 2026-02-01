// Supabase Edge Function: Retention Cleanup
// Per industry-grade specification Section 11
// 
// This function deletes old data per retention policy
// Run daily at 2 AM IST via cron

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
    try {
        const supabase = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // Get retention config
        const { data: config } = await supabase
            .from('mobitraq_config')
            .select('value')
            .eq('key', 'RETENTION_DAYS')
            .single()

        const retentionDays = config?.value ? parseInt(config.value) : 35
        const cutoffDate = new Date()
        cutoffDate.setDate(cutoffDate.getDate() - retentionDays)
        const cutoffIso = cutoffDate.toISOString()

        // Delete old location points
        const { count: deletedPoints, error: pointsError } = await supabase
            .from('location_points')
            .delete({ count: 'exact' })
            .lt('recorded_at', cutoffIso)

        if (pointsError) {
            console.error('Error deleting points:', pointsError)
        }

        // Delete old timeline events
        const { count: deletedEvents, error: eventsError } = await supabase
            .from('timeline_events')
            .delete({ count: 'exact' })
            .lt('start_time', cutoffIso)

        if (eventsError) {
            console.error('Error deleting events:', eventsError)
        }

        // Delete old alerts (90 days retention for alerts)
        const alertCutoff = new Date()
        alertCutoff.setDate(alertCutoff.getDate() - 90)

        const { count: deletedAlerts, error: alertsError } = await supabase
            .from('mobitraq_alerts')
            .delete({ count: 'exact' })
            .lt('created_at', alertCutoff.toISOString())

        if (alertsError) {
            console.error('Error deleting alerts:', alertsError)
        }

        // Clean up orphaned session rollups (sessions that were deleted)
        await supabase.rpc('cleanup_orphaned_rollups')

        return new Response(JSON.stringify({
            message: 'Retention cleanup complete',
            retention_days: retentionDays,
            cutoff_date: cutoffIso,
            deleted: {
                location_points: deletedPoints ?? 0,
                timeline_events: deletedEvents ?? 0,
                alerts: deletedAlerts ?? 0,
            },
        }), {
            headers: { 'Content-Type': 'application/json' },
        })

    } catch (error) {
        return new Response(JSON.stringify({ error: error.message }), {
            status: 500,
            headers: { 'Content-Type': 'application/json' },
        })
    }
})
