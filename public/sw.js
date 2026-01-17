// ============================================================================
// BenzDesk Service Worker
// Handles: Caching, Offline Support, Push Notifications
// ============================================================================

const CACHE_NAME = 'benzdesk-v1.0.3';
const STATIC_ASSETS = [
    '/',
    '/app',
    '/login',
    '/manifest.json',
    '/icon-192.png',
    '/icon-512.png',
];

// ============================================================================
// Install Event - Cache static assets
// ============================================================================
self.addEventListener('install', (event) => {
    console.log('[SW] Installing service worker...');
    event.waitUntil(
        caches.open(CACHE_NAME).then((cache) => {
            console.log('[SW] Caching static assets');
            return cache.addAll(STATIC_ASSETS);
        })
    );
    // Activate immediately
    self.skipWaiting();
});

// ============================================================================
// Activate Event - Clean old caches
// ============================================================================
self.addEventListener('activate', (event) => {
    console.log('[SW] Activating service worker...');
    event.waitUntil(
        caches.keys().then((cacheNames) => {
            return Promise.all(
                cacheNames
                    .filter((name) => name !== CACHE_NAME)
                    .map((name) => {
                        console.log('[SW] Deleting old cache:', name);
                        return caches.delete(name);
                    })
            );
        })
    );
    // Take control of all pages immediately
    self.clients.claim();
});

// ============================================================================
// Fetch Event - Network first, fallback to cache
// ============================================================================
self.addEventListener('fetch', (event) => {
    // Skip non-GET requests
    if (event.request.method !== 'GET') return;

    // Skip API/Supabase requests (always go to network)
    if (event.request.url.includes('supabase.co')) return;

    event.respondWith(
        fetch(event.request)
            .then((response) => {
                // Clone response and cache it
                const responseClone = response.clone();
                caches.open(CACHE_NAME).then((cache) => {
                    cache.put(event.request, responseClone);
                });
                return response;
            })
            .catch(() => {
                // Network failed, try cache
                return caches.match(event.request);
            })
    );
});

// ============================================================================
// Push Event - Handle incoming push notifications
// ============================================================================
self.addEventListener('push', (event) => {
    console.log('[SW] Push received:', event);

    let data = {
        title: 'BenzDesk',
        body: 'You have a new notification',
        icon: '/icon-192.png',
        badge: '/icon-192.png',
        url: '/',
    };

    try {
        if (event.data) {
            data = { ...data, ...event.data.json() };
        }
    } catch (e) {
        console.error('[SW] Error parsing push data:', e);
    }

    const options = {
        body: data.body,
        icon: data.icon || '/icon-192.png',
        badge: data.badge || '/icon-192.png',
        vibrate: [100, 50, 100],
        data: {
            url: data.url || '/',
            dateOfArrival: Date.now(),
        },
        actions: [
            { action: 'open', title: 'Open' },
            { action: 'dismiss', title: 'Dismiss' },
        ],
        requireInteraction: true,
        tag: data.tag || 'benzdesk-notification',
    };

    event.waitUntil(
        self.registration.showNotification(data.title, options)
    );
});

// ============================================================================
// Notification Click Event - Handle notification clicks
// ============================================================================
self.addEventListener('notificationclick', (event) => {
    console.log('[SW] Notification clicked:', event.action);

    event.notification.close();

    if (event.action === 'dismiss') {
        return;
    }

    const urlToOpen = event.notification.data?.url || '/';

    event.waitUntil(
        clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
            // Check if there's already an open window
            for (const client of clientList) {
                if (client.url.includes(self.location.origin) && 'focus' in client) {
                    client.navigate(urlToOpen);
                    return client.focus();
                }
            }
            // Open a new window
            if (clients.openWindow) {
                return clients.openWindow(urlToOpen);
            }
        })
    );
});
