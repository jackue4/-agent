// Art director: from the second round on, it turns a pencil Demo into final art without blocking
// the builder. One planning call names the final style; a style key frame is repainted from the
// real pencil screenshot (same layout, finished look); every art slot is then drawn against that
// key frame so the whole set stays consistent. Jobs outlive the round that started them.
import { runAgent } from './agent.mjs';
import { CODE_MODEL } from './codegen.mjs';

export const ART_LIMITS = { perRun: 24, perGame: 96 };
export const STYLE_KEY = 'art_style';
export const SLOT_ID = /^[a-z][a-z0-9_]{1,30}$/;
const PENCIL_COLORS = new Set(['red', 'orange', 'yellow', 'green', 'teal', 'blue', 'purple', 'pink', 'brown', 'gray', 'ink', 'paper']);
const SLOT_CALL = /Pencil\s*\.\s*(sprite|texture|backdrop|material|actor3d|has_art|art_path)\s*\(([^\n]*)/g;
const KIND_OF = { sprite: 'sprite', texture: 'sprite', actor3d: 'sprite', has_art: 'sprite', art_path: 'sprite', backdrop: 'background', material: 'texture' };
const SLOT_KINDS = ['sprite', 'background', 'texture'];

/** Art slots referenced from GDScript: Pencil.sprite("hero", ...), Pencil.material(tint, "wall"), … */
export function artSlotsIn(sources = {}) {
  const slots = new Map();
  for (const [file, src] of Object.entries(sources)) {
    if (!/\.(gd|tscn)$/.test(file)) continue;
    let dynamicUse = '';
    for (const m of String(src).matchAll(SLOT_CALL)) {
      const args = m[2].replace(/(?:Pencil\s*\.\s*)?color\s*\(\s*"[^"]*"[^)]*\)/gi, '').replace(/Color\s*\([^)]*\)/g, '');
      const id = m[1] === 'backdrop' ? args.match(/^\s*"([a-z][a-z0-9_]{1,30})"/)?.[1] || (/^\s*\)/.test(args) ? 'background' : '') : args.match(/"([a-z][a-z0-9_]{1,30})"/)?.[1];
      if (!id && /^\s*[a-z_]\w*\s*,/i.test(args) && (!dynamicUse || KIND_OF[m[1]] === 'sprite')) dynamicUse = m[1];
      if (!id || PENCIL_COLORS.has(id) || id === STYLE_KEY || slots.has(id)) continue;
      const size = args.match(/Vector2\s*\(\s*([\d.]+)\s*,\s*([\d.]+)\s*\)/);
      slots.set(id, { id, kind: KIND_OF[m[1]], use: m[1], file, ...(size ? { size: [Number(size[1]), Number(size[2])] } : {}) });
    }
    // An id passed through a variable (helper(id) -> Pencil.actor3d(id, ...)) is found where it is
    // assigned to an art-named variable or key.
    if (!dynamicUse) continue;
    for (const m of String(src).matchAll(/(?:\b(?:\w+_)?art(?:_id)?\s*:?=\s*|"(?:art|art_id)"\s*:\s*)"([a-z][a-z0-9_]{1,30})"/g)) {
      const id = m[1];
      if (PENCIL_COLORS.has(id) || id === STYLE_KEY || slots.has(id)) continue;
      slots.set(id, { id, kind: KIND_OF[dynamicUse], use: dynamicUse, file });
    }
  }
  return [...slots.values()];
}

/** Design-level slots (design.art) merged with the ones actually used by code; code wins on kind. */
export function mergeSlots(designArt = [], codeSlots = []) {
  const out = new Map();
  for (const a of Array.isArray(designArt) ? designArt : []) {
    const id = String(a?.id || '').trim();
    if (SLOT_ID.test(id) && id !== STYLE_KEY) out.set(id, { id, kind: SLOT_KINDS.includes(a.kind) ? a.kind : 'sprite', name: String(a.name || '').slice(0, 20), look: String(a.prompt || a.look || '').slice(0, 300), planned: true });
  }
  for (const s of codeSlots) out.set(s.id, { ...out.get(s.id), ...s, used: true });
  return [...out.values()];
}

export const PLAN_ART_TOOL = {
  name: 'plan_art',
  description: 'Plan the final art that replaces the pencil placeholders of this game.',
  input_schema: {
    type: 'object', required: ['style', 'key_prompt', 'slots'],
    properties: {
      style: { type: 'string', description: 'English, 1-2 sentences: the finished art direction for the whole game (rendering style, materials, lighting, palette mood). Must fit the genre and the design art bible; it is no longer pencil.' },
      key_prompt: { type: 'string', description: 'English: how to repaint the attached pencil screenshot into the finished game frame in that style. Name what each pencil shape is (hero, enemies, floor, walls, UI…).' },
      slots: { type: 'array', items: { type: 'object', required: ['id', 'prompt'], properties: {
        id: { type: 'string' },
        kind: { type: 'string', enum: SLOT_KINDS },
        name: { type: 'string', description: '中文名，≤8 字' },
        prompt: { type: 'string', description: 'English: one single subject, its look, colors, facing/view (sprites: full body, isolated; textures: seamless surface material; backgrounds: scenery only).' },
      } } },
    },
  },
};

const PLAN_SYSTEM = [
  'You are the art director of a small game studio. The game was prototyped with hand-drawn pencil placeholders; every placeholder is an art slot with a stable id that the code already loads from res://assets/<id>.png.',
  'Decide one finished art style that suits the game, then write image prompts so every slot can be generated in that same style. Keep every slot id exactly as given; do not invent ids for code that does not use them, but you may keep planned slots.',
  'Sprites are single isolated subjects on a plain white background (they are cut out automatically). Textures are seamless tileable surfaces seen straight on. Backgrounds are scenery without characters or UI.',
  'Call plan_art exactly once.',
].join('\n');

function planBrief(design = {}, meta = {}, slots = []) {
  return [
    'Game: ' + (design.title || meta.title || '') + ' — ' + (design.pitch || meta.pitch || ''),
    'Genre: ' + (design.genre || meta.genre || '') + '; ' + (design.dimension === '3d' || meta.dimension === '3d' ? '3D, ' : '2D, ') + (meta.orientation === 'portrait' ? 'portrait' : 'landscape'),
    'Design art bible: ' + (design.art_bible || meta.art_bible || '(none)'),
    ...(design.art_request ? ['The player asked for finished art with these words; any style they name overrides the art bible: ' + design.art_request] : []),
    'Palette: ' + (design.palette || meta.palette || []).join(' '),
    'Art slots (id | kind | how the code uses it | planned look):',
    ...slots.map(s => '- ' + s.id + ' | ' + s.kind + ' | ' + (s.use ? 'Pencil.' + s.use + (s.size ? ' size ' + s.size.join('x') : '') + ' in ' + s.file : 'planned, not yet in code') + (s.look ? ' | ' + s.look : '')),
    'The attached image is the current pencil Demo as the player sees it.',
  ].join('\n');
}

/** One LLM call: style, key-frame prompt and per-slot prompts. */
export async function planArt({ design, meta, slots, shot, model = process.env.UGC_ART_MODEL || CODE_MODEL, signal, agentRunner = runAgent, fetchImpl }) {
  let plan = null;
  const content = [{ type: 'text', text: planBrief(design, meta, slots) }];
  if (shot) content.push({ type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: shot } });
  await agentRunner({
    messages: [{ role: 'user', content }], signal, cb: {}, maxTurns: 2, finishTools: ['plan_art'],
    ...(fetchImpl ? { deps: { fetchImpl } } : {}),
    req: { model, system: PLAN_SYSTEM, tools: [PLAN_ART_TOOL], max_tokens: 8000 },
    exec: async (name, input) => { if (name !== 'plan_art') return { error: 'only plan_art' }; plan = input; return { ok: true }; },
  });
  if (!plan?.style) throw new Error('美术规划没有返回风格');
  const byId = new Map(slots.map(s => [s.id, s]));
  const out = [];
  for (const s of Array.isArray(plan.slots) ? plan.slots : []) {
    const slot = byId.get(String(s?.id || ''));
    if (!slot || !String(s.prompt || '').trim() || out.some(o => o.id === slot.id)) continue;
    out.push({ id: slot.id, kind: slot.use ? slot.kind : SLOT_KINDS.includes(s.kind) ? s.kind : slot.kind, name: String(s.name || slot.name || slot.id).slice(0, 20), prompt: String(s.prompt).slice(0, 500) });
  }
  for (const slot of slots) if (slot.used && !out.some(o => o.id === slot.id)) out.push({ id: slot.id, kind: slot.kind, name: slot.name || slot.id, prompt: slot.look || slot.id.replace(/_/g, ' ') });
  return { style: String(plan.style).slice(0, 600), keyPrompt: String(plan.key_prompt || '').slice(0, 900), slots: out };
}

