// The service owns the catalogue and persisted choice. This view never invents IDs.
export class ModelSelection {
  constructor({ request, projectId = '', onChange = () => {}, onSaved = () => {} }) {
    this.request = request; this.projectId = projectId; this.onChange = onChange; this.onSaved = onSaved;
    this.models = []; this.value = ''; this.pending = ''; this.loading = true; this.busy = false; this.error = ''; this.loaded = false;
  }
  sync(value, busy = false) {
    if (typeof value === 'string' && !this.pending) this.value = value;
    this.busy = Boolean(busy); this.onChange(this);
  }
  async load() {
    if (this.loadRequest) return this.loadRequest;
    this.loading = true; this.error = ''; this.onChange(this);
    this.loadRequest = (async () => {
      try {
        const result = await this.request('/models'), seen = new Set();
        this.models = (Array.isArray(result?.models) ? result.models : []).filter(row => {
          if (!row || typeof row.id !== 'string' || !row.id || typeof row.label !== 'string' || !row.label || seen.has(row.id)) return false;
          seen.add(row.id); return true;
        }).map(({ id, label }) => ({ id, label }));
        if (!this.models.length) throw new Error('暂无可选模型');
        if (!this.projectId && !this.value && seen.has(result.defaultModel)) this.value = result.defaultModel;
        this.loaded = true;
      } catch (error) { this.error = '模型列表加载失败：' + error.message; }
      finally { this.loading = false; this.loadRequest = null; this.onChange(this); }
    })();
    return this.loadRequest;
  }
  async choose(value) {
    if (this.busy || this.pending || this.loading || !this.models.some(row => row.id === value)) { this.onChange(this); return false; }
    if (value === this.value) return true;
    this.error = '';
    if (!this.projectId) { this.value = value; this.onChange(this); return true; }
    this.pending = value; this.onChange(this);
    try {
      const result = await this.request('/projects/' + encodeURIComponent(this.projectId) + '/model', { body: { model: value } });
      if (result?.ok !== true || typeof result.model !== 'string' || !result.model) throw new Error('未收到保存确认');
      this.value = result.model; this.onSaved(result.model);
      return true;
    } catch (error) {
      // A response can be lost after commit, or another tab can have started work.
      // Read back the actual selection instead of claiming a failed POST changed it.
      try {
        const current = await this.request('/projects/' + encodeURIComponent(this.projectId));
        if (typeof current?.model === 'string') { this.value = current.model; this.onSaved(current.model, current); }
        this.busy = this.busy || current?.running === true;
      } catch { /* Retain the last confirmed value when offline. */ }
      this.error = '切换未确认：' + error.message;
      return false;
    } finally { this.pending = ''; this.onChange(this); }
  }
}

export function modelSelectionView(state) {
  const value = state.pending || state.value, options = [...state.models];
  if (!options.some(row => row.id === value)) options.unshift({ id: value, label: value ? '当前选择（列表暂不可用）' : state.loading ? '正在加载…' : '请选择模型', disabled: true });
  return { value, options, disabled: state.busy || state.loading || Boolean(state.pending) || !state.loaded,
    note: state.pending ? '正在保存…' : state.error || (state.busy ? '制作中，本轮完成后可切换' : ''),
    error: Boolean(state.error), retry: !state.loading && !state.loaded };
}

export function paintModelSelection(state, select, note, retry, escape) {
  const view = modelSelectionView(state);
  const html = view.options.map(row => '<option value="' + escape(row.id) + '"' + (row.disabled ? ' disabled' : '') + '>' + escape(row.label) + '</option>').join('');
  if (select.innerHTML !== html) select.innerHTML = html;
  select.value = view.value; select.disabled = view.disabled;
  note.textContent = view.note; note.hidden = !view.note; note.dataset.state = view.error ? 'error' : 'normal';
  retry.hidden = !view.retry;
}
