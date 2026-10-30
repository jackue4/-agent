// Tolerant JSON parsing for model output (tool arguments, SSE payloads, MCP replies).
// Repairs harmless formatting glitches only; truncated documents are rejected so callers never act on
// half an object.

const stripFences = s => s.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
const stripTrailingCommas = s => s.replace(/,(\s*[}\]])/g, '$1');

/** Outermost {...} or [...] span of a string, or null. */
function outerSpan(s) {
  const i = s.search(/[{[]/);
  if (i < 0) return null;
  const close = s[i] === '{' ? '}' : ']';
  const j = s.lastIndexOf(close);
  return j > i ? s.slice(i, j + 1) : null;
}

function scanJson(s) {
  const stack = [];
  const cuts = [];
  let inStr = false, esc = false;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (inStr) {
      if (esc) esc = false;
      else if (c === '\\') esc = true;
      else if (c === '"') inStr = false;
      continue;
    }
    if (c === '"') inStr = true;
    else if (c === '{' || c === '[') { stack.push(c === '{' ? '}' : ']'); cuts.push(i + 1); }
    else if (c === '}' || c === ']') stack.pop();
    else if (c === ',') cuts.push(i);
  }
  return { stack, cuts, inStr, esc };
}

/**
 * Best-effort parse of a JSON document that is still streaming in (tool input deltas): open strings,
 * arrays and objects are closed, and an incomplete trailing member is dropped. Returns null when
 * nothing usable has arrived yet. Only for progress display - never act on the result.
 */
export function parsePartialJson(text) {
  if (typeof text !== 'string') return null;
  let cur = text.trimEnd();
  for (let attempt = 0; attempt < 12 && cur; attempt++) {
    const { stack, cuts, inStr, esc } = scanJson(cur);
    let t = cur;
    if (inStr) {
      if (esc) t = t.slice(0, -1);
      t = t.replace(/\\u[0-9a-fA-F]{0,3}$/, '') + '"';
    }
    t = t.replace(/[\s,:]+$/, '');
    try { return JSON.parse(t + stack.slice().reverse().join('')); } catch { /* cut back below */ }
    const cut = cuts.filter(c => c < cur.length).pop();
    if (cut === undefined) return null;
    cur = cur.slice(0, cut);
  }
  return null;
}

/** Parse JSON, tolerating code fences, trailing commas and surrounding prose. Returns fallback on failure. */
export function parseLooseJson(text, fallback = null) {
  if (typeof text !== 'string') return fallback;
  const s = stripFences(text.trim());
  const span = outerSpan(s);
  for (const c of [s, stripTrailingCommas(s), span, span && stripTrailingCommas(span)]) {
    if (!c) continue;
    try { return JSON.parse(c); } catch {}
  }
  return fallback;
}
