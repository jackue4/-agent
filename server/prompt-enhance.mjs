// One short call on a strong model before the weak builder starts. It does not replace the
// user's words: it adds a checklist the builder can follow. A failure leaves the original text.
import { runAgent } from './agent.mjs';

export const ENHANCE_MODEL = process.env.UGC_ENHANCE_MODEL || 'claude-opus-5-5';
const RESUME = /^(继续|接着|下一步|继续做|go on|continue)[\s。！!]*$/i;
const line = (value, max) => String(value || '').replace(/\s+/g, ' ').trim().slice(0, max);
const list = (value, max, itemMax) => (Array.isArray(value) ? value : []).map(item => line(item, itemMax)).filter(Boolean).slice(0, max);

export const BRIEF_TOOL = {
  name: 'write_brief',
  description: '把用户的原话整理成弱模型能照做的制作简报。不改目标，不发挥新玩法。',
  input_schema: {
    type: 'object', required: ['goal', 'playable', 'rules', 'keep', 'avoid'],
    properties: {
      goal: { type: 'string', description: '一句话目标，必须能从用户原话里找到依据' },
      playable: { type: 'string', description: '这一轮结束后玩家能亲手做的一件事' },
      rules: { type: 'array', items: { type: 'string' }, description: '最多 6 条。每条是一个可实现的规则、手感或胜负条件，能写数字就写数字' },
      keep: { type: 'array', items: { type: 'string' }, description: '必须保留的用户原话要点，最多 4 条' },
      avoid: { type: 'array', items: { type: 'string' }, description: '这一轮明确不要做的事，最多 4 条' },
    },
  },
};

const SYSTEM = [
  '你是制作简报编辑。用户的原话会原样交给一个较弱的游戏制作模型，你只补一份简报，帮它少漏、少发挥。',
  '只调用一次 write_brief。目标、可玩片段和规则都必须能从用户原话推出；用户没说的系统、数值和世界观不要新造。',
  '第一轮只要一个能玩的小片段。后续修改只整理这一次改动，不要要求重做整个游戏。',
  '用中文，短句。',
].join('\n');

/** Resume words need no rewrite. The selected builder is already the strong model. */
export function shouldEnhance(text, mainModel, enhanceModel = ENHANCE_MODEL) {
  const value = String(text || '').trim();
  return Boolean(value) && !RESUME.test(value) && mainModel !== enhanceModel && process.env.UGC_ENHANCE !== '0';
}

export function formatBrief(input) {
  const goal = line(input?.goal, 80);
  const playable = line(input?.playable, 120);
  const rules = list(input?.rules, 6, 80);
  const keep = list(input?.keep, 4, 80);
  const avoid = list(input?.avoid, 4, 80);
  if (!goal || !playable) return '';
  return [
    '【制作简报】按下面执行，但用户原话优先。',
    '目标：' + goal,
    '本轮可玩：' + playable,
    rules.length ? '规则：\n' + rules.map(item => '- ' + item).join('\n') : '',
    keep.length ? '必须保留：\n' + keep.map(item => '- ' + item).join('\n') : '',
    avoid.length ? '不要做：\n' + avoid.map(item => '- ' + item).join('\n') : '',
  ].filter(Boolean).join('\n');
}

export function enhanceRequest({ text, isFirst, design }) {
  const lines = ['用户原话：「' + String(text || '').trim().slice(0, 2000) + '」'];
  if (design?.title) lines.push('已有游戏：《' + line(design.title, 40) + '》' + line(design.pitch, 120));
  lines.push(isFirst ? '这是第一轮。' : '这是对已有游戏的一次修改。');
  return lines.join('\n');
}

/** Returns the brief text, or '' when there is nothing useful to add. */
export async function enhanceUserPrompt({ text, isFirst = false, design = null, signal, model = ENHANCE_MODEL, agentRunner = runAgent } = {}) {
  let brief = null;
  const messages = [{ role: 'user', content: enhanceRequest({ text, isFirst, design }) }];
  await agentRunner({
    messages, signal, cb: {}, maxTurns: 2, finishTools: ['write_brief'], idleTimeoutMs: 20000,
    req: { model, system: SYSTEM, tools: [BRIEF_TOOL], max_tokens: 1200 },
    exec: async (name, input) => {
      if (name !== 'write_brief') return { error: 'only write_brief' };
      brief = input;
      return { ok: true };
    },
  });
  return formatBrief(brief);
}
