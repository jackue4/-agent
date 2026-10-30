import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const DEFAULT_MODEL = 'kimi-k3.1-pro-highspeed';
/** The sketch artist draws 20–40 short rounds per build, so it keeps its own fast model. A round
 * with no stroke within 25 s is abandoned; on 2026-10-30 deepseek-v4.1-flash and kimi needed
 * 30–95 s before their first stroke, the gpt-5.4 mini/nano models 2–4 s. */
export const SKETCH_MODEL = 'gpt-5.4-mini';
export const SKETCH_FALLBACK_MODEL = 'gpt-5.4-nano';
// IDs verified against this gateway's /v1/models catalogue, 2026-10-29.
// Each entry completed a function-tool call. Labels name that entry, never an alias.
export const MODEL_CATALOG = Object.freeze([
  { id: 'claude-opus-5-5', label: 'Opus 5.5' },
  { id: 'claude-opus-5', label: 'Opus 5' },
  { id: 'claude-opus-4-8', label: 'Opus 4.8' },
  { id: 'claude-sonnet-5-5', label: 'Sonnet 5.5' },
  { id: 'gpt-6.1-sol', label: 'GPT 6.1 Sol' },
  { id: 'gpt-6.1-terra', label: 'GPT 6.1 Terra' },
  { id: 'gpt-6-sol', label: 'GPT 6 Sol' },
  { id: 'gpt-6-luna', label: 'GPT 6 Luna' },
  { id: 'gpt-6-astra', label: 'GPT 6 Astra' },
  { id: 'gpt-5.6-sol', label: 'GPT 5.6 Sol' },
  { id: 'gpt-5.6-luna', label: 'GPT 5.6 Luna' },
  { id: 'gpt-5.6-terra', label: 'GPT 5.6 Terra' },
  { id: 'gpt-5.5', label: 'GPT 5.5' },
  { id: 'gpt-5.4-pro', label: 'GPT 5.4 Pro' },
  { id: 'gpt-5.4', label: 'GPT 5.4' },
  { id: 'gpt-5.4-mini', label: 'GPT 5.4 Mini' },
  { id: 'gpt-5.4-nano', label: 'GPT 5.4 Nano' },
  { id: 'gpt-5.2', label: 'GPT 5.2' },
  { id: 'deepseek-v4.1-flash', label: 'DeepSeek V4.1 Flash' },
  { id: 'kimi-k3.1-pro-highspeed', label: 'Kimi K3.1 高速' },
].map(option => Object.freeze(option)));
const catalogIds = new Set(MODEL_CATALOG.map(option => option.id));
export const MODEL_CONFIG_PATH = process.env.UGC_MODEL_CONFIG || path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'model-config.local.json');
const validModel = value => typeof value === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9._:/-]{0,127}$/.test(value);

/** Platform-local model names only. Invalid settings fail loudly; no request/model fallback. */
export function loadModelConfig({ env = process.env, configPath = MODEL_CONFIG_PATH, readFile = fs.readFileSync } = {}) {
  let local = {}, present = false;
  try {
    local = JSON.parse(readFile(configPath, 'utf8')); present = true;
  } catch (error) {
    if (error.code !== 'ENOENT') throw new Error('平台模型配置无法读取或不是有效 JSON');
  }
  if (!local || typeof local !== 'object' || Array.isArray(local) || Object.keys(local).some(key => !['model', 'codeModel', 'models'].includes(key))) throw new Error('平台模型配置仅允许 model、codeModel 和 models 字段，不应包含凭据');
  for (const key of ['model', 'codeModel']) if (Object.hasOwn(local, key) && !validModel(local[key])) throw new Error('平台模型配置字段无效：' + key);
  let models = null;
  if (Object.hasOwn(local, 'models')) {
    if (!Array.isArray(local.models) || !local.models.length || local.models.some(id => !catalogIds.has(id))) throw new Error('平台模型配置字段无效：models');
    models = Object.freeze([...new Set(local.models)]);
  }
  for (const key of ['UGC_MODEL', 'UGC_CODE_MODEL']) if (Object.hasOwn(env, key) && !validModel(env[key])) throw new Error('平台模型环境变量无效：' + key);
  const choose = entries => entries.find(entry => entry.value !== undefined);
  const primary = choose([{ value: env.UGC_MODEL, source: 'env:UGC_MODEL' }, { value: local.model, source: 'local:model' }, { value: DEFAULT_MODEL, source: 'default' }]);
  const code = choose([{ value: env.UGC_CODE_MODEL, source: 'env:UGC_CODE_MODEL' }, { value: env.UGC_MODEL, source: 'env:UGC_MODEL' }, { value: local.codeModel, source: 'local:codeModel' }, { value: local.model, source: 'local:model' }, { value: DEFAULT_MODEL, source: 'default' }]);
  if (models && (!models.includes(primary.value) || !models.includes(code.value))) throw new Error('平台默认模型必须在 models 列表中');
  return Object.freeze({ model: primary.value, codeModel: code.value, modelSource: primary.source, codeModelSource: code.source, configFile: present ? configPath : null, models });
}

export const MODEL_SETTINGS = loadModelConfig();
/** A `models` list in the local config limits what users see and may pick; stored choices outside it run on the default. */
export const MODEL_OPTIONS = MODEL_SETTINGS.models ? Object.freeze(MODEL_CATALOG.filter(option => MODEL_SETTINGS.models.includes(option.id))) : MODEL_CATALOG;
const selectableModels = new Set(MODEL_OPTIONS.map(option => option.id));

/** Explicit project selection must be a verified catalogue ID; no friendly aliases. */
export function assertModelSelection(value) {
  if (typeof value !== 'string' || !selectableModels.has(value)) throw new Error('请选择当前模型列表中的有效模型');
  return value;
}

/** Missing legacy values retain the administrator's configured default, even outside
 * the public catalogue. Explicit selections are always strict. */
export function resolveModelSelection(value, { defaultModel = MODEL_SETTINGS.codeModel, locked = Boolean(MODEL_SETTINGS.models) } = {}) {
  if (value === undefined || value === null || (locked && !selectableModels.has(value))) {
    if (!validModel(defaultModel)) throw new Error('平台默认模型配置无效');
    return defaultModel;
  }
  return assertModelSelection(value);
}
