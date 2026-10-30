// AIGC MCP client (streamable HTTP JSON-RPC) + asset generation pipeline.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const MCP_URL = process.env.AIGC_MCP_URL || 'http://18.143.229.110:8782/mcp';
const RPC_TIMEOUT_MS = 120000;
const CALL_ATTEMPTS = 4;
const RETRY_BASE_MS = 800;
const RETRY_MAX_MS = 8000;
const POLL_MS = 3000;
const MAX_POLL_FAILURES = 5;

let session = null;
let rpcId = 10;

const active = signal => { if (signal?.aborted) throw signal.reason || new Error('素材任务已停止'); };
const networkSignal = (signal, ms) => signal ? AbortSignal.any([signal, AbortSignal.timeout(ms)]) : AbortSignal.timeout(ms);
export const sleep = (ms, signal) => new Promise((resolve, reject) => {
  if (signal?.aborted) { reject(signal.reason || new Error('素材任务已停止')); return; }
  const stop = () => { clearTimeout(timer); reject(signal.reason || new Error('素材任务已停止')); };
  const timer = setTimeout(() => { signal?.removeEventListener('abort', stop); resolve(); }, ms);
  signal?.addEventListener('abort', stop, { once: true });
});

// ---------------------------------------------------------------- pure helpers (unit-tested)

/** An MCP/HTTP failure with retry classification. */
export class McpError extends Error {
  constructor(message, { status = 0, retryable = false, session = false } = {}) {
    super(message);
    this.name = 'McpError';
    this.status = status;
    this.retryable = retryable;
    this.session = session;
  }
}

/** Network errors, timeouts, 5xx and 429 are worth retrying; protocol/tool errors are not. */
export function isRetryable(err) {
  if (!err) return false;
  if (err instanceof McpError) return err.retryable || err.session;
  return ['AbortError', 'TimeoutError', 'TypeError'].includes(err.name) || /ECONNRESET|ECONNREFUSED|ETIMEDOUT|EAI_AGAIN|socket|network|fetch failed/i.test(String(err.message || err));
}

/** Exponential backoff with +-25% jitter, capped. */
export function backoffMs(attempt, base = RETRY_BASE_MS, cap = RETRY_MAX_MS, rand = Math.random) {
  const raw = Math.min(cap, base * 2 ** attempt);
  return Math.round(raw * (0.75 + rand() * 0.5));
}

/** Pick the JSON-RPC response out of a plain-JSON or SSE ("data: ...") body. */
export function parseRpcBody(text) {
  const t = String(text || '').trim();
  if (t.startsWith('{')) {
    try { return JSON.parse(t); } catch { return null; }
  }
  let msg = null;
  for (const line of t.split(/\r?\n/)) {
    if (!line.startsWith('data:')) continue;
    try {
      const m = JSON.parse(line.slice(5));
      if (m && m.id !== undefined && m.id !== null) msg = m;
    } catch { /* keep scanning: partial or keep-alive lines */ }
  }
  return msg;
}

/** Classify an HTTP status before the body is interpreted. */
export function httpError(status, text) {
  if (status === 404 || status === 400) return new McpError('MCP 会话失效 (' + status + ')', { status, session: true });
  if (status === 429 || status >= 500) return new McpError('素材服务暂时不可用 (HTTP ' + status + ')', { status, retryable: true });
  if (status >= 300) return new McpError('素材服务请求失败 (HTTP ' + status + '): ' + String(text).slice(0, 160), { status });
  return null;
}

/** Concatenate the text blocks of a tools/call result. */
export function toolResultText(result) {
  return ((result && result.content) || []).map(c => c.text || '').join('\n');
}

