// Treska relay: one shared reader of ZET's GTFS-RT feed and timetable ZIP.
//
// Every app polls this Worker instead of zet.hr, so ZET sees roughly one
// client per Cloudflare location no matter how many people use Treska.
// The bytes are passed through untouched; the app still parses ZET's own
// protobuf and shows its own header timestamp, so a stale copy is visible
// as such in the app.

const RT_URL = 'https://zet.hr/gtfs-rt-protobuf';
const STATIC_URL = 'https://zet.hr/gtfs-scheduled/latest';
// The ~19 MB timetable ZIP changes a few times a week; edge copies live 1 h.
const STATIC_CACHE_S = 3600;
const USER_AGENT = 'Treska-relay/1.0 (Cloudflare Worker; ZET timetable)';

// A copy younger than this is served as is. Kept short so the relay adds at
// most a second to ZET's own ~10 s update cycle; ZET still sees at most one
// request per second per Cloudflare location.
const FRESH_MS = 1000;
// When ZET fails, the last good copy is still served for this long.
const STALE_MS = 60000;
const UPSTREAM_TIMEOUT_MS = 8000;

// Shared Cache API key. On a workers.dev hostname the Cache API is a no-op;
// the in-memory copy below then does the work per isolate.
const CACHE_KEY = 'https://treska-relay.internal/rt';

let last = null; // { body: ArrayBuffer, at: epoch ms }
let pending = null; // in-flight upstream fetch, shared by concurrent requests
let failedAt = 0; // last upstream failure; ZET is not retried more often than FRESH_MS

async function fetchUpstream() {
  const response = await fetch(RT_URL, {
    headers: { 'User-Agent': USER_AGENT, 'Cache-Control': 'no-cache' },
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
  });
  if (!response.ok) throw new Error(`ZET HTTP ${response.status}`);
  const body = await response.arrayBuffer();
  if (body.byteLength < 100) throw new Error('ZET empty response');
  return { body, at: Date.now() };
}

async function fromCache() {
  try {
    const hit = await caches.default.match(CACHE_KEY);
    if (!hit) return null;
    const at = Number(hit.headers.get('X-Fetched-At'));
    if (!at) return null;
    return { body: await hit.arrayBuffer(), at };
  } catch {
    return null;
  }
}

function toCache(ctx, copy) {
  const response = new Response(copy.body, {
    headers: {
      'Content-Type': 'application/x-protobuf',
      'Cache-Control': `max-age=${Math.ceil(STALE_MS / 1000)}`,
      'X-Fetched-At': String(copy.at),
    },
  });
  ctx.waitUntil(caches.default.put(CACHE_KEY, response).catch(() => {}));
}

function reply(copy, status) {
  return new Response(copy.body, {
    headers: {
      'Content-Type': 'application/x-protobuf',
      'Cache-Control': 'no-store',
      'X-Relay-Age-Ms': String(Math.max(0, Date.now() - copy.at)),
      'X-Relay-Status': status,
    },
  });
}

const fresh = (copy) => copy && Date.now() - copy.at < FRESH_MS;

async function realtime(ctx) {
  if (fresh(last)) return reply(last, 'memory');

  const cached = await fromCache();
  if (cached && (!last || cached.at > last.at)) last = cached;
  if (fresh(last)) return reply(last, 'cache');

  const recentlyFailed = Date.now() - failedAt < FRESH_MS;
  try {
    if (recentlyFailed) throw new Error('ZET failed recently');
    pending ??= fetchUpstream().finally(() => {
      pending = null;
    });
    const copy = await pending;
    if (!last || copy.at > last.at) {
      last = copy;
      toCache(ctx, copy);
    }
    return reply(last, 'upstream');
  } catch (e) {
    if (!recentlyFailed) failedAt = Date.now();
    if (last && Date.now() - last.at < STALE_MS) return reply(last, 'stale');
    return new Response(`upstream error: ${e.message}`, { status: 502 });
  }
}

// Streams the timetable ZIP through Cloudflare's cache. The app's conditional
// headers are forwarded, so an unchanged feed is still a 304.
async function timetable(request) {
  const headers = { 'User-Agent': USER_AGENT };
  for (const name of ['If-None-Match', 'If-Modified-Since']) {
    const value = request.headers.get(name);
    if (value) headers[name] = value;
  }
  try {
    return await fetch(STATIC_URL, {
      headers,
      cf: { cacheTtl: STATIC_CACHE_S, cacheEverything: true },
    });
  } catch (e) {
    return new Response(`upstream error: ${e.message}`, { status: 502 });
  }
}

export default {
  async fetch(request, env, ctx) {
    const { pathname } = new URL(request.url);
    if (request.method !== 'GET') {
      return new Response('method not allowed', { status: 405 });
    }
    if (pathname === '/rt') return realtime(ctx);
    if (pathname === '/static') return timetable(request);
    if (pathname === '/') return new Response('Treska relay\n');
    return new Response('not found', { status: 404 });
  },
};