export function slotPrompt(slot, style) {
  const subject = slot.kind === 'sprite' ? 'Draw only this single subject, isolated and centered on a plain pure white background, matching the art style of the reference image: '
    : slot.kind === 'texture' ? 'A seamless tileable surface texture, matching the materials and colors of the reference image: '
      : 'Background scenery only, matching the world and style of the reference image: ';
  return subject + slot.prompt + '. Style: ' + style;
}

/**
 * Orchestrates one art pass. deps:
 *  slots(): merged slot list; shot(): base64 jpeg of the current game; design(), meta();
 *  existing(): {id: asset}; generate(asset): Promise<{url, source}> (style key only);
 *  enqueue(asset): queues one slot (returns '' or why not); emit(event); plan(args) (tests).
 */
export class ArtDirector {
  constructor(deps) {
    this.deps = deps;
    this.abort = new AbortController();
    this.state = 'idle';
    this.done = null;
  }
  /** Planning and the style key; queued slot jobs run on in the shared asset queue. */
  get running() { return this.state === 'planning' || this.state === 'styling'; }
  stop(reason = '美术任务已停止') { this.abort.abort(new Error(reason)); }
  status(extra = {}) { this.deps.emit?.({ type: 'art', state: this.state, ...extra }); }

  start() {
    if (this.running) return this.done;
    this.done = this.run().catch(error => {
      this.state = this.abort.signal.aborted ? 'stopped' : 'failed';
      this.status({ error: String(error?.message || error).slice(0, 200) });
    });
    return this.done;
  }

