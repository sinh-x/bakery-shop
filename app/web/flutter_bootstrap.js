{{flutter_js}}
{{flutter_build_config}}

// Cleanup: unregister any existing service worker and clear caches
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then(function(registrations) {
    for (var i = 0; i < registrations.length; i++) {
      registrations[i].unregister();
    }
  });
  if ('caches' in window) {
    caches.keys().then(function(names) {
      for (var i = 0; i < names.length; i++) {
        caches.delete(names[i]);
      }
    });
  }
}

// Load Flutter WITHOUT service worker
_flutter.loader.load();
