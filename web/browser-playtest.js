// A separate, command-bound game instance. It never sends input to the author's game.
const identityKeys = ['commandId', 'clientId', 'runtimeSession', 'buildId', 'sourceRevision', 'runId'];
const clip = (value, max = 180) => typeof value === 'string' ? value.slice(0, max) : '';
// crypto.randomUUID is missing outside secure contexts (plain-http LAN addresses).
const randomId = () => typeof crypto.randomUUID === 'function' ? crypto.randomUUID()
  : Array.from(crypto.getRandomValues(new Uint32Array(4)), part => part.toString(16).padStart(8, '0')).join('-');
export function runtimeIdentity(command) {
  return Object.fromEntries([...identityKeys, 'kind'].map(key => [key, command[key]]));
}
export function validRuntimeCommand(command, clientId, runId, now = Date.now()) {
  return Boolean(command && identityKeys.every(key => typeof command[key] === 'string' && command[key])
    && command.clientId === clientId && command.runId === runId
    && ['run', 'eval', 'test', 'stop'].includes(command.kind)
    && Number.isFinite(command.createdAt) && Number.isFinite(command.expiresAt) && command.expiresAt > now
    && typeof command.pckUrl === 'string' && /^\/(?!\/)[^\s<>\\]*$/.test(command.pckUrl));
}
export function runtimePresentation(view) {
  if (!view) return null;
  const passed = { run: '启动完成', eval: '本步操作完成', test: '本次断言检查通过', stop: '已停止' };
  return { label: { run: '实际启动', eval: '实际操作', test: '规则检查', stop: '验收停止' }[view.kind],
    status: view.status === 'passed' ? passed[view.kind] : ({ starting: '正在启动', live: '正在执行', failed: '本步检查未通过', stopped: '本次检查已停止' })[view.status],
    note: view.connectionError || (view.status === 'starting' ? '等待本次游戏绘制首帧' : view.status === 'live' ? '正在此窗口运行真实游戏' : '这是本次实际运行的游戏，可切回制作'),
    checks: (view.checks || []).slice(-3).map(row => (row.ok ? '✓ ' : '× ') + clip(row.what)).join(' · '),
    errors: (view.errors || []).slice(-2).map(error => clip(typeof error === 'string' ? error : error.message)).join('；') };
}
export class BrowserPlaytestController {
  constructor({ projectId, iframe, context, onView = () => {}, fetcher = (...args) => fetch(...args), host = window, clock = () => Date.now(), uuid = randomId, setTimer = setTimeout, clearTimer = clearTimeout }) {
    this.projectId = projectId; this.iframe = iframe; this.context = context; this.onView = onView;
    this.fetcher = fetcher; this.host = host; this.clock = clock; this.uuid = uuid;
    // Browser native timers require the Window receiver, not this controller.
    // Wrapping also retains deterministic timer injection in tests.
    this.setTimer = (callback, delay) => setTimer.call(host, callback, delay);
    this.clearTimer = timer => clearTimer.call(host, timer);
    this.clientId = uuid(); this.current = null; this.session = null; this.view = null; this.active = false;
    this.requests = new Set(); this.completed = new Map(); this.outbox = new Map(); this.delivering = new Set(); this.timer = null; this.deadline = null; this.generation = 0; this.polling = false; this.lastCommandAt = 0;
    this.messageListener = event => this.onMessage(event);
    host.addEventListener('message', this.messageListener);
  }
  async request(path, body, { timeout = 4000, keepalive = false } = {}) {
    const controller = new AbortController(); this.requests.add(controller);
    const timer = this.setTimer(() => controller.abort(), timeout);
    try {
      const response = await this.fetcher('/api/projects/' + encodeURIComponent(this.projectId) + path, {
        method: body ? 'POST' : 'GET', headers: body ? { 'content-type': 'application/json' } : {},
        body: body ? JSON.stringify(body) : undefined, signal: controller.signal, cache: 'no-store', keepalive
      });
      const result = await response.json(); if (!response.ok) throw new Error(result?.error || '连接暂时中断'); return result;
    } finally { this.clearTimer(timer); this.requests.delete(controller); }
  }
  eligible() { const c = this.context(); return Boolean(c.enabled && c.visible && c.mode === 'edit' && c.runId); }
  sync() {
    const eligible = this.eligible();
    if (this.session && this.session.runId !== this.context().runId) { this.cancel('本轮制作已切换'); this.view = null; this.onView(null); }
    if (eligible === this.active) return;
    this.active = eligible; this.generation++;
    if (eligible) this.tick();
    else this.suspend(this.context().mode === 'play' ? '已切换为手动试玩' : '页面暂不可见');
  }
  suspend(reason = '页面暂不可见') {
    this.active = false; this.generation++; this.clearTimer(this.timer); this.timer = null;
    for (const request of this.requests) request.abort();
    this.cancel(reason);
    // The canvas was unloaded. Keep result receipts, but never present it as live.
    this.view = null; this.onView(null);
    this.request('/runtime-client', { clientId: this.clientId, visible: false, supported: true }, { keepalive: true }).catch(() => {});
  }
  async tick() {
    if (!this.active || this.polling) return;
    const generation = this.generation; this.polling = true;
    for (const [key, item] of this.outbox) {
      if (item.at + 30000 < this.clock() || item.attempts >= 8) this.outbox.delete(key);
      else this.deliver(item.body);
    }
    try {
      await this.request('/runtime-client', { clientId: this.clientId, visible: true, supported: true });
      if (!this.active || generation !== this.generation) return;
      const reply = await this.request('/runtime-command?clientId=' + encodeURIComponent(this.clientId));
      if (this.active && generation === this.generation) this.accept(reply?.command ?? reply);
    } catch (error) {
      if (this.active && generation === this.generation && this.view) { this.view = { ...this.view, connectionError: '验收连接中断，正在重连' }; this.onView(this.view); }
    } finally {
      this.polling = false;
      if (this.active) { this.clearTimer(this.timer); this.timer = this.setTimer(() => this.tick(), 2000); }
    }
  }
  accept(command) {
    if (!this.active || !this.eligible() || !validRuntimeCommand(command, this.clientId, this.context().runId, this.clock())) return false;
    if (this.current?.commandId === command.commandId) return true;
    if (this.completed.has(command.commandId)) { this.deliver(this.completed.get(command.commandId)); return true; }
    if (command.createdAt < this.lastCommandAt) return false;
    this.lastCommandAt = command.createdAt;
    if (command.kind === 'stop') {
      if (this.session && ['runtimeSession', 'runId', 'buildId', 'sourceRevision'].some(key => this.session[key] !== command[key])) return false;
      if (this.current) this.cancel('本次验收已停止');
      else if (this.session?.ready && this.session.runtimeSession === command.runtimeSession) {
        try { this.iframe.contentWindow.ugcReceive(JSON.stringify({ type: 'runtime_test', command })); } catch {}
        this.session.ready = false;
      }
      const body = { ...runtimeIdentity(command), phase: 'result', data: { ok: true, loaded: Boolean(this.view?.loaded), errors: [] } };
      this.completed.set(command.commandId, body); this.deliver(body); return true;
    }
    if (this.current) this.cancel('新的验收步骤已开始');
    this.current = command;
    this.view = { ...runtimeIdentity(command), step: clip(command.step || command.payload?.step || ({ run: '启动当前游戏', eval: '执行本步操作', test: '检查玩法规则' })[command.kind]),
      status: 'starting', loaded: false, checks: [], errors: [], connectionError: '' };
    this.onView(this.view, true);
    this.deadline = this.setTimer(() => { if (this.current?.commandId === command.commandId) this.cancel('本步验收超时，请重试', 'failed'); }, Math.max(1, command.expiresAt - this.clock()));
    if (command.kind === 'eval') {
      if (!this.session?.ready || ['runtimeSession', 'runId', 'buildId', 'sourceRevision'].some(key => this.session[key] !== command[key])) {
        this.cancel('实际运行会话已结束，需要重新启动游戏', 'failed'); return false;
      }
      this.execute(); return true;
    }
    this.session = { ...runtimeIdentity(command), previewSession: this.uuid(), ready: false };
    const params = new URLSearchParams({ pck: command.pckUrl, runtimeTest: '1', runtimeSession: command.runtimeSession,
      previewSession: this.session.previewSession, expectedBuildId: command.buildId });
    this.iframe.src = '/gp.html?' + params;
    this.iframe.tabIndex = -1;
    return true;
  }
  receive(event) {
    if (event.command) return this.accept(event.command);
    // Server copies of checks acknowledge the same execution; never echo them back.
    if (!this.view || !['progress', 'result'].includes(event.phase) || identityKeys.some(key => event[key] !== this.view[key]) || event.kind !== this.view.kind) return false;
    this.view = { ...this.view, checks: Array.isArray(event.checks) ? event.checks : this.view.checks,
      errors: Array.isArray(event.errors) ? event.errors : this.view.errors,
      ...(event.phase === 'result' ? { status: event.ok === true ? 'passed' : 'failed', connectionError: '' } : {}) };
    if (event.phase === 'result') this.outbox.delete(event.commandId);
    this.onView(this.view); return true;
  }
  invalidateSource(sourceRevision) {
    if (!sourceRevision || !this.view || this.view.sourceRevision === sourceRevision) return false;
    this.cancel('场景已修改，旧验收已归档'); this.view = null; this.onView(null); return true;
  }
  execute() {
    if (!this.current || !this.session?.ready) return;
    try {
      this.iframe.contentWindow.ugcReceive(JSON.stringify({ type: 'runtime_test', command: this.current }));
      this.view = { ...this.view, loaded: true, status: 'live', connectionError: '' }; this.onView(this.view);
    } catch { this.cancel('游戏验收连接未就绪', 'failed'); }
  }
  onMessage(event) {
    const command = this.current, payload = event.data?.__ugc && event.data.payload;
    if (!command || !this.active || !payload || event.source !== this.iframe.contentWindow || event.origin !== this.host.location.origin
      || payload.previewSession !== this.session?.previewSession) return;
    if (payload.type === 'ready') {
      if (this.session.ready) return;
      if (payload.loaded !== true || payload.errors?.length || payload.buildId !== command.buildId || payload.sourceRevision !== command.sourceRevision) {
        this.cancel(payload.errors?.join('；') || '载入的游戏版本与本次验收不一致', 'failed'); return;
      }
      this.session.ready = true; this.execute(); return;
    }
    if (payload.type === 'js_error' || payload.type === 'code_status' && payload.errors?.length) {
      this.cancel(payload.message || payload.errors?.join('；') || '实际游戏运行失败', 'failed'); return;
    }
    if (!['runtime_test_progress', 'runtime_test_result'].includes(payload.type) || !this.session.ready
      || identityKeys.some(key => payload[key] !== command[key]) || payload.kind !== command.kind) return;
    const data = payload.data && typeof payload.data === 'object' ? payload.data : {};
    this.view = { ...this.view, checks: Array.isArray(data.checks) ? data.checks : this.view.checks,
      errors: Array.isArray(data.errors) ? data.errors : [], loaded: true, connectionError: '' };
    if (payload.type === 'runtime_test_progress') {
      this.onView(this.view); this.deliver({ ...runtimeIdentity(command), phase: 'progress', data });
    } else this.finishCommand(command, data, data.ok === true && !data.errors?.length ? 'passed' : 'failed');
  }
  finishCommand(command, data, status) {
    if (status === 'passed' && Array.isArray(data.checks) && data.checks.some(check => check.ok === false)) status = 'failed';
    this.clearTimer(this.deadline); this.deadline = null;
    if (this.current?.commandId === command.commandId) this.current = null;
    const body = { ...runtimeIdentity(command), phase: 'result', data };
    this.completed.set(command.commandId, body);
    while (this.completed.size > 100) this.completed.delete(this.completed.keys().next().value);
    this.view = { ...(this.view || {}), ...runtimeIdentity(command), status, checks: data.checks || this.view?.checks || [], errors: data.errors || [], loaded: Boolean(this.session?.ready), connectionError: '' };
    this.onView(this.view); this.deliver(body);
  }
  async deliver(body) {
    const key = body.phase + ':' + body.commandId;
    if (this.delivering.has(key)) return;
    this.delivering.add(key);
    if (body.phase === 'result') {
      const item = this.outbox.get(body.commandId) || { body, at: this.clock(), attempts: 0 };
      item.attempts++; this.outbox.set(body.commandId, item);
    }
    try {
      // Large real screenshots cannot use fetch's 64 KiB keepalive body budget.
      const small = JSON.stringify(body).length < 15000;
      const result = await this.request('/runtime-result', body, { keepalive: body.phase === 'result' && small });
      if (result?.ok === false) throw new Error(result.error || '回执未被接收');
      if (body.phase === 'result') this.outbox.delete(body.commandId);
      if (this.view?.commandId === body.commandId && this.view.connectionError) { this.view = { ...this.view, connectionError: '' }; this.onView(this.view); }
    } catch {
      if (body.phase === 'result' && this.outbox.has(body.commandId) && this.view?.commandId === body.commandId) { this.view = { ...this.view, connectionError: '结果尚未送达，连接恢复后重试' }; this.onView(this.view); }
    } finally { this.delivering.delete(key); }
    // Polling retries bounded cached results; duplicate commands also retry without execution.
  }
  cancel(reason = '本次验收已停止', status = 'stopped') {
    const command = this.current;
    this.clearTimer(this.deadline); this.deadline = null;
    if (command) this.finishCommand(command, { ok: false, loaded: Boolean(this.session?.ready), checks: this.view?.checks || [], errors: [reason] }, status);
    this.current = null; this.session = null; this.iframe.src = 'about:blank';
    if (this.view) { this.view = { ...this.view, loaded: false }; this.onView(this.view); }
  }
  dispose() { this.active = false; this.generation++; this.clearTimer(this.timer); for (const request of this.requests) request.abort(); this.cancel('验收窗口已关闭'); this.host.removeEventListener('message', this.messageListener); }
}