  async run() {
    const { deps } = this, signal = this.abort.signal;
    const existing = deps.existing();
    const generated = Object.values(existing).filter(a => a.async).length;
    const todo = deps.slots().filter(s => !existing[s.id] || existing[s.id].state === 'failed');
    const room = Math.max(0, Math.min(ART_LIMITS.perRun, ART_LIMITS.perGame - generated));
    if (!todo.length || !room) { this.state = 'idle'; if (todo.length) this.status({ note: '美术素材已达上限' }); return; }
    this.state = 'planning'; this.status({ slots: todo.length });
    const shot = deps.shot();
    const plan = await retry(() => (deps.plan || planArt)({ design: deps.design(), meta: deps.meta(), slots: todo.slice(0, room), shot, signal }), signal, deps.retryMs);
    if (signal.aborted) throw signal.reason;
    this.plan = plan;
    let key = existing[STYLE_KEY]?.state === 'ready' ? existing[STYLE_KEY] : null;
    let note = '';
    if (!key) {
      this.state = 'styling'; this.status({ style: plan.style });
      const spec = { id: STYLE_KEY, kind: 'keyart', name: '画风定稿', styled: true, refs: shot ? ['data:image/jpeg;base64,' + shot] : [],
        prompt: 'Repaint this hand-drawn pencil game prototype as the finished game. ' + plan.keyPrompt + ' Style: ' + plan.style };
      try { key = await retry(() => deps.generateKey(spec, signal), signal, deps.retryMs); }
      catch (e) {
        if (signal.aborted) throw e;
        note = '风格定稿图暂未生成（' + String(e.message || e).slice(0, 80) + '），先按文字画风绘制';
      }
    }
    const ref = key?.source || key?.preview || '';
    this.state = 'drawing';
    const queued = [];
    for (const slot of plan.slots) {
      const err = deps.enqueue({ id: slot.id, kind: slot.kind, name: slot.name, styled: true, async: true, refs: ref ? [ref] : [], prompt: slotPrompt(slot, plan.style) }, signal);
      if (!err) queued.push(slot.id);
    }
    this.status({ style: plan.style, key: key?.url || '', image: key?.url || '', queued, ...(note ? { note } : {}) });
    this.state = 'done';
  }
}

/** One retry after a short pause: image and model services fail transiently. */
async function retry(fn, signal, waitMs = 8000) {
  try { return await fn(); }
  catch (e) {
    if (signal.aborted) throw signal.reason ?? e;
    await new Promise(r => setTimeout(r, waitMs));
    if (signal.aborted) throw signal.reason;
    return fn();
  }
}
