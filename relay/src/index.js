// Treska relay: one shared reader of ZET's GTFS-RT feed and timetable ZIP.
//
// Every app polls this Worker instead of zet.hr, so ZET sees roughly one
// client per Cloudflare location no matter how many people use Treska.
// The bytes are passed through untouched; the app still parses ZET's own
// protobuf and shows its own header timestamp, so a stale copy is visible
// as such in the app.

import { DurableObject } from 'cloudflare:workers';

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

// ── Push ────────────────────────────────────────────────────────────────────
//
// /ws: every app keeps one WebSocket to a single FeedHub. While at least one
// client is connected, the hub checks ZET (see PUSH_* below) and sends the
// protobuf (gzipped) to everyone as soon as it changes. Outgoing WebSocket
// messages are not billed by Cloudflare, so the cost is the hub's own checks
// plus one request per connection, not one per client per poll.

// ZET publishes a new feed every ~10-12 s. Right after one arrives the next
// is not due for a while, so the hub rests, then checks every second until it
// shows up: a new feed reaches the apps within ~1 s, with ~4 checks per cycle
// (~30 000 a day while anyone is connected, inside the free plan's 100 000).
// If ZET stalls, checks slow down so a long outage cannot burn the quota.
const PUSH_REST_MS = 7000;
const PUSH_CHECK_MS = 1000;
const PUSH_STALLED_AFTER_MS = 30000;
const PUSH_STALLED_CHECK_MS = 5000;

const sameBytes = (a, b) => {
  if (a.byteLength !== b.byteLength) return false;
  const x = new Uint8Array(a);
  const y = new Uint8Array(b);
  for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) return false;
  return true;
};

async function gzip(buffer) {
  const stream = new Blob([buffer]).stream().pipeThrough(new CompressionStream('gzip'));
  return new Response(stream).arrayBuffer();
}

export class FeedHub extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.last = null; // { body, at } of the last feed sent
    this.lastGz = null;
    this.changedAt = 0; // when the feed last changed
  }

  async fetch() {
    const [client, server] = Object.values(new WebSocketPair());
    // Hibernation API: clients send nothing, so connected sockets cost no
    // duration on their own; only the check loop below keeps the hub awake.
    this.ctx.acceptWebSocket(server);
    if (this.lastGz && Date.now() - this.last.at < STALE_MS) server.send(this.lastGz);
    if ((await this.ctx.storage.getAlarm()) == null) {
      await this.ctx.storage.setAlarm(Date.now());
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  async alarm() {
    // Nobody listening: stop asking ZET until the next client connects.
    if (this.ctx.getWebSockets().length === 0) return;
    // Rearm first, so a failure below cannot end the loop.
    const stalled = Date.now() - this.changedAt > PUSH_STALLED_AFTER_MS;
    await this.ctx.storage.setAlarm(
      Date.now() + (stalled ? PUSH_STALLED_CHECK_MS : PUSH_CHECK_MS));
    let copy;
    try {
      copy = await fetchUpstream();
    } catch {
      return; // keep the last copy; the next check retries
    }
    if (this.last && sameBytes(this.last.body, copy.body)) {
      this.last.at = copy.at;
      return;
    }
    // The first copy after a cold start is at an unknown point in ZET's cycle,
    // so only a real change starts the rest period.
    if (this.last) await this.ctx.storage.setAlarm(Date.now() + PUSH_REST_MS);
    this.last = copy;
    this.changedAt = copy.at;
    this.lastGz = await gzip(copy.body);
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.send(this.lastGz);
      } catch {
        // A socket that is already closing; its close handler cleans up.
      }
    }
  }

  webSocketMessage() {}

  webSocketClose(ws, code) {
    try {
      ws.close(code, 'closed');
    } catch {}
  }

  webSocketError(ws) {
    try {
      ws.close(1011, 'error');
    } catch {}
  }
}

function push(request, env) {
  if (request.headers.get('Upgrade') !== 'websocket') {
    return new Response('expected websocket', { status: 426 });
  }
  // One hub for all of Zagreb, placed in eastern Europe near ZET.
  const hub = env.HUB.get(env.HUB.idFromName('zagreb'), { locationHint: 'eeur' });
  return hub.fetch(request);
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
    if (pathname === '/ws') return push(request, env);
    if (pathname === '/') return new Response('Treska relay\n');
    return new Response('not found', { status: 404 });
  },
};
