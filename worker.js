// POOL — archive worker (Cloudflare Worker + D1). Lampwrecked.
// Stores every gesture forever. Numbers only: no text, no IPs, no ids beyond a row number.
//
// Needs one D1 database bound to this Worker with the variable name: DB
// The table creates itself on the first request.
//
//   POST /g                 save one gesture   {t, a, f:[[ms,x,y,...],...]}
//   GET  /since?id=N        gestures newer than row N (for live replay)  → {items, max}
//   GET  /random?n=60       random gestures from all of history          → {items, max}
//   GET  /count             → {max}
//   GET  /export?after=N    up to 500 rows after N, for your own backups → {items, max}

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET,POST,OPTIONS',
  'access-control-allow-headers': 'content-type',
};
const json = (o, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json', ...CORS } });

let ready = false;
async function setup(db) {
  if (ready) return;
  await db.prepare('CREATE TABLE IF NOT EXISTS g (id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, t INTEGER NOT NULL, data TEXT NOT NULL)').run();
  ready = true;
}

// strict cleaning: anything that isn't a small whole number in range is rejected
const int = (v, lo, hi) => Number.isInteger(v) && v >= lo && v <= hi;
function clean(g) {
  if (!g || typeof g !== 'object') return null;
  if (!int(g.t, 0, 9) || !int(g.a, 100, 4000) || !Array.isArray(g.f)) return null;
  if (g.f.length < 1 || g.f.length > 5) return null;
  const f = [];
  for (const arr of g.f) {
    if (!Array.isArray(arr) || arr.length < 3 || arr.length > 1350 || arr.length % 3) return null;
    let prevT = -1;
    for (let i = 0; i < arr.length; i += 3) {
      if (!int(arr[i], 0, 20000) || arr[i] < prevT) return null;
      if (!int(arr[i + 1], -100, 1100) || !int(arr[i + 2], -100, 1100)) return null;
      prevT = arr[i];
    }
    f.push(arr);
  }
  return { t: g.t, a: g.a, f };
}

// light rate limit per visitor (in memory, per Worker instance; nothing is stored)
const hits = new Map();
function limited(req) {
  const ip = req.headers.get('cf-connecting-ip') || 'x';
  const now = Date.now(), h = hits.get(ip) || [];
  const recent = h.filter(t => now - t < 10000); recent.push(now); hits.set(ip, recent);
  if (hits.size > 5000) hits.clear();
  return recent.length > 40; // more than 40 gestures in 10s
}

const rows = r => (r.results || []).map(x => ({ id: x.id, g: JSON.parse(x.data) }));
async function maxId(db) { const r = await db.prepare('SELECT MAX(id) AS m FROM g').first(); return (r && r.m) || 0; }

export default {
  async fetch(req, env) {
    if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
    if (!env.DB) return json({ error: 'No D1 database bound as DB' }, 500);
    const db = env.DB; await setup(db);
    const url = new URL(req.url), p = url.pathname;

    if (req.method === 'POST' && p === '/g') {
      if (limited(req)) return json({ error: 'slow down' }, 429);
      const body = await req.text();
      if (body.length > 20000) return json({ error: 'too big' }, 413);
      let g; try { g = clean(JSON.parse(body)); } catch (e) { g = null; }
      if (!g) return json({ error: 'not a gesture' }, 400);
      const r = await db.prepare('INSERT INTO g (ts, t, data) VALUES (?, ?, ?)').bind(Date.now(), g.t, JSON.stringify(g)).run();
      return json({ ok: true, id: r.meta && r.meta.last_row_id });
    }

    if (req.method === 'GET' && p === '/since') {
      const id = Math.max(0, parseInt(url.searchParams.get('id')) || 0);
      const m = await maxId(db);
      if (id === 0) return json({ items: [], max: m });
      const r = await db.prepare('SELECT id, data FROM g WHERE id > ? ORDER BY id LIMIT 40').bind(id).all();
      return json({ items: rows(r), max: m });
    }

    if (req.method === 'GET' && p === '/random') {
      const n = Math.min(100, Math.max(1, parseInt(url.searchParams.get('n')) || 60));
      const m = await maxId(db);
      if (!m) return json({ items: [], max: 0 });
      const ids = new Set(); const want = Math.min(n, m);
      while (ids.size < want) ids.add(1 + Math.floor(Math.random() * m));
      const list = [...ids];
      const r = await db.prepare(`SELECT id, data FROM g WHERE id IN (${list.map(() => '?').join(',')})`).bind(...list).all();
      return json({ items: rows(r), max: m });
    }

    if (req.method === 'GET' && p === '/count') return json({ max: await maxId(db) });

    if (req.method === 'GET' && p === '/export') {
      const after = Math.max(0, parseInt(url.searchParams.get('after')) || 0);
      const r = await db.prepare('SELECT id, ts, data FROM g WHERE id > ? ORDER BY id LIMIT 500').bind(after).all();
      return json({ items: (r.results || []).map(x => ({ id: x.id, ts: x.ts, g: JSON.parse(x.data) })), max: await maxId(db) });
    }

    return json({ pool: 'ok' });
  },
};