/** Task id from a submit reply ("任务ID: xxx" / "task_id: xxx" / JSON). */
export function parseTaskId(text) {
  const m = String(text).match(/(?:任务\s*ID|task[_\s-]?id)["']?\s*[:：=]\s*["']?([\w-]+)/i);
  return m ? m[1] : null;
}

/** Readable reason when a submit reply carries no task id. */
export function submitError(tool, text) {
  const t = String(text || '').replace(/\s+/g, ' ').trim();
  const reason = (t.match(/(?:error|错误|失败|reason)[^:：]*[:：]\s*(.{1,160})/i) || [])[1] || t.slice(0, 160) || '空响应';
  return new Error('素材任务提交失败（' + tool + '）：' + reason);
}

const DONE = ['completed', 'succeeded', 'success', 'done', 'finished'];
const FAILED = ['failed', 'error', 'cancelled', 'canceled', 'timeout'];

/** Parse a get_task_status reply into { state: 'done'|'failed'|'running', raw, urls }. */
export function parseTaskStatus(text) {
  const t = String(text || '');
  const raw = ((t.match(/(?:状态|status)["']?\s*[:：=]\s*["']?(\w+)/i) || [])[1] || '').toLowerCase();
  const state = DONE.includes(raw) ? 'done' : FAILED.includes(raw) ? 'failed' : 'running';
  return { state, raw, urls: state === 'done' ? extractUrls(t) : [] };
}

/** Result URLs: explicit "url=" fields first, else any http(s) URL; de-duplicated, trailing punctuation trimmed. */
export function extractUrls(text) {
  const clean = u => u.replace(/["'),.;\]}>]+$/, '');
  let urls = [...String(text).matchAll(/url\s*=\s*(\S+)/g)].map(m => clean(m[1]));
  if (!urls.length) urls = [...String(text).matchAll(/https?:\/\/[^\s"'<>]+/g)].map(m => clean(m[0]));
  return [...new Set(urls.filter(u => /^https?:\/\//.test(u)))];
}

/** Prefer a .glb, then .fbx, then whatever came back. */
export function pickModelUrl(urls) {
  return urls.find(u => /\.glb(\?|$)/i.test(u)) || urls.find(u => /\.fbx(\?|$)/i.test(u)) || urls[0];
}

const STYLE_WORDS = {
  pixel: 'pixel art, 16-bit retro game style, crisp pixels',
  cartoon: 'cute cartoon game art, bold outlines, vibrant flat colors',
  handdrawn: 'hand-drawn storybook illustration, watercolor and ink',
  lowpoly: 'low poly stylized, clean shapes',
  realistic: 'detailed stylized realistic game art',
  anime: 'anime style game art, cel shaded',
};

export function styleWords(style) { return STYLE_WORDS[style] || style || STYLE_WORDS.cartoon; }

/**
 * Style suffix shared by every image prompt of a game: the art bible (one consistent look per game)
 * plus the base style keywords. Accepts the game meta or, for older callers, a bare style string.
 */
export function styleSuffix(meta) {
  const m = typeof meta === 'string' ? { style: meta } : (meta || {});
  const bible = String(m.art_bible || '').trim();
  const base = styleWords(m.style);
  return bible ? bible + ', ' + base : base;
}

const IMAGE_SUFFIX = {
  sprite: 'single isolated game sprite, full body, centered, side view, plain pure white background, no text, no shadow, no frame',
  background: 'wide game background scenery, side-scrolling backdrop, no characters, no text, no UI',
  texture: 'seamless tileable square game texture, flat orthographic, evenly lit, no text',
  model3d: 'single 3D game asset concept, full object, centered, three-quarter view, plain white background, no text',
  keyart: 'finished in-game screenshot, keep the exact layout, camera angle, object positions and UI placement of the reference image',
};

/** Final image prompt: subject, then the game's shared style, then kind-specific framing. */
export function imagePrompt(kind, subject, meta) {
  return [String(subject || '').trim(), styleSuffix(meta), IMAGE_SUFFIX[kind]].filter(Boolean).join(', ');
}

// ---------------------------------------------------------------- MCP transport

async function rpc(method, params, isNotification = false, signal) {
  active(signal);
  const headers = { 'content-type': 'application/json', accept: 'application/json, text/event-stream' };
  if (session) headers['mcp-session-id'] = session;
  const body = isNotification ? { jsonrpc: '2.0', method, params } : { jsonrpc: '2.0', id: ++rpcId, method, params };
  const res = await fetch(MCP_URL, { method: 'POST', headers, body: JSON.stringify(body), signal: networkSignal(signal, RPC_TIMEOUT_MS) });
  const sid = res.headers.get('mcp-session-id');
  if (sid) session = sid;
  if (isNotification) return null;
  const text = await res.text();
  const httpErr = httpError(res.status, text);
  if (httpErr) throw httpErr;
  const msg = parseRpcBody(text);
  if (!msg) throw new McpError('素材服务返回了空响应', { retryable: true });
  if (msg.error) throw new McpError('素材服务错误：' + (msg.error.message || JSON.stringify(msg.error)).slice(0, 200));
  return msg.result;
}

async function ensureSession(signal) {
  active(signal);
  if (session) return;
  await rpc('initialize', { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 'ugc-platform', version: '0.1' } }, false, signal);
  await rpc('notifications/initialized', undefined, true, signal);
}

/** Call an MCP tool; retries network errors / 5xx / expired sessions with exponential backoff. */
export async function callTool(name, args, { signal } = {}) {
  for (let attempt = 0; ; attempt++) {
    try {
      active(signal);
      await ensureSession(signal);
      return toolResultText(await rpc('tools/call', { name, arguments: args }, false, signal));
    } catch (e) {
      active(signal);
      if (e.session || !(e instanceof McpError)) session = null;
      if (attempt >= CALL_ATTEMPTS - 1 || !isRetryable(e)) throw e;
      await sleep(backoffMs(attempt), signal);
    }
  }
}

async function submit(name, args, signal) {
  const text = await callTool(name, args, { signal });
  const id = parseTaskId(text);
  if (!id) throw submitError(name, text);
  return id;
}

async function waitTask(taskId, timeoutMs, onTick, signal) {
  const t0 = Date.now();
  let failures = 0;
  while (Date.now() - t0 < timeoutMs) {
    await sleep(POLL_MS, signal);
    let text;
    try {
      text = await callTool('get_task_status', { task_id: taskId }, { signal });
      failures = 0;
    } catch (e) {
      active(signal);
      if (++failures >= MAX_POLL_FAILURES) throw new Error('无法查询素材任务进度：' + (e.message || e));
      continue;
    }
    const st = parseTaskStatus(text);
    onTick?.(st.raw, Date.now() - t0);
    if (st.state === 'done') {
      if (!st.urls.length) throw new Error('素材任务完成但没有返回文件地址');
      return st.urls;
    }
    if (st.state === 'failed') throw new Error('素材任务' + st.raw + '：' + String(text).replace(/\s+/g, ' ').slice(0, 200));
  }
  throw new Error('素材生成超时（' + Math.round(timeoutMs / 1000) + ' 秒）');
}

// ---------------------------------------------------------------- asset pipeline

const IMAGE_EXTS = ['.png', '.jpg', '.webp'];
export function imageExt(bytes) {
  if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return '.png';
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return '.jpg';
  if (bytes.length >= 12 && bytes.toString('latin1', 0, 4) === 'RIFF' && bytes.toString('latin1', 8, 12) === 'WEBP') return '.webp';
  return '';
}

export class AssetFactory {
  constructor(dataDir) {
    this.dir = path.join(dataDir, 'assets');
    fs.mkdirSync(this.dir, { recursive: true });
  }

  /** Image services may answer a .png request with JPEG or WebP bytes; the extension must match the bytes. */
  async download(url, ext, signal) {
    active(signal);
    const stem = crypto.createHash('sha1').update(url).digest('hex').slice(0, 20);
    const image = IMAGE_EXTS.includes(ext);
    const cached = image ? IMAGE_EXTS.map(e => stem + e).find(n => fs.existsSync(path.join(this.dir, n))) : null;
    if (cached) return '/assets/' + cached;
    let name = stem + ext;
    let file = path.join(this.dir, name);
    if (!fs.existsSync(file)) {
      let lastErr;
      for (let attempt = 0; attempt < CALL_ATTEMPTS; attempt++) {
        try {
          active(signal);
          const res = await fetch(url, { signal: networkSignal(signal, 180000) });
          if (!res.ok) {
            lastErr = new McpError('素材下载失败 (HTTP ' + res.status + ')', { status: res.status, retryable: res.status >= 500 || res.status === 429 });
            if (!lastErr.retryable) throw lastErr;
          } else {
            const bytes = Buffer.from(await res.arrayBuffer());
            const actual = image ? imageExt(bytes) : '';
            if (actual && actual !== ext) { name = stem + actual; file = path.join(this.dir, name); }
            const tmp = file + '.part';
            active(signal);
            fs.writeFileSync(tmp, bytes);
            fs.renameSync(tmp, file);
            lastErr = null;
            break;
          }
        } catch (e) {
          active(signal);
          lastErr = e;
          if (!isRetryable(e)) throw e;
        }
        await sleep(backoffMs(attempt), signal);
      }
      if (lastErr) throw lastErr;
    }
    return '/assets/' + name;
  }

  /** a.refs are reference images (URLs or data URLs) for image-to-image; a.styled means a.prompt
   *  already carries the final style, so the game's art bible is not appended again. */
  async image(kind, a, meta, width, height, signal) {
    const refs = Array.isArray(a.refs) ? a.refs.filter(Boolean).slice(0, 4) : [];
    const prompt = a.styled ? [String(a.prompt || '').trim(), IMAGE_SUFFIX[kind]].filter(Boolean).join(', ') : imagePrompt(kind, a.prompt, meta);
    const id = await submit('generate_image_async', { prompt, provider: 'nanobanana', width, height, ...(refs.length ? { images: refs } : {}) }, signal);
    const [url] = await waitTask(id, 180000, undefined, signal);
    return url;
  }

  async cutout(url, signal) {
    const rb = await submit('removebg', { image_url: url }, signal);
    const [cut] = await waitTask(rb, 120000, undefined, signal);
    return cut;
  }

  /**
   * Generate one asset. meta is the game meta (style + art_bible; a bare style string is accepted).
   * onStage(stage, extra) reports visual progress stages.
   */
  async generate(a, meta, onStage, { signal } = {}) {
    active(signal);
    switch (a.kind) {
      case 'sprite': {
        onStage('drawing');
        const raw = await this.image('sprite', a, meta, 1024, 1024, signal);
        onStage('cutout', { preview: raw });
        try {
          return { url: await this.download(await this.cutout(raw, signal), '.png', signal), source: raw };
        } catch {
          active(signal);
          return { url: await this.download(raw, '.png', signal), source: raw, warning: 'removebg failed' };
        }
      }
      case 'background': {
        onStage('drawing');
        return { url: await this.download(await this.image('background', a, meta, 1536, 864, signal), '.png', signal) };
      }
      case 'texture': {
        onStage('drawing');
        return { url: await this.download(await this.image('texture', a, meta, 1024, 1024, signal), '.png', signal) };
      }
      case 'keyart': {
        onStage('drawing');
        const [w, h] = meta?.orientation === 'portrait' ? [864, 1536] : [1536, 864];
        const raw = await this.image('keyart', a, meta, w, h, signal);
        return { url: await this.download(raw, '.png', signal), source: raw };
      }
      case 'model3d': {
        onStage('drawing');
        // Image first (fast + previewable), then image-to-3D.
        const img = await this.image('model3d', a, meta, 1024, 1024, signal);
        onStage('sculpting', { preview: img });
        try {
          const mid = await submit('generate_3d_model_async', { image_url: img, provider: process.env.UGC_3D_PROVIDER || 'hunyuan_3d', face_count: 3000 }, signal);
          const urls = await waitTask(mid, Number(process.env.UGC_3D_TIMEOUT || 360000), (st, ms) => onStage('sculpting', { elapsed: ms }), signal);
          const model = pickModelUrl(urls);
          return { url: await this.download(model, /\.fbx(\?|$)/i.test(model) ? '.fbx' : '.glb', signal), preview: img };
        } catch (e) {
          active(signal);
          // 3D sculpting failed or is too slow: fall back to a cut-out billboard of the concept art.
          onStage('cutout', { preview: img, fallback: true });
          let src = img;
          try { src = await this.cutout(img, signal); } catch { active(signal); }
          return { url: await this.download(src, '.png', signal), preview: img, kind: 'sprite', fallback: String(e.message || e).slice(0, 120) };
        }
      }
      case 'music': {
        onStage('composing');
        const id = await submit('generate_music_async', { prompt: a.prompt + ', instrumental game background music loop', format: 'mp3' }, signal);
        const [u] = await waitTask(id, 420000, undefined, signal);
        return { url: await this.download(u, '.mp3', signal) };
      }
      case 'sfx': {
        onStage('recording');
        const id = await submit('generate_sound_effects_async', { prompt: a.prompt + ', short game sound effect' }, signal);
        const [u] = await waitTask(id, 120000, undefined, signal);
        return { url: await this.download(u, '.mp3', signal) };
      }
      default:
        throw new Error('未知素材类型 ' + a.kind);
    }
  }
}
