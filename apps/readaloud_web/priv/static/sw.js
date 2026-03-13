const CACHE_NAME = "readaloud-v1";
const STATIC_ASSETS = [
	"/assets/css/app.css",
	"/assets/js/app.js",
	"/fonts/Inter-Variable.woff2",
];

self.addEventListener("install", (event) => {
	event.waitUntil(
		caches.open(CACHE_NAME).then((cache) => cache.addAll(STATIC_ASSETS)),
	);
	self.skipWaiting();
});

self.addEventListener("activate", (event) => {
	event.waitUntil(
		caches
			.keys()
			.then((keys) =>
				Promise.all(
					keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)),
				),
			),
	);
	self.clients.claim();
});

self.addEventListener("fetch", (event) => {
	const url = new URL(event.request.url);

	// Never cache WebSocket upgrades
	if (event.request.headers.get("upgrade") === "websocket") return;

	// Network-first for HTML and API
	if (
		event.request.mode === "navigate" ||
		url.pathname.startsWith("/api/") ||
		url.pathname.startsWith("/live/")
	) {
		event.respondWith(
			fetch(event.request).catch(() => caches.match(event.request)),
		);
		return;
	}

	// Cache-first for static assets
	if (
		url.pathname.startsWith("/assets/") ||
		url.pathname.startsWith("/fonts/") ||
		url.pathname.startsWith("/images/")
	) {
		event.respondWith(
			caches.match(event.request).then((cached) => {
				return (
					cached ||
					fetch(event.request).then((response) => {
						const clone = response.clone();
						caches
							.open(CACHE_NAME)
							.then((cache) => cache.put(event.request, clone));
						return response;
					})
				);
			}),
		);
		return;
	}

	// Default: network-first
	event.respondWith(
		fetch(event.request).catch(() => caches.match(event.request)),
	);
});
