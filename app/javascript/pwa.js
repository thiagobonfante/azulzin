// PWA service worker registration (install-only — no offline caching yet).
// Registers only when the app-host manifest link is present (see layouts/_meta),
// so it never fires a 404 request on the marketing host.
if ("serviceWorker" in navigator && document.querySelector('link[rel="manifest"]')) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/service-worker.js").catch(() => {})
  })
}
