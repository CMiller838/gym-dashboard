// ADR 001 (docs/ARCHITECTURE.md): this service worker exists ONLY to make
// registration.showNotification() callable for background timer alerts.
// No fetch handler, no push/pushManager, no Background Sync — do not add one.
self.addEventListener('install', (event) => { self.skipWaiting(); });
self.addEventListener('activate', (event) => { event.waitUntil(self.clients.claim()); });
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      if(list.length > 0) return list[0].focus();
      return self.clients.openWindow('./');
    })
  );
});
