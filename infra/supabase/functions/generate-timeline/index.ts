// Supabase Edge Function: Generate Timeline Events
// Per industry-grade specification Section 9.2
// 
// This function generates timeline events (stops and moves) from location points
// Run hourly or on-demand via cron

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Configuration (matching mobitraq_config table)
const STOP_RADIUS_M = 120
const STOP_MIN_DURATION_SEC = 600 // 10 minutes
const EARTH_RADIUS_KM = 6371

serve(async (req) => {
    try {
        const supabase = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        const { employee_id, date, session_id } = await req.json()

        // Get date range (IST timezone)
        const targetDate = date ? new Date(date) : new Date()
        const startOfDay = new Date(targetDate)
        startOfDay.setHours(0, 0, 0, 0)
        const endOfDay = new Date(targetDate)
        endOfDay.setHours(23, 59, 59, 999)

        // Build query for location points
        let query = supabase
            .from('location_points')
            .select('*')
            .gte('recorded_at', startOfDay.toISOString())
            .lte('recorded_at', endOfDay.toISOString())
            .order('recorded_at', { ascending: true })

        if (employee_id) {
            query = query.eq('employee_id', employee_id)
        }
        if (session_id) {
            query = query.eq('session_id', session_id)
        }

        const { data: points, error: pointsError } = await query

        if (pointsError) {
            throw new Error(`Failed to fetch points: ${pointsError.message}`)
        }

        if (!points || points.length < 2) {
            return new Response(JSON.stringify({
                message: 'Not enough points for timeline generation',
                points_count: points?.length ?? 0
            }), {
                headers: { 'Content-Type': 'application/json' },
            })
        }

        // Group points by session
        const sessionGroups = new Map<string, any[]>()
        for (const point of points) {
            const sid = point.session_id
            if (!sessionGroups.has(sid)) {
                sessionGroups.set(sid, [])
            }
            sessionGroups.get(sid)!.push(point)
        }

        const generatedEvents: any[] = []

        // Process each session
        for (const [sessionId, sessionPoints] of sessionGroups) {
            const events = generateTimelineEvents(sessionPoints)

            for (const event of events) {
                const timelineEvent = {
                    employee_id: sessionPoints[0].employee_id,
                    session_id: sessionId,
                    day: startOfDay.toISOString().split('T')[0],
                    event_type: event.type,
                    start_time: event.startTime,
                    end_time: event.endTime,
                    duration_sec: event.durationSec,
                    distance_km: event.distanceKm,
                    center_lat: event.centerLat,
                    center_lng: event.centerLng,
                    start_lat: event.startLat,
                    start_lng: event.startLng,
                    end_lat: event.endLat,
                    end_lng: event.endLng,
                    point_count: event.pointCount,
                }

                // Upsert to handle re-runs
                const { data, error } = await supabase
                    .from('timeline_events')
                    .upsert(timelineEvent, {
                        onConflict: 'session_id,start_time',
                        ignoreDuplicates: false
                    })

                if (error) {
                    console.error('Error inserting timeline event:', error)
                } else {
                    generatedEvents.push(timelineEvent)
                }
            }
        }

        return new Response(JSON.stringify({
            message: 'Timeline generation complete',
            events_generated: generatedEvents.length,
            sessions_processed: sessionGroups.size,
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

// Generate timeline events from sorted points
function generateTimelineEvents(points: any[]): any[] {
    if (points.length < 2) return []

    const events: any[] = []
    let i = 0

    while (i < points.length) {
        const clusterResult = buildCluster(points, i)

        if (clusterResult.isStop) {
            events.push({
                type: 'stop',
                startTime: clusterResult.startTime,
                endTime: clusterResult.endTime,
                durationSec: clusterResult.durationSec,
                centerLat: clusterResult.centerLat,
                centerLng: clusterResult.centerLng,
                pointCount: clusterResult.pointCount,
            })
        } else if (clusterResult.pointCount > 1) {
            events.push({
                type: 'move',
                startTime: clusterResult.startTime,
                endTime: clusterResult.endTime,
                durationSec: clusterResult.durationSec,
                startLat: clusterResult.startLat,
                startLng: clusterResult.startLng,
                endLat: clusterResult.endLat,
                endLng: clusterResult.endLng,
                distanceKm: clusterResult.distanceKm,
                pointCount: clusterResult.pointCount,
            })
        }

        i += Math.max(1, clusterResult.pointCount)
    }

    return events
}

// Build a cluster starting at given index
function buildCluster(points: any[], startIdx: number) {
    if (startIdx >= points.length) {
        return { pointCount: 0, isStop: false }
    }

    const anchor = points[startIdx]
    const clusterPoints = [anchor]

    let sumLat = anchor.latitude
    let sumLng = anchor.longitude

    let j = startIdx + 1
    while (j < points.length) {
        const point = points[j]
        const distanceM = haversineDistanceMeters(
            anchor.latitude, anchor.longitude,
            point.latitude, point.longitude
        )

        if (distanceM <= STOP_RADIUS_M) {
            clusterPoints.push(point)
            sumLat += point.latitude
            sumLng += point.longitude
            j++
        } else {
            break
        }
    }

    const startTime = new Date(clusterPoints[0].recorded_at)
    const endTime = new Date(clusterPoints[clusterPoints.length - 1].recorded_at)
    const durationSec = Math.floor((endTime.getTime() - startTime.getTime()) / 1000)

    const isStop = durationSec >= STOP_MIN_DURATION_SEC && clusterPoints.length >= 2

    // Calculate total distance for move segments
    let distanceKm = 0
    if (!isStop) {
        for (let k = 1; k < clusterPoints.length; k++) {
            distanceKm += haversineDistanceKm(
                clusterPoints[k - 1].latitude, clusterPoints[k - 1].longitude,
                clusterPoints[k].latitude, clusterPoints[k].longitude
            )
        }
    }

    return {
        pointCount: clusterPoints.length,
        startTime: startTime.toISOString(),
        endTime: endTime.toISOString(),
        durationSec,
        centerLat: sumLat / clusterPoints.length,
        centerLng: sumLng / clusterPoints.length,
        startLat: clusterPoints[0].latitude,
        startLng: clusterPoints[0].longitude,
        endLat: clusterPoints[clusterPoints.length - 1].latitude,
        endLng: clusterPoints[clusterPoints.length - 1].longitude,
        distanceKm,
        isStop,
    }
}

// Haversine distance in meters
function haversineDistanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
    return haversineDistanceKm(lat1, lng1, lat2, lng2) * 1000
}

// Haversine distance in kilometers
function haversineDistanceKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const dLat = toRadians(lat2 - lat1)
    const dLng = toRadians(lng2 - lng1)

    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) *
        Math.sin(dLng / 2) * Math.sin(dLng / 2)

    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

    return EARTH_RADIUS_KM * c
}

function toRadians(degrees: number): number {
    return degrees * Math.PI / 180
}
