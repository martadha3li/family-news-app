const CACHE='family-shell-v11';
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(['/','/style.css','/app.js','/community.mjs','/social.mjs','/family.mjs','/chat-media.mjs','/mentions.mjs','/family-logo.png','/icon-512.png','/auth-callback.mjs','/announcement-time.mjs','/icon.svg','/manifest.webmanifest']))));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k))))));
self.addEventListener('fetch',e=>{if(e.request.method!=='GET'||new URL(e.request.url).origin!==self.location.origin)return;e.respondWith(fetch(e.request).catch(()=>caches.match(e.request).then(r=>r||new Response('يلزم الاتصال بالإنترنت',{status:503}))));});
