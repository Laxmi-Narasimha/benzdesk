// ============================================================================
// BenzDesk Service Worker
// Handles: Caching, Offline Support, Push Notifications
// ============================================================================

const CACHE_NAME = 'benzdesk-v1.0.11';

// Only cache files that definitely exist
const STATIC_ASSETS = [
    '/',
    '/manifest.json',
];

// ============================================================================
// Install Event - Skip waiting immediately for faster activation
// ============================================================================
self.addEventListener('install', (event) => {
    console.log('[SW] Installing service worker...');

    event.waitUntil(
        caches.open(CACHE_NAME)
            .then((cache) => {
                console.log('[SW] Caching minimal assets');
                // Cache each file individually to avoid failures
                return Promise.all(
                    STATIC_ASSETS.map(url =>
                        cache.add(url).catch(err => {
                            console.warn('[SW] Failed to cache:', url, err);
                            return Promise.resolve(); // Continue even if one fails
                        })
                    )
                );
            })
            .then(() => {
                console.log('[SW] Install complete, skipping waiting');
                return self.skipWaiting();
            })
    );
});

// ============================================================================
// Activate Event - Claim clients immediately
// ============================================================================
self.addEventListener('activate', (event) => {
    console.log('[SW] Activating service worker...');

    event.waitUntil(
        caches.keys()
            .then((cacheNames) => {
                return Promise.all(
                    cacheNames
                        .filter((name) => name !== CACHE_NAME)
                        .map((name) => {
                            console.log('[SW] Deleting old cache:', name);
                            return caches.delete(name);
                        })
                );
            })
            .then(() => {
                console.log('[SW] Taking control of all clients');
                return self.clients.claim();
            })
    );
});

// ============================================================================
// Fetch Event - Network first, fallback to cache
// ============================================================================
self.addEventListener('fetch', (event) => {
    // Skip non-GET requests
    if (event.request.method !== 'GET') return;

    // Skip API/Supabase requests (always go to network)
    if (event.request.url.includes('supabase.co')) return;
    if (event.request.url.includes('googleapis.com')) return;

    event.respondWith(
        fetch(event.request)
            .then((response) => {
                // Only cache successful responses
                if (response.status === 200) {
                    const responseClone = response.clone();
                    caches.open(CACHE_NAME).then((cache) => {
                        cache.put(event.request, responseClone);
                    });
                }
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
    console.log('[SW] Push received!');

    let data = {
        title: 'BenzDesk',
        body: 'You have a new notification',
        icon: '/icon-192.png',
        badge: '/icon-192.png',
        url: '/',
    };

    try {
        if (event.data) {
            const payload = event.data.json();
            console.log('[SW] Push payload:', payload);
            data = { ...data, ...payload };
        }
    } catch (e) {
        console.error('[SW] Error parsing push data:', e);
        if (event.data) {
            data.body = event.data.text();
        }
    }

    const options = {
        body: data.body,
        icon: data.icon || '/icon-192.png',
        badge: data.badge || '/icon-192.png',
        vibrate: [200, 100, 200],
        data: {
            url: data.url || data.data?.url || '/',
            dateOfArrival: Date.now(),
        },
        tag: data.tag || 'benzdesk-notification',
        requireInteraction: true,
        renotify: true,
    };

    event.waitUntil(
        self.registration.showNotification(data.title, options)
            .then(() => console.log('[SW] Notification shown'))
            .catch(err => console.error('[SW] Failed to show notification:', err))
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

console.log('[SW] Service worker script loaded');
