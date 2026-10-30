export const $ = (s, el = document) => el.querySelector(s);
/** crypto.randomUUID exists only in secure contexts (https, localhost); LAN http addresses lack it. */
export function uuid() {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  const b = crypto.getRandomValues(new Uint8Array(16));
  b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
  const h = Array.from(b, x => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
export const $$ = (s, el = document) => [...el.querySelectorAll(s)];
export async function api(path, opts = {}) {
  const r = await fetch('/api' + path, { method: opts.body ? 'POST' : (opts.method || 'GET'), headers: opts.body ? { 'content-type': 'application/json' } : {}, body: opts.body ? JSON.stringify(opts.body) : undefined });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error || r.status);
  return j;
}
export function esc(s) { return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
export function toast(t, ms = 2200) { const d = document.createElement('div'); d.className = 'toast'; d.textContent = t; document.body.appendChild(d); setTimeout(() => d.remove(), ms); }
export function ago(t) { const s = (Date.now() - t) / 1000; if (s < 60) return '刚刚'; if (s < 3600) return Math.floor(s / 60) + ' 分钟前'; if (s < 86400) return Math.floor(s / 3600) + ' 小时前'; return Math.floor(s / 86400) + ' 天前'; }
export const GENRE_CN = { platformer: '跳跃闯关', topdown: '俯视冒险', shooter: '射击', maze: '迷宫', rpg: '冒险' };
export const STYLE_CN = { pixel: '像素', cartoon: '卡通', handdrawn: '手绘', anime: '动漫', lowpoly: '低多边形' };

// Bridge to the Godot runtime inside an iframe.
export class Runtime {
  constructor(iframe, onEvent) {
    this.f = iframe; this.ready = false; this.q = []; this.onEvent = onEvent || (() => {});
    window.addEventListener('message', e => {
      if (e.source !== iframe.contentWindow || !e.data || !e.data.__ugc) return;
      const ev = e.data.payload;
      if (ev.type === 'ready') { this.ready = true; const q = this.q; this.q = []; q.forEach(m => this._post(m)); }
      this.onEvent(ev);
    });
  }
  static absAssets(assets) {
    const out = {};
    for (const [k, a] of Object.entries(assets || {})) out[k] = { ...a, url: a.url ? new URL(a.url, location.origin).href : '' };
    return out;
  }
  _post(m) { try { this.f.contentWindow.ugcReceive(JSON.stringify(m)); } catch (e) { console.warn('runtime post failed', e); } }
  send(m) {
    if (m.type === 'load' && m.assets) m = { ...m, assets: Runtime.absAssets(m.assets) };
    if (m.type === 'asset' && m.url) m = { ...m, url: new URL(m.url, location.origin).href };
    if (m.type === 'ops') m = { ...m, ops: m.ops.map(o => o.op === 'asset' && o.url ? { ...o, url: new URL(o.url, location.origin).href } : o) };
    if (this.ready) this._post(m); else if (m.type === 'load') { this.q = this.q.filter(x => x.type !== 'load' && x.type !== 'ops'); this.q.push(m); } else this.q.push(m);
  }
  /** Point the frame at another runtime page (Godot-project games: gp.html with the game's pack). */
  reload(src) { this.ready = false; this.q = []; this.f.src = src; }
  focus() { try { this.f.focus(); this.f.contentWindow.focus(); this.f.contentWindow.document.querySelector('canvas')?.focus(); } catch {} }
  snapshot() {
    return new Promise(res => {
      const req = Math.random().toString(36).slice(2);
      const prev = this.onEvent;
      const to = setTimeout(() => { this.onEvent = prev; res(null); }, 4000);
      this.onEvent = ev => { if (ev.type === 'snapshot' && ev.req === req) { clearTimeout(to); this.onEvent = prev; res(ev.data); } else prev(ev); };
      this.send({ type: 'snapshot', req });
    });
  }
}
