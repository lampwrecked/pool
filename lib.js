// pool — gesture codec + tiny Ethereum helpers (no libraries). Lampwrecked.
(function () {
  const MAX_BYTES = 6144, MAX_STROKES = 40, MAX_MS = 10000;

  // ---------- encode a 10-second session ----------
  // strokes: [{ t:type, f:[[ms,x,y, ms,x,y, ...], ...] }]  ms = since the session began, x/y 0..1000
  function encode(strokes, aspect) {
    strokes = strokes.filter(s => s.f.some(a => a.length >= 3)).slice(0, MAX_STROKES)
      .map(s => ({ t: s.t | 0, f: s.f.filter(a => a.length >= 3).slice(0, 5).map(clean) }));
    if (!strokes.length) return null;
    let step = 1, out;
    for (;;) {
      out = pack(strokes, aspect, step);
      if (out.length <= MAX_BYTES || step > 64) break;
      step++;
    }
    return out.length <= MAX_BYTES ? out : null;
  }
  function clean(a) { // clamp, keep inside 10s, ascending time
    const r = []; let last = -1;
    for (let i = 0; i < a.length; i += 3) {
      const t = Math.min(MAX_MS, Math.max(last, Math.round(a[i])));
      if (t > MAX_MS) break;
      r.push(t, Math.max(0, Math.min(1000, Math.round(a[i + 1]))), Math.max(0, Math.min(1000, Math.round(a[i + 2]))));
      last = t;
    }
    return r;
  }
  function pack(strokes, aspect, step) {
    const b = [];
    const u16 = v => b.push((v >> 8) & 255, v & 255);
    b.push(1); u16(Math.max(100, Math.min(4000, Math.round(aspect * 1000)))); b.push(strokes.length);
    for (const s of strokes) {
      b.push(Math.max(0, Math.min(9, s.t)), s.f.length);
      for (const a of s.f) {
        // thin the points (keep first and last), then split any gap over 255ms
        const pts = [];
        const n0 = a.length / 3;
        for (let i = 0; i < n0; i++) if (i % step === 0 || i === n0 - 1) pts.push([a[i * 3], a[i * 3 + 1], a[i * 3 + 2]]);
        const seq = [pts[0]];
        for (let i = 1; i < pts.length; i++) {
          let prev = seq[seq.length - 1];
          while (pts[i][0] - prev[0] > 255) { prev = [prev[0] + 255, prev[1], prev[2]]; seq.push(prev); }
          seq.push(pts[i]);
        }
        u16(seq.length); u16(seq[0][0]); u16(seq[0][1]); u16(seq[0][2]);
        for (let i = 1; i < seq.length; i++) { b.push(seq[i][0] - seq[i - 1][0]); u16(seq[i][1]); u16(seq[i][2]); }
      }
    }
    return new Uint8Array(b);
  }

  // ---------- decode ----------
  // → { a: aspect, dur, strokes:[{ t, start, f:[[ms-from-stroke-start, x, y, ...]] }] }
  function decode(b) {
    try {
      if (!b || b.length < 12 || b[0] !== 1) return null;
      const u16 = i => (b[i] << 8) | b[i + 1];
      const a = u16(1) / 1000, ns = b[3];
      let p = 4, dur = 0;
      const strokes = [];
      for (let s = 0; s < ns; s++) {
        const t = b[p], nf = b[p + 1]; p += 2;
        const f = [];
        for (let k = 0; k < nf; k++) {
          const n = u16(p); let ms = u16(p + 2);
          const arr = [ms, u16(p + 4), u16(p + 6)]; p += 8;
          for (let i = 1; i < n; i++) { ms += b[p]; arr.push(ms, u16(p + 1), u16(p + 3)); p += 5; }
          f.push(arr); dur = Math.max(dur, ms);
        }
        const start = Math.min(...f.map(x => x[0]));
        for (const x of f) for (let i = 0; i < x.length; i += 3) x[i] -= start;
        strokes.push({ t, start, f });
      }
      if (p !== b.length) return null;
      return { a, dur, strokes };
    } catch (e) { return null; }
  }

  // ---------- hex / ABI ----------
  const hex = u8 => Array.from(u8, x => x.toString(16).padStart(2, '0')).join('');
  const unhex = h => { h = h.replace(/^0x/, ''); const o = new Uint8Array(h.length / 2); for (let i = 0; i < o.length; i++) o[i] = parseInt(h.substr(i * 2, 2), 16); return o; };
  const word = n => BigInt(n).toString(16).padStart(64, '0');
  const SEL = { mint: '7ba0e2e7', totalSupply: '18160ddd', gestures: 'b4eb4f38', hasMinted: '38e21cce', mintOpen: '24bbd049',
    rewrite: '203c1e11', tokensOf: '5a3f2672', writeFile: '2e038106', setMintOpen: 'f8004d31', setRewriteOpen: 'a01d9148',
    withdraw: '3ccfd60b', freezeFiles: '4d86d83d', owner: '8da5cb5b', filesFrozen: '420a47c1', rewriteOpen: '82f8e2a2',
    poolHTML: '894308fb', mintHTML: '7634820a', file: 'aa70dd94' };
  const REWRITE_WEI = '0x2386f26fc10000';   // 0.01 ETH
  const TRANSFER = '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef';
  function encMint(bytes) {
    const h = hex(bytes), pad = h.padEnd(Math.ceil(h.length / 64) * 64, '0');
    return '0x' + SEL.mint + word(32) + word(bytes.length) + pad;
  }
  const encGestures = (from, count) => '0x' + SEL.gestures + word(from) + word(count);
  const padBytes = u8 => { const h = hex(u8); return word(u8.length) + h.padEnd(Math.ceil(h.length / 64) * 64, '0'); };
  const encRewrite = (id, bytes) => '0x' + SEL.rewrite + word(id) + word(64) + padBytes(bytes);
  const encWriteFile = (slot, bytes, replace) => '0x' + SEL.writeFile + word(slot) + word(96) + word(replace ? 1 : 0) + padBytes(bytes);
  const encBool = (sel, v) => '0x' + sel + word(v ? 1 : 0);
  const encUint = (sel, v) => '0x' + sel + word(v);
  function decBytes(h) { const d = unhex(h); if (d.length < 64) return new Uint8Array(0);
    const W = i => Number(BigInt('0x' + hex(d.slice(i, i + 32)))); const off = W(0), len = W(off); return d.slice(off + 32, off + 32 + len); }
  function decUintArray(h) { const d = unhex(h); if (d.length < 64) return [];
    const W = i => Number(BigInt('0x' + hex(d.slice(i, i + 32)))); const off = W(0), n = W(off); return Array.from({ length: n }, (_, i) => W(off + 32 + i * 32)); }
  const encAddr = (sel, addr) => '0x' + sel + addr.replace(/^0x/, '').toLowerCase().padStart(64, '0');
  function decBytesArray(h) {
    const d = unhex(h); if (d.length < 64) return [];
    const W = i => Number(BigInt('0x' + hex(d.slice(i, i + 32))));
    const base = W(0), n = W(base), list = [];
    for (let i = 0; i < n; i++) {
      const off = base + 32 + W(base + 32 + i * 32);
      const len = W(off);
      list.push(d.slice(off + 32, off + 32 + len));
    }
    return list;
  }
  const decUint = h => Number(BigInt(h && h !== '0x' ? h : '0x0'));

  // ---------- read-only RPC with fallbacks ----------
  function cfg() { return window.POOL_CONFIG || {}; }
  const DEFAULT_RPC = { 1: ['https://ethereum-rpc.publicnode.com', 'https://eth.llamarpc.com', 'https://cloudflare-eth.com'],
    11155111: ['https://ethereum-sepolia-rpc.publicnode.com', 'https://rpc.sepolia.org'] };
  function rpcList() { const c = cfg(); const id = c.chainId || 1;
    const own = id === 11155111 ? c.sepoliaRpc : c.rpc; return (own && own.length ? own : DEFAULT_RPC[id]) || []; }
  let good = 0;
  async function rpc(method, params) {
    const list = rpcList(); let err;
    for (let k = 0; k < list.length; k++) {
      const url = list[(good + k) % list.length];
      try {
        const r = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }) });
        const j = await r.json();
        if (j.error) throw new Error(j.error.message);
        good = (good + k) % list.length; return j.result;
      } catch (e) { err = e; }
    }
    throw err || new Error('no rpc');
  }
  const call = (data) => rpc('eth_call', [{ to: cfg().contract, data }, 'latest']);

  async function totalSupply() { return decUint(await call('0x' + SEL.totalSupply)); }
  async function readGestures(from, count) { return decBytesArray(await call(encGestures(from, count))); }

  const b64ToBytes = s => Uint8Array.from(atob(s), c => c.charCodeAt(0));
  window.POOLLIB = { encode, decode, hex, unhex, encMint, encRewrite, encWriteFile, encBool, encUint, encAddr, decUint, decBytes, decUintArray,
    b64ToBytes, SEL, REWRITE_WEI, TRANSFER, rpc, call, totalSupply, readGestures, MAX_MS, MAX_BYTES };
})();
