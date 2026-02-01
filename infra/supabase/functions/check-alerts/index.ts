// Supabase Edge Function: Check and Create Alerts
// Per industry-grade specification Section 10
// 
// This function checks for stuck and no-signal conditions during active sessions
// Run every 5 minutes via cron

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Configuration (matching mobitraq_config table)
const STUCK_RADIUS_M = 150
const STUCK_MIN_DURATION_MIN = 30
const NO_SIGNAL_TIMEOUT_MIN = 20
const EARTH_RADIUS_KM = 6371

serve(async (req) => {
    try {
        const supabase = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // Get all active sessions
        const { data: activeSessions, error: sessionsError } = await supabase
            .from('shift_sessions')
            .select(`
        id,
        employee_id,
        start_time,
        employees!inner(name, device_token)
      `)
            .eq('status', 'active')

        if (sessionsError) {
            throw new Error(`Failed to fetch sessions: ${sessionsError.message}`)
        }

        if (!activeSessions || activeSessions.length === 0) {
            return new Response(JSON.stringify({
                message: 'No active sessions to check',
            }), {
                headers: { 'Content-Type': 'application/json' },
            })
        }

        const alertsCreated: any[] = []
        const alertsClosed: any[] = []

        for (const session of activeSessions) {
            // Check for stuck condition
            const stuckResult = await checkStuckCondition(supabase, session)
            if (stuckResult.createAlert) {
                alertsCreated.push(stuckResult.alert)

                // Send FCM notification
                if (session.employees?.device_token) {
                    await sendFCMAlert(session.employees.device_token, stuckResult.alert)
                }
            } else if (stuckResult.closeAlert) {
                alertsClosed.push(stuckResult.alertId)
            }

            // Check for no-signal condition
            const noSignalResult = await checkNoSignalCondition(supabase, session)
            if (noSignalResult.createAlert) {
                alertsCreated.push(noSignalResult.alert)

                if (session.employees?.device_token) {
                    await sendFCMAlert(session.employees.device_token, noSignalResult.alert)
                }
            } else if (noSignalResult.closeAlert) {
                alertsClosed.push(noSignalResult.alertId)
            }
        }

        return new Response(JSON.stringify({
            message: 'Alert check complete',
            sessions_checked: activeSessions.length,
            alerts_created: alertsCreated.length,
            alerts_closed: alertsClosed.length,
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

// Check if employee is stuck
async function checkStuckCondition(supabase: any, session: any) {
    // Get recent points for this session (last hour)
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString()

    const { data: points, error } = await supabase
        .from('location_points')
        .select('latitude, longitude, recorded_at')
        .eq('session_id', session.id)
        .gte('recorded_at', oneHourAgo)
        .order('recorded_at', { ascending: false })
        .limit(100)

    if (error || !points || points.length < 2) {
        return { createAlert: false, closeAlert: false }
    }

    // Find anchor point (oldest in recent window)
    const anchorPoint = points[points.length - 1]
    const latestPoint = points[0]

    // Check if all points are within stuck radius
    let allWithinRadius = true
    for (const point of points) {
        const distance = haversineDistanceMeters(
            anchorPoint.latitude, anchorPoint.longitude,
            point.latitude, point.longitude
        )
        if (distance > STUCK_RADIUS_M) {
            allWithinRadius = false
            break
        }
    }

    // Check duration
    const anchorTime = new Date(anchorPoint.recorded_at)
    const latestTime = new Date(latestPoint.recorded_at)
    const durationMin = (latestTime.getTime() - anchorTime.getTime()) / (1000 * 60)

    // Check for existing open stuck alert
    const { data: existingAlert } = await supabase
        .from('mobitraq_alerts')
        .select('id')
        .eq('session_id', session.id)
        .eq('alert_type', 'stuck')
        .eq('is_open', true)
        .single()

    if (allWithinRadius && durationMin >= STUCK_MIN_DURATION_MIN) {
        if (existingAlert) {
            // Already have open alert
            return { createAlert: false, closeAlert: false }
        }

        // Create new stuck alert
        const alert = {
            employee_id: session.employee_id,
            session_id: session.id,
            alert_type: 'stuck',
            severity: 'warn',
            message: `Employee stuck at location for ${Math.round(durationMin)} minutes`,
            start_time: anchorTime.toISOString(),
            lat: anchorPoint.latitude,
            lng: anchorPoint.longitude,
            is_open: true,
        }

        await supabase.from('mobitraq_alerts').insert(alert)
        return { createAlert: true, alert }
    } else if (existingAlert && !allWithinRadius) {
        // Movement detected, close alert
        await supabase
            .from('mobitraq_alerts')
            .update({
                is_open: false,
                end_time: new Date().toISOString()
            })
            .eq('id', existingAlert.id)

        return { createAlert: false, closeAlert: true, alertId: existingAlert.id }
    }

    return { createAlert: false, closeAlert: false }
}

// Check for no-signal condition
async function checkNoSignalCondition(supabase: any, session: any) {
    // Get last point for this session
    const { data: lastPoint, error } = await supabase
        .from('location_points')
        .select('recorded_at')
        .eq('session_id', session.id)
        .order('recorded_at', { ascending: false })
        .limit(1)
        .single()

    const now = new Date()

    // Check for existing open no_signal alert
    const { data: existingAlert } = await supabase
        .from('mobitraq_alerts')
        .select('id')
        .eq('session_id', session.id)
        .eq('alert_type', 'no_signal')
        .eq('is_open', true)
        .single()

    if (!lastPoint) {
        // No points at all, check session start time
        const sessionStart = new Date(session.start_time)
        const minutesSinceStart = (now.getTime() - sessionStart.getTime()) / (1000 * 60)

        if (minutesSinceStart >= NO_SIGNAL_TIMEOUT_MIN && !existingAlert) {
            const alert = {
                employee_id: session.employee_id,
                session_id: session.id,
                alert_type: 'no_signal',
                severity: 'critical',
                message: `No location data received since session started (${Math.round(minutesSinceStart)} minutes)`,
                start_time: sessionStart.toISOString(),
                is_open: true,
            }

            await supabase.from('mobitraq_alerts').insert(alert)
            return { createAlert: true, alert }
        }
        return { createAlert: false, closeAlert: false }
    }

    const lastPointTime = new Date(lastPoint.recorded_at)
    const minutesSinceLastPoint = (now.getTime() - lastPointTime.getTime()) / (1000 * 60)

    if (minutesSinceLastPoint >= NO_SIGNAL_TIMEOUT_MIN) {
        if (existingAlert) {
            return { createAlert: false, closeAlert: false }
        }

        const alert = {
            employee_id: session.employee_id,
            session_id: session.id,
            alert_type: 'no_signal',
            severity: 'critical',
            message: `No location data received for ${Math.round(minutesSinceLastPoint)} minutes`,
            start_time: lastPointTime.toISOString(),
            is_open: true,
        }

        await supabase.from('mobitraq_alerts').insert(alert)
        return { createAlert: true, alert }
    } else if (existingAlert) {
        // Signal resumed, close alert
        await supabase
            .from('mobitraq_alerts')
            .update({
                is_open: false,
                end_time: now.toISOString()
            })
            .eq('id', existingAlert.id)

        return { createAlert: false, closeAlert: true, alertId: existingAlert.id }
    }

    return { createAlert: false, closeAlert: false }
}

// Send FCM push notification
async function sendFCMAlert(deviceToken: string, alert: any) {
    try {
        const fcmKey = Deno.env.get('FCM_SERVER_KEY')
        if (!fcmKey) {
            console.warn('FCM_SERVER_KEY not configured')
            return
        }

        const response = await fetch('https://fcm.googleapis.com/fcm/send', {
            method: 'POST',
            headers: {
                'Authorization': `key=${fcmKey}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                to: deviceToken,
                notification: {
                    title: `Alert: ${alert.alert_type === 'stuck' ? 'Employee Stuck' : 'No Signal'}`,
                    body: alert.message,
                },
                data: {
                    type: 'alert',
                    alert_type: alert.alert_type,
                    session_id: alert.session_id,
                },
            }),
        })

        if (!response.ok) {
            console.error('FCM send failed:', await response.text())
        }
    } catch (error) {
        console.error('FCM error:', error)
    }
}

// Haversine distance in meters
function haversineDistanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const dLat = toRadians(lat2 - lat1)
    const dLng = toRadians(lng2 - lng1)

    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) *
        Math.sin(dLng / 2) * Math.sin(dLng / 2)

    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

    return 6371 * 1000 * c
}

function toRadians(degrees: number): number {
    return degrees * Math.PI / 180
}
