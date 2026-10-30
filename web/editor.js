import { $, $$, api, esc, toast, ago, Runtime, uuid } from '/common.js';
import { normalizeWorkflow, reduceWorkflow, workflowSummary, TASK_LABELS, ROLE_LABELS, createEventCursor, assessPreview, STUDIO_STAGES, iterationView, formatElapsed, iterationRequest, CREATION_TIERS, canForwardTestInput, isWritingProgress, reduceWritingProgress, studioTaskCards, activityFromEvent, mergeActivity, studioNextSteps } from '/workflow-view.js';
import { restoreInworldWorkflow, reduceInworldEvent, inworldMessages } from '/inworld-workflow.js';
import { validConstruction, acceptConstruction, assessConstructionReceipt } from '/construction-view.js';
import { emptyPlaytest, reducePlaytest, playtestPresentation, watchIsActive, returnsToMaking } from '/playtest-view.js';
import { BrowserPlaytestController, runtimePresentation } from '/browser-playtest.js';
import { focusModule, moduleSuggestions, participationRows, mergeParticipation, participationLabel, participationSummary } from '/participation-view.js';
import { ModelSelection, paintModelSelection } from '/model-selection.js';
import { SketchBoardView } from '/sketch-board.js';

const qs = new URLSearchParams(location.search);
const pid = qs.get('id');
let proj = null, mode = 'edit', running = false, selection = null;
let curText = null, curAgent = '', restoringHistory = true, composing = false;
let inworldState = null;
let focusedModule = null, participationPending = false, participationError = '', participationAttempt = null;
let observeConstruction = false, constructionReceipt = null;
let sceneSelection = null, sceneEditPending = false, sceneBuildPending = false, sceneEditError = '', sceneUndo = null, sceneEnabled = null;
let browserTestView = null;
let primaryPresentation = null;
const constructionReceipts = new Map();
let playtestState = emptyPlaytest(), watchChoice = 'making', watchTimer = null, watchRequest = null, watchAbort = null, watchGeneration = 0, watchConnectionError = '';
let watchFrameEpoch = 0, watchImagePending = null, watchFrameShown = null, watchImageError = false;
let workflow = null, preview = { status: 'idle', message: '' }, previewExpected = null, previewTimer = null, loadedBuild = null;
const receiptKeys = new Set();
let liveActivity = [], studioTimer = null;
let sketch = null, sketchChoice = 'auto';
let writingProgress = null, visibleWritingProgress = null, writingTimer = null, writingRenderedAt = 0;
function publishWritingProgress() {
  writingTimer = null; visibleWritingProgress = writingProgress; writingRenderedAt = Date.now(); renderWorkflow();
  if (visibleWritingProgress) syncInworld({ ...visibleWritingProgress, type: 'tool_progress', name: 'write_file' });
}
function clearWritingProgress() {
  clearTimeout(writingTimer); writingTimer = null; writingProgress = visibleWritingProgress = null; writingRenderedAt = 0;
}
function updateWritingProgress(event) {
  const next = reduceWritingProgress(writingProgress, event, workflow?.id);
  if (next === writingProgress) return;
  writingProgress = next;
  if (!next) { clearWritingProgress(); renderWorkflow(); return; }
  const wait = Math.max(0, 1000 - (Date.now() - writingRenderedAt));
  if (!wait) { clearTimeout(writingTimer); publishWritingProgress(); }
  else if (!writingTimer) writingTimer = setTimeout(publishWritingProgress, wait);
}
function setWorkflowOpen(open, focus = true) {
  $('#workflowPanel').hidden = !open;
  $('#stage').classList.toggle('dock-closed', !open);
  $('#workflowBtn').setAttribute('aria-expanded', String(open));
  if (open) { if (!feed.hidden) setChat(false, false); if (focus) $('#workflowClose').focus({ preventScroll: true }); }
  else if (focus) $('#workflowBtn').focus({ preventScroll: true });
  layout();
}
function renderClock() {
  const timing = iterationView(workflow);
  $('#iterationKind').textContent = workflow ? timing.hasIteration ? timing.kind : '制作记录' : '先做小而精的 Demo';
  $('#iterationElapsed').textContent = formatElapsed(timing.elapsedMs);
  $('#iterationTarget').textContent = timing.targetMs ? '目标 ' + Math.round(timing.targetMs / 60000) + ' 分钟' : workflow ? '未设置目标时间' : '目标 ' + CREATION_TIERS[iterationRequest($('#iterationTier').value).tier].minutes + ' 分钟';
  $('#iterationClockNote').textContent = workflow ? timing.clockLabel : '开始后展示真实计时和制作事件';
  $('.studio-clock').dataset.state = timing.clockState;
  $('#sceneTiming').textContent = timing.elapsedMs == null ? '' : formatElapsed(timing.elapsedMs) + (timing.targetMs ? ' / 目标 ' + Math.round(timing.targetMs / 60000) + ' 分' : '');
  renderPlaytest();
}
function renderWorkflow() {
  const summary = workflowSummary(workflow, { sceneDirty: proj?.sceneDirty, sourceRevision: expectedSceneSource() });
  if (running && workflow?.status !== 'running') { summary.text = '正在准备本次制作'; summary.tone = 'active'; }
  const previewProblem = ['failed', 'unverified', 'receipt_failed'].includes(preview.status);
  $('#workflowStatus').textContent = previewProblem ? (preview.status === 'failed' ? '预览遇到问题' : preview.status === 'receipt_failed' ? '预览回执未保存' : '当前预览尚未验证') : preview.status === 'loading' && workflow?.status === 'ready' ? '正在打开本次制作结果' : summary.text;
  $('#workflowBtn').dataset.tone = previewProblem ? 'error' : summary.tone;
  $('#workflowPanel').dataset.tone = previewProblem ? 'error' : summary.tone;
  renderClock();
  const timing = iterationView(workflow), rows = mergeActivity(workflow, liveActivity);
  const detailsOpen = $('#studioDetails')?.open && $('#studioDetails').dataset.run === workflow?.id;
  const cards = studioTaskCards(workflow, liveActivity, visibleWritingProgress);
  const shot = rows.findLast(row => row.image);
  const evidenceNames = { compile: '代码检查', test: '实际试玩检查', build: '预览包生成', preview: '浏览器预览确认' };
  const goal = String(workflow?.goal || '描述你想制作或修改的内容，进度会在这里更新。'), goalChars = Array.from(goal);
  const goalOpen = $('#workflowGoal')?.open && $('#workflowGoal').dataset.run === workflow?.id;
  let details = goalChars.length > 160
    ? '<details class="workflow-goal-details" id="workflowGoal" data-run="' + esc(workflow?.id) + '"' + (goalOpen ? ' open' : '') + '><summary><span class="workflow-goal-preview">' + esc(goalChars.slice(0, 120).join('')) + '…</span><span class="goal-expand">展开全文</span><span class="goal-collapse">收起全文</span></summary><p class="workflow-goal">' + esc(goal) + '</p></details>'
    : '<p class="workflow-goal">' + esc(goal) + '</p>';
  if (workflow?.tasks.length) details += '<h3>全部任务</h3><ol class="workflow-list">' + workflow.tasks.map(task => '<li><div class="workflow-row"><strong>' + esc(task.title || task.id) + '</strong><span>' + esc(TASK_LABELS[task.status] || task.status || '状态待确认') + '</span></div>' + (task.role ? '<small>' + esc(ROLE_LABELS[task.role] || task.role) + '</small>' : '') + (task.summary ? '<small>交付时说明：' + esc(task.summary) + '</small>' : '') + (task.status === 'verified' ? '<small class="workflow-ok">当前版本已通过整体验收</small>' : '') + (task.error ? '<small class="workflow-error">' + esc(typeof task.error === 'string' ? task.error : task.error.message || JSON.stringify(task.error)) + '</small>' : '') + '</li>').join('') + '</ol>';
  if (workflow?.evidence.length) details += '<h3>验收记录</h3><ul class="workflow-list">' + workflow.evidence.slice(-12).map(item => '<li><div class="workflow-row"><strong>' + esc(evidenceNames[item.kind] || '制作检查') + '</strong><span class="' + (item.ok ? 'workflow-ok' : 'workflow-error') + '">' + (item.ok ? '通过' : '未通过') + '</span></div>' + (item.summary ? '<small>' + esc(item.summary) + '</small>' : '') + (item.errors?.length ? '<small class="workflow-error">' + esc(item.errors.map(error => typeof error === 'string' ? error : error.message || '检查失败').join('；')) + '</small>' : '') + '</li>').join('') + '</ul>';
  if (preview.message) details += '<h3>当前场景</h3><p class="' + (previewProblem ? 'workflow-error' : 'workflow-subtle') + '">' + esc(preview.message) + '</p>';
  if (workflow?.issues.length) details += '<h3>待处理</h3><ul class="workflow-list">' + workflow.issues.map(issue => '<li class="workflow-error">' + esc(typeof issue === 'string' ? issue : issue.message || JSON.stringify(issue)) + '</li>').join('') + '</ul>';
  const changedFiles = [...new Set([...cards.flatMap(card => card.files), ...rows.map(row => row.file).filter(Boolean)])];
  if (changedFiles.length) details += '<h3>涉及文件</h3><ul class="workflow-list">' + changedFiles.slice(-12).map(file => '<li>' + esc(file) + '</li>').join('') + '</ul>';
  const html = '<ol class="studio-stages" aria-label="制作阶段">' + STUDIO_STAGES.map((stage, i) => '<li data-state="' + (!workflow || timing.paused ? 'pending' : i < timing.phaseIndex ? 'done' : i === timing.phaseIndex ? 'current' : 'pending') + '"' + (workflow && i === timing.phaseIndex ? ' aria-current="step"' : '') + '>' + stage.label + '</li>').join('') + '</ol>'
    + '<p class="studio-goal" title="本轮需求，全文在下方范围记录中">' + esc(goalChars.slice(0, 32).join('')) + (goalChars.length > 32 ? '…' : '') + '</p><p role="status" class="studio-status' + (previewProblem || summary.tone === 'error' ? ' workflow-error' : '') + '">' + esc($('#workflowStatus').textContent) + '</p>'
    + (timing.reason ? '<p class="workflow-subtle">' + esc(timing.reason) + '</p>' : '')
    + '<div class="studio-section-title">最近发生<small>来自真实制作事件</small></div>'
    + (rows.length ? '<ol class="studio-events">' + rows.slice(-3).reverse().map(row => '<li data-status="' + esc(row.status || '') + '">' + (row.at && !Number.isNaN(new Date(row.at).getTime()) ? '<time>' + esc(new Date(row.at).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })) + '</time>' : '') + '<strong>' + esc(row.title) + '</strong>' + (row.detail ? '<small>' + esc(String(row.detail).slice(0, 70)) + '</small>' : '') + '</li>').join('') + '</ol>' : '<p class="studio-empty">正在等待第一条制作事件。</p>')
    + (cards.length ? '<div class="studio-crew' + (cards.length === 1 ? ' single-worker' : '') + '">' + cards.map((task, i) => '<article class="worker-card" data-status="' + esc(task.status) + '"><div class="worker-role"><span class="worker-icon" aria-hidden="true">' + (task.id === 'main-work' ? 'M' : i + 1) + '</span>' + esc(task.roleLabel) + '</div><strong>' + esc(task.title) + '</strong><span class="worker-status">' + esc(task.statusLabel) + '</span>' + (task.writingLabel ? '<small class="worker-writing">' + esc(task.writingLabel) + '</small>' : '') + '</article>').join('') + '</div>' : '')
    + (shot ? '<figure class="studio-shot"><a href="' + esc(shot.image) + '" target="_blank" rel="noopener" aria-label="打开实际试玩截图"><img src="' + esc(shot.image) + '" alt="实际试玩检查截图" loading="lazy"></a><figcaption>最近一次实际试玩截图 · ' + esc(shot.title) + '</figcaption></figure>' : '')
    + '<details class="studio-details" id="studioDetails" data-run="' + esc(workflow?.id) + '"' + (detailsOpen ? ' open' : '') + '><summary>范围、全部任务与验收记录</summary>' + details + '</details>';
  const content = $('#workflowContent');
  if (content.innerHTML !== html) {
    const scrollTop = content.scrollTop, focused = document.activeElement;
    const summaryId = content.contains?.(focused) && focused?.tagName === 'SUMMARY' ? focused.parentElement?.id : '';
    content.innerHTML = html; content.scrollTop = scrollTop;
    if (['studioDetails', 'workflowGoal'].includes(summaryId)) $('#' + summaryId + ' > summary')?.focus({ preventScroll: true });
  }
  $('#workflowRepair').hidden = running || !(summary.canRepair || preview.status === 'failed');
  $('#previewRetry').hidden = (!pckUrl && !previewExpected?.workshop) || !previewProblem;
  const canPlay = Boolean(pckUrl || proj?.sceneDirty && validConstruction(proj?.game?.construction) || (!isGodot() && Object.keys(proj?.game?.entities || {}).length));
  $('#studioPlay').hidden = !canPlay;
  $('#studioPlay').textContent = pckUrl && shownPckUrl && shownPckUrl !== pckUrl ? '打开新试玩包' : running ? '试玩已有版本' : '先试玩';
  $('#scenePlay').hidden = !canPlay;
  $('#scenePlay').textContent = $('#studioPlay').textContent;
  renderConstructionStatus();
  $('#studioBuildNote').textContent = canPlay ? (proj?.build?.version != null ? '可试玩版本 v' + proj.build.version + ' · ' : '') + (shownPckUrl && pckUrl !== shownPckUrl ? '当前游戏保持原样，点击后更新' : preview.status === 'verified' ? '已收到当前版本首帧回执' : '试玩不等于全部玩法已验收') : '可运行版本生成后，这里会出现试玩入口';
  $('#studioNext').hidden = running || !timing.canChoose;
  const choices = studioNextSteps(workflow).map((row, index) => '<button class="improvement-choice" data-improve="' + index + '">' + esc(row.title) + '</button>').join('');
  if ($('#improvementOptions').innerHTML !== choices) $('#improvementOptions').innerHTML = choices;
  renderParticipation();
  modelSelection.sync(proj?.model, running);
  syncSketch();
}
// The sketch covers the game area while the builder works, unless a live picture (3D construction or the playtest) is on screen; then it waits in the corner.
const sketchLiveBuild = () => $('#frameWrap').classList.contains('watching') || (observeConstruction && validConstruction(proj?.game?.construction));
const sketchRealGame = () => Boolean(shownPckUrl) || sketchLiveBuild();
function syncSketch() {
  if (!sketch) return;
  sketch.setMaker(running ? $('#workflowStatus').textContent : '');
  const real = sketchRealGame(), has = mode === 'edit' && sketch.hasContent();
  const auto = !real || (running && !sketchLiveBuild()) ? 'full' : sketch.live ? 'pip' : 'hidden';
  const view = !has ? 'hidden' : sketchChoice !== 'auto' ? sketchChoice : auto;
  sketch.setView(view, { canCollapse: real });
  const button = $('#sketchBtn');
  button.hidden = !has;
  button.setAttribute('aria-pressed', String(view !== 'hidden'));
  button.title = view === 'hidden' ? '显示 AI 铅笔草图' : '收起 AI 铅笔草图';
}
$('#sketchBtn').onclick = () => {
  sketchChoice = sketch?.view === 'hidden' ? (sketchRealGame() ? 'pip' : 'full') : 'hidden';
  syncSketch();
};
function renderParticipation() {
  const rows = participationRows(proj?.participation), context = { running, delivery: proj?.participationDelivery || (proj?.game?.meta?.engine === 'code' ? 'next_round' : 'live') };
  if (focusedModule) focusedModule = focusModule(focusedModule, inworldState?.modules || []);
  const focus = $('#moduleFocus'); focus.hidden = !focusedModule;
  $('#moduleFocusName').textContent = focusedModule ? '正在讨论：' + focusedModule.label : '';
  const suggestions = moduleSuggestions(focusedModule).map((value, index) => '<button type="button" data-module-suggestion="' + index + '">' + esc(value) + '</button>').join('');
  if ($('#moduleSuggestions').innerHTML !== suggestions) $('#moduleSuggestions').innerHTML = suggestions;
  input.placeholder = focusedModule ? '对「' + focusedModule.label + '」有什么建议？' : running ? context.delivery === 'next_round' ? '制作中也能提建议，下一轮开始时送达…' : '制作中也能提建议，下个工作节点接收…' : '说说你想怎么改…';
  const retry = participationAttempt?.key === JSON.stringify([input.value.trim(), focusedModule?.file || '']);
  const button = $('#sendBtn'), label = participationPending ? '提交中' : running ? '提交建议' : retry ? '重试建议' : '发送';
  button.hidden = false; button.disabled = participationPending || Boolean(modelSelection.pending && !running); button.classList.toggle('send-advice', running || participationPending || retry);
  button.setAttribute('aria-label', label); button.title = label; $('#sendLabel').textContent = running || participationPending || retry ? label : '';
  $('#participationStatus').hidden = !participationError && !participationPending && !rows.length;
  $('#participationNote').textContent = participationError || (participationPending ? '正在提交建议，当前制作继续进行' : participationSummary(rows, context));
  $('#participationNote').dataset.state = participationError ? 'error' : 'normal';
  $('#participationDetails').hidden = !rows.length;
  const receipts = rows.slice(-8).reverse().map(row => '<li><span>' + esc(participationLabel(row, context)) + '</span><p>' + esc(row.text) + '</p></li>').join('');
  if ($('#participationList').innerHTML !== receipts) $('#participationList').innerHTML = receipts;
}
function renderConstructionStatus() {
  const snapshot = proj?.game?.construction, note = $('#constructionStatus'), stage = hasBuildStage(), live = liveBuild(), modules = stage || live;
  note.hidden = !observeConstruction && !modules || mode !== 'edit';
  note.textContent = sceneBuildPending ? '正在为已保存的场景生成试玩版本' : sceneEditPending ? '正在保存物体位置' : sceneEditError ? sceneEditError : proj?.sceneDirty ? '场景已保存 · 试玩时将生成新版本' : !validConstruction(snapshot) ? '观察搭建 · 等待真实场景内容'
    : constructionReceipt?.loaded ? '场景已落地 · ' + constructionReceipt.objectCount + ' 个对象'
    : constructionReceipt ? '场景应用遇到问题 · ' + constructionReceipt.errors.join('；') : '正在应用场景变更';
  if (modules) note.textContent = stage ? '小精灵正在准备第一版画面 · 试玩由你开始' : '小精灵正在现场拼装 · 新内容会直接出现在画面上';
  note.dataset.state = constructionReceipt && !constructionReceipt.loaded ? 'error' : 'normal';
  for (const button of $$('#modeSeg button')) if (button.dataset.m === 'edit') button.textContent = modules ? '观察制作' : observeConstruction ? '观察搭建' : '编辑';
  renderSceneEditor();
}
function canEditScene() { return mode === 'edit' && validConstruction(proj?.game?.construction) && !running && !sceneEditPending && !sceneBuildPending && !browserTests?.current; }
function renderSceneEditor() {
  const enabled = canEditScene(), visible = mode === 'edit' && validConstruction(proj?.game?.construction) && Boolean(sceneSelection) && !(watchChoice === 'testing' && (browserTestView || playtestState.watch));
  $('#sceneEditBar').hidden = !visible;
  if (sceneEnabled !== enabled && typeof rt !== 'undefined') { sceneEnabled = enabled; if (previewExpected?.workshop && rt.ready) rt.send({ type: 'editor_control', enabled }); }
  if (!visible) return;
  $('#sceneEditName').textContent = sceneSelection.label || sceneSelection.id;
  $('#sceneEditPosition').textContent = (sceneSelection.position || []).map((n, i) => 'XYZ'[i] + ' ' + Number(n).toFixed(2)).join(' · ');
  $('#sceneEditNote').textContent = sceneEditError || (sceneEditPending || sceneSelection.pending ? '正在保存' : sceneBuildPending ? '正在生成试玩版本' : running ? '制作中 · 可观察，暂不能移动' : '可拖动物体或按方向微调');
  for (const button of $$('#sceneNudge button')) button.disabled = !enabled || sceneSelection.pending;
  $('#sceneUndo').disabled = !enabled || !sceneUndo;
}
function restoreCanonicalScene() {
  if (validConstruction(proj?.game?.construction) && mode === 'edit' && previewExpected?.workshop && rt.ready)
    rt.send({ type: 'construction', snapshot: proj.game.construction, restore: true });
}
async function sceneRequest(path, body, timeout = 8000) {
  const controller = new AbortController(), timer = setTimeout(() => controller.abort(), timeout);
  try {
    const response = await fetch('/api/projects/' + encodeURIComponent(pid) + path, { method: body ? 'POST' : 'GET', headers: body ? { 'content-type': 'application/json' } : {}, body: body ? JSON.stringify(body) : undefined, signal: controller.signal, cache: 'no-store' });
    return { response, result: await response.json() };
  } finally { clearTimeout(timer); }
}
async function saveSceneMove(event, undoing = false) {
  const snapshot = proj?.game?.construction, object = snapshot?.objects.find(row => row.id === event.id);
  if (!canEditScene() || !object || event.baseRevision !== snapshot.revision || !Array.isArray(event.position) || event.position.length !== 3 || !event.position.every(Number.isFinite)) { restoreCanonicalScene(); return; }
  const previousPosition = [...object.position], requestId = event.requestId || uuid();
  sceneEditPending = true; sceneEditError = ''; renderConstructionStatus();
  try {
    const { response, result } = await sceneRequest('/scene-edit', { id: event.id, position: event.position, baseRevision: snapshot.revision, requestId });
    if (validConstruction(result.snapshot) && result.snapshot.revision >= proj.game.construction.revision) proj.game.construction = result.snapshot;
    if (!response.ok || !result.ok) throw new Error(result.error || '位置未保存，已恢复实际场景');
    proj.sceneDirty = true; proj.sceneSourceRevision = result.sceneSourceRevision || result.sourceRevision; invalidateSceneTests();
    sceneUndo = undoing ? null : { id: event.id, position: previousPosition };
    const current = proj.game.construction.objects.find(row => row.id === event.id);
    if (current) sceneSelection = { id: current.id, label: current.label, position: [...current.position], revision: proj.game.construction.revision, pending: false };
  } catch (error) {
    sceneEditError = '保存失败：' + error.message;
    // Fetch authoritative state after network uncertainty or an edit conflict.
    try { const { result: fresh } = await sceneRequest(''); if (validConstruction(fresh.game?.construction) && fresh.game.construction.revision >= proj.game.construction.revision) { proj.game.construction = fresh.game.construction; proj.sceneDirty = fresh.sceneDirty; proj.sceneSourceRevision = fresh.sceneSourceRevision; } } catch {}
  } finally {
    sceneEditPending = false;
    const actual = proj.game.construction.objects.find(row => row.id === event.id);
    if (sceneSelection) { sceneSelection.pending = false; if (actual) { sceneSelection.position = [...actual.position]; sceneSelection.revision = proj.game.construction.revision; } }
    invalidateSceneTests(); restoreCanonicalScene(); renderWorkflow();
  }
}
async function buildSceneForPlay() {
  if (sceneBuildPending || sceneEditPending || running) { toast('请等待当前场景保存或制作完成后试玩'); return false; }
  const revision = proj.game.construction?.revision;
  sceneBuildPending = true; sceneEditError = ''; renderConstructionStatus();
  try {
    const { response, result } = await sceneRequest('/scene-build', {}, 120000);
    if (!response.ok || !result.ok || !result.pck || !result.build?.buildId) throw new Error(result.error || '没有生成可试玩版本');
    if (proj.game.construction?.revision !== revision || running) throw new Error('场景又有新变化，请重新生成试玩版本');
    proj.build = result.build; pckUrl = proj.pck = result.pck; proj.sceneDirty = false;
    proj.sceneSourceRevision = result.sceneSourceRevision || result.sourceRevision; invalidateSceneTests(); return true;
  } catch (error) { sceneEditError = '试玩版本生成失败：' + error.message; toast(sceneEditError); return false; }
  finally { sceneBuildPending = false; renderConstructionStatus(); }
}
function presentConstruction(restore = false) {
  if (mode !== 'edit' || !validConstruction(proj?.game?.construction)) return;
  observeConstruction = true;
  if (gpSrc() !== rtSrc) gpShow();
  else if (rt.ready) rt.send({ type: 'construction', snapshot: proj.game.construction, restore });
  renderWorkflow(); layout();
}
function updateWorkflow(next) {
  if (workflow?.id !== next?.id) {
    resetPlaytest(next?.id || '');
    liveActivity = []; clearWritingProgress(); $('#improvementOptions').hidden = true;
    if (next?.iteration) $('#iterationTier').value = iterationRequest(next.iteration.tier).tier;
  }
  workflow = normalizeWorkflow(next); if (proj) proj.workflow = workflow; renderWorkflow(); restoreInworld(); browserTests.sync();
}
$('#workflowBtn').onclick = () => setWorkflowOpen($('#workflowPanel').hidden);
$('#workflowClose').onclick = () => setWorkflowOpen(false);
$('#workflowRepair').onclick = () => {
  if (running) return;
  const issues = [...(workflow?.issues || []), ...(preview.errors || [])].map(row => typeof row === 'string' ? row : JSON.stringify(row));
  input.value = '请继续完成这次制作，修复未通过的任务和验收问题，并重新验证实际游戏。' + (issues.length ? '\n待处理：' + issues.slice(0, 8).join('；') : '');
  resizeInput(); send();
};
$('#previewRetry').onclick = () => gpShow({ force: true });
$('#studioPlay').onclick = () => { if (proj) setMode('play'); };
$('#scenePlay').onclick = () => { if (proj) setMode('play'); };
$('#watchMaking').onclick = () => { watchChoice = 'making'; renderPlaytest(); };
$('#watchTesting').onclick = () => { if (browserTestView || playtestState.watch) { watchChoice = 'testing'; renderPlaytest(); if (!browserTestView) pollWatch(); } };
$('#sceneNudge').onclick = event => { const button = event.target.closest('[data-axis]'); if (!button || !canEditScene() || !sceneSelection) return; const delta = [0, 0, 0]; delta[Number(button.dataset.axis)] = Number(button.dataset.sign) * Number($('#sceneEditStep').value || 1); rt.send({ type: 'editor_control', action: 'nudge', id: sceneSelection.id, delta }); };
$('#sceneUndo').onclick = () => { if (sceneUndo && canEditScene()) saveSceneMove({ ...sceneUndo, baseRevision: proj.game.construction.revision }, true); };
$('#sceneFrame').onclick = () => rt.send({ type: 'editor_control', action: 'frame' });
$('#improveBtn').onclick = () => { $('#improvementOptions').hidden = !$('#improvementOptions').hidden; };
$('#improvementOptions').onclick = event => {
  const button = event.target.closest('[data-improve]'); if (!button || running) return;
  if (input.value.trim()) { toast('输入框里已有想法，可以直接发送或先修改'); input.focus(); return; }
  const next = studioNextSteps(workflow)[Number(button.dataset.improve)]; if (!next) return;
  input.value = next.prompt; resizeInput(); input.focus({ preventScroll: true });
  toast('已写入这一个改进，发送后开始下一轮');
};
$('#iterationTier').onchange = renderClock;

function clearWatchFrame() {
  clearTimeout(watchImagePending?.timer); watchFrameEpoch++; watchImagePending = null; watchFrameShown = null; watchImageError = false;
  const img = $('#watchFrame'); img.hidden = true; img.removeAttribute('src');
}
function resetPlaytest(runId) {
  cancelWatchRequest(); clearTimeout(watchTimer); watchTimer = null;
  playtestState = emptyPlaytest(runId); watchChoice = 'making'; watchConnectionError = ''; clearWatchFrame(); renderPlaytest(); scheduleWatchPoll();
}
function expectedSceneSource() { return proj?.sceneDirty ? proj.sceneSourceRevision : proj?.build?.sourceRevision; }
function invalidateSceneTests() {
  const revision = expectedSceneSource();
  if (!revision) return;
  const outdatedWatch = playtestState.watch && playtestState.watch.sourceRevision !== revision;
  const outdatedRuntime = browserTests.invalidateSource(revision);
  if (outdatedWatch) resetPlaytest(workflow?.id || '');
  if (outdatedWatch || outdatedRuntime) { watchChoice = 'making'; renderPlaytest(); }
}
function receivePlaytest(value, restoring = false) {
  if (browserTestView) return;
  if (value && expectedSceneSource() && value.sourceRevision !== expectedSceneSource()) return;
  if (value === null) { if (playtestState.watch) resetPlaytest(workflow?.id || ''); return; }
  const previous = playtestState, next = reducePlaytest(previous, value, workflow?.id || '');
  if (next === previous) return;
  const changedSession = next.watch?.sessionId !== previous.watch?.sessionId;
  playtestState = next; watchConnectionError = '';
  if (changedSession) {
    clearWatchFrame();
    if (mode === 'edit' && (watchIsActive(next.watch) || restoring && ['verify', 'review'].includes(workflow?.iteration?.phase))) watchChoice = 'testing';
  }
  renderPlaytest(); scheduleWatchPoll();
}
function loadWatchFrame(watch) {
  if (!watch?.frameUrl || !watch.frameSeq || mode !== 'edit' || watchChoice !== 'testing' || document.visibilityState === 'hidden') return;
  const key = watch.sessionId + ':' + watch.frameSeq;
  if (watchFrameShown?.key === key || watchImagePending) return;
  const img = document.createElement('img'), epoch = watchFrameEpoch;
  const pending = { key, img }; watchImagePending = pending;
  img.decoding = 'async'; img.alt = '本次验收的真实画面';
  img.onload = () => {
    if (watchImagePending !== pending || epoch !== watchFrameEpoch || playtestState.watch?.sessionId !== watch.sessionId) return;
    clearTimeout(pending.timer);
    watchImagePending = null; watchImageError = false; img.onload = img.onerror = null;
    img.id = 'watchFrame'; img.hidden = false; $('#watchFrame').replaceWith(img);
    watchFrameShown = { key, capturedAt: watch.capturedAt }; renderPlaytest();
  };
  img.onerror = () => {
    if (watchImagePending !== pending || epoch !== watchFrameEpoch || playtestState.watch?.sessionId !== watch.sessionId) return;
    clearTimeout(pending.timer);
    watchImagePending = null; watchImageError = true; img.onload = img.onerror = null;
    renderPlaytest(false); // A retired frame may be 410; the next poll brings a new URL.
  };
  pending.timer = setTimeout(() => {
    if (watchImagePending !== pending || epoch !== watchFrameEpoch) return;
    watchImagePending = null; watchImageError = true; img.onload = img.onerror = null; img.removeAttribute('src'); renderPlaytest(false);
  }, 2000);
  img.src = watch.frameUrl;
}
function renderPlaytest(loadFrame = true) {
  const watch = browserTestView || playtestState.watch, visible = mode === 'edit' && watchChoice === 'testing' && Boolean(watch);
  $('#watchSwitch').hidden = mode !== 'edit' || !watch;
  $('#watchMaking').setAttribute('aria-pressed', String(!visible));
  $('#watchTesting').setAttribute('aria-pressed', String(visible));
  $('#playtestSurface').hidden = !visible;
  $('#frameWrap').classList.toggle('watching', visible);
  syncSketch();
  $('#rt').tabIndex = visible ? -1 : 0;
  $('#rt').setAttribute('aria-hidden', String(visible));
  syncPrimaryPresentation(); renderSceneEditor();
  $('#testRt').hidden = !browserTestView;
  if (browserTestView) {
    const view = runtimePresentation(browserTestView);
    $('#watchFrame').hidden = true; $('#playtestSurface').dataset.tone = browserTestView.status; $('#playtestSurface').dataset.stale = 'false';
    $('#watchKind').textContent = view.label; $('#watchStep').textContent = browserTestView.step || '实际验收'; $('#watchStatus').textContent = view.status;
    $('#watchNote').textContent = view.note; $('#watchChecks').textContent = view.checks; $('#watchErrors').textContent = view.errors;
    $('#watchWaiting').hidden = browserTestView.loaded; $('#watchWaiting').textContent = browserTestView.loaded ? '' : view.errors || view.note;
    return;
  }
  if (!watch) return;
  const view = playtestPresentation(watch, Date.now(), watchFrameShown?.capturedAt || watch.capturedAt);
  $('#playtestSurface').dataset.tone = watch.status;
  $('#playtestSurface').dataset.stale = String(view.stale);
  $('#watchKind').textContent = view.label;
  $('#watchStep').textContent = watch.step || '等待实际步骤';
  $('#watchStatus').textContent = view.status;
  $('#watchNote').textContent = watchConnectionError || (watchImageError ? '当前帧暂未取到，等待下一帧' : view.note);
  $('#watchChecks').textContent = watch.checks.slice(-3).map(row => (row.ok ? '✓ ' : '× ') + row.what).join(' · ');
  $('#watchErrors').textContent = watch.errors.slice(-2).join('；');
  $('#watchWaiting').hidden = Boolean(watchFrameShown);
  $('#watchWaiting').textContent = view.hasFrame ? '正在载入实际画面' : view.note;
  if (visible && loadFrame) loadWatchFrame(watch);
}
function syncPrimaryPresentation(force = false) {
  if (!isGodot() || !rt.ready) return;
  const active = document.visibilityState !== 'hidden' && !(mode === 'edit' && watchChoice === 'testing' && (browserTestView || playtestState.watch));
  if (!force && active === primaryPresentation) return;
  if (active && primaryPresentation === false && previewExpected?.workshop) restoreCanonicalScene();
  primaryPresentation = active;
  rt.send({ type: 'presentation', active });
}
function scheduleWatchPoll() {
  clearTimeout(watchTimer); watchTimer = null;
  if (!proj || browserTestView || mode !== 'edit' || document.visibilityState === 'hidden') return;
  const active = watchIsActive(playtestState.watch);
  if (!active && !running) return;
  watchTimer = setTimeout(pollWatch, active && watchChoice === 'testing' && !watchConnectionError ? 250 : 1500);
}
function cancelWatchRequest() {
  watchGeneration++; watchAbort?.abort(); watchAbort = null; watchRequest = null;
}
async function pollWatch() {
  if (!proj || browserTestView || mode !== 'edit' || document.visibilityState === 'hidden' || watchRequest) return;
  const generation = watchGeneration, controller = new AbortController();
  watchAbort = controller;
  const deadline = setTimeout(() => controller.abort(), 4000);
  const request = (async () => {
    const response = await fetch('/api/projects/' + encodeURIComponent(pid) + '/watch', { signal: controller.signal, cache: 'no-store' });
    if (!response.ok) throw new Error('验收画面请求失败');
    return await response.json();
  })();
  watchRequest = request;
  try {
    const value = await request;
    if (generation !== watchGeneration || mode !== 'edit') return;
    receivePlaytest(value, true);
  } catch (error) {
    if (generation === watchGeneration && mode === 'edit') { watchConnectionError = '验收画面连接暂时中断，正在重连'; renderPlaytest(false); }
  } finally {
    clearTimeout(deadline);
    if (watchAbort === controller) watchAbort = null;
    if (watchRequest === request) watchRequest = null;
    if (generation === watchGeneration) scheduleWatchPoll();
  }
}

// The game keeps running while the optional conversation is closed.
const feed = $('#feed'), msgs = $('#msgs'), input = $('#input'), chatBtn = $('#chatBtn');
const modelSelection = new ModelSelection({ request: api, projectId: pid,
  onChange: state => { paintModelSelection(state, $('#modelSelect'), $('#modelNote'), $('#modelRetry'), esc); renderParticipation(); },
  onSaved: (model, current) => { if (proj) proj.model = model; if (current?.running) setRunning(true); }
});
$('#modelSelect').onchange = () => modelSelection.choose($('#modelSelect').value);
$('#modelRetry').onclick = () => modelSelection.load();
function syncEmpty() { $('#chatEmpty').hidden = msgs.childElementCount > 0; }
function scroll() { if (!feed.hidden) requestAnimationFrame(() => { msgs.scrollTop = msgs.scrollHeight; }); }
function notifyReply() {
  if (restoringHistory) return;
  if (feed.hidden) chatBtn.dataset.unread = 'true'; else scroll();
}
function setChat(open, restoreFocus = true) {
  if (open && mode === 'play') setMode('edit');
  feed.hidden = !open;
  document.body.classList.toggle('chat-view', open);
  $$('#viewSeg button').forEach(button => {
    const active = button.dataset.view === (open ? 'chat' : 'preview');
    button.classList.toggle('on', active); button.setAttribute('aria-pressed', String(active));
  });
  chatBtn.setAttribute('aria-expanded', String(open));
  chatBtn.setAttribute('aria-label', open ? '关闭对话记录' : '打开对话记录');
  if (open) {
    setWorkflowOpen(false, false);
    delete chatBtn.dataset.unread; scroll();
    if (restoreFocus) $('#viewSeg [data-view="chat"]').focus({ preventScroll: true });
  } else if (restoreFocus) $('#viewSeg [data-view="preview"]').focus({ preventScroll: true });
  layout();
}
$$('#viewSeg button').forEach(button => button.onclick = () => setChat(button.dataset.view === 'chat', false));
chatBtn.onclick = () => setChat(feed.hidden);
$('#chatClose').onclick = () => setChat(false);
function md(el) { el.innerHTML = esc(el.textContent).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').replace(/`([^`]+)`/g, '<code>$1</code>'); }
function addUser(text) {
  const el = document.createElement('div'); el.className = 'msg user';
  el.innerHTML = '<div>' + esc(text) + '</div>'; msgs.appendChild(el); syncEmpty(); scroll();
}
function addAi(text, streaming = false) {
  const el = document.createElement('div'); el.className = 'msg ai';
  el.innerHTML = '<div class="av" aria-hidden="true">✦</div><div class="tx' + (streaming ? ' cursor' : '') + '"></div>';
  const tx = $('.tx', el); tx.textContent = text || ''; if (!streaming) md(tx);
  msgs.appendChild(el); syncEmpty(); if (text) notifyReply(); scroll(); return tx;
}
function endStream() {
  if (!curText) return;
  md(curText); curText.classList.remove('cursor');
  if (!curText.textContent.trim()) curText.parentElement.remove();
  curText = null; syncEmpty();
}
function addSugg(list) {
  const suggestions = (list || []).filter(s => typeof s === 'string' && s.trim()).slice(0, 4);
  if (!suggestions.length) return;
  const el = document.createElement('div'); el.className = 'sugg';
  for (const text of suggestions) {
    const button = document.createElement('button'); button.textContent = text;
    button.onclick = () => { input.value = text; resizeInput(); if (!running) send(); else input.focus(); };
    el.appendChild(button);
  }
  msgs.appendChild(el); syncEmpty(); notifyReply(); scroll();
}
function addError(text) {
  const el = document.createElement('div'); el.className = 'err'; el.setAttribute('role', 'alert');
  el.textContent = '⚠ ' + text; msgs.appendChild(el); syncEmpty(); notifyReply(); scroll();
}
function restoreChat(messages) {
  const wasRestoring = restoringHistory;
  restoringHistory = true; curText = null; curAgent = ''; msgs.replaceChildren();
  snapshotTextThrough.clear(); snapshotSummaries.clear(); snapshotReceivedAt = Date.now();
  for (const message of messages || []) {
    if (message.role === 'user') addUser(message.text);
    else {
      const agent = message.agent || '';
      if (typeof message.t === 'number') snapshotTextThrough.set(agent, Math.max(snapshotTextThrough.get(agent) || 0, message.t));
      if (!agent) snapshotSummaries.add(message.text);
      addAi(message.text); if (message.suggestions) addSugg(message.suggestions);
    }
  }
  restoringHistory = wasRestoring; syncEmpty();
}

// Preserve the Godot bridge independently from the editor's presentation.
const rt = new Runtime($('#rt'), onRuntime);
const browserTests = new BrowserPlaytestController({ projectId: pid, iframe: $('#testRt'), host: window,
  fetcher: (...args) => fetch(...args), uuid,
  setTimer: (callback, delay) => window.setTimeout(callback, delay), clearTimer: timer => window.clearTimeout(timer),
  context: () => ({ enabled: isGodot(), visible: document.visibilityState !== 'hidden', mode, runId: workflow?.id || '' }),
  onView: (view, newCommand = false) => {
    browserTestView = view;
    if (view) { cancelWatchRequest(); clearTimeout(watchTimer); clearWatchFrame(); }
    if (newCommand && mode === 'edit') watchChoice = 'testing';
    renderPlaytest(); renderSceneEditor();
  }
});
// Module clicks can only come from the current, same-origin making surface.
// The normal Runtime callback deliberately does not accept this message twice.
addEventListener('message', event => {
  if (event.origin !== location.origin || event.source !== $('#rt').contentWindow || !event.data?.__ugc) return;
  const message = event.data.payload;
  if (message?.type !== 'module_focus' || mode !== 'edit' || isGodot() && message.previewSession !== previewExpected?.session) return;
  const focus = focusModule(message, inworldState?.modules || []);
  if (!focus) return;
  focusedModule = focus; renderParticipation(); layout();
});
// Construction and the game share this iframe. The first game pack replaces the yard;
// later checkpoints wait for the user's choice. Scene workers replay factual state.
const isGodot = () => proj?.game?.meta?.engine === 'godot';
let pckUrl = '', shownPckUrl = '', rtSrc = '', aiPlaying = false, reloadTimer = null;
sketch = new SketchBoardView($('#sketchBoard'), {
  onChange: ({ begin } = {}) => { if (begin) sketchChoice = 'auto'; syncSketch(); },
  onChoice: choice => { sketchChoice = choice; syncSketch(); },
});
// 2D games are built in front of the user: the real pack is shown and every new pack reloads
// with an assembly pass. Only before the first pack does a plain stage stand in for it.
const is2dGodot = () => isGodot() && proj?.game?.meta?.dimension !== '3d' && !validConstruction(proj?.game?.construction);
const hasBuildStage = () => is2dGodot() && !pckUrl && Boolean(inworldState?.plan?.modules?.length);
const liveBuild = () => mode === 'edit' && running && is2dGodot() && !observeConstruction;
const usesWorkshop = () => mode === 'edit' && (!pckUrl || observeConstruction || validConstruction(proj?.game?.construction));
function gpSrc(ai = false) { return usesWorkshop() ? '/gp.html?pck=%2Fworkshop.pck&edit=1&workshop=1' + (proj?.game?.meta?.dimension === '3d' || proj?.game?.construction?.dimension === '3d' ? '&dim=3d' : '') : '/gp.html?pck=' + encodeURIComponent(pckUrl) + (mode === 'play' ? '' : '&edit=1') + (liveBuild() && !ai ? '&assemble=1' : '') + (ai ? '&seed=1&ai=1' : ''); }
function gpShow({ ai = false, force = false } = {}) {
  if (!pckUrl && mode !== 'edit') return;
  const workshop = usesWorkshop();
  const src = gpSrc(ai);
  if (src === rtSrc && !force) return;
  rtSrc = src;
  shownPckUrl = workshop ? '' : pckUrl;
  constructionReceipt = null;
  const build = workshop ? {} : proj?.build || {};
  const sessionId = crypto.randomUUID?.() || Array.from(crypto.getRandomValues(new Uint32Array(4)), part => part.toString(16)).join('-');
  previewExpected = { ...build, session: sessionId, workshop };
  loadedBuild = null;
  preview = { status: workshop ? 'workshop_loading' : 'loading', message: workshop ? is2dGodot() ? '正在打开搭建舞台；第一版画面生成后会直接出现在这里。' : '正在打开施工观察视图；试玩由你开始。' : '正在打开场景，等待游戏首帧确认。' };
  renderWorkflow();
  $('#rtLoading').hidden = false;
  const params = new URLSearchParams({ previewSession: previewExpected.session });
  if (build.buildId) params.set('expectedBuildId', build.buildId);
  rt.reload(src + '&' + params);
  clearTimeout(previewTimer);
  const session = previewExpected.session;
  previewTimer = setTimeout(() => {
    if (previewExpected?.session !== session || !['loading', 'workshop_loading'].includes(preview.status)) return;
    preview = { status: workshop ? 'failed' : 'unverified', message: workshop ? '施工现场尚未载入，可重新打开预览；这不是用户游戏的验收结果。' : '尚未收到游戏首帧回执。场景可能仍在载入，可重新打开预览后确认。' };
    $('#rtLoading').hidden = true; renderWorkflow();
  }, 60000);
}
// Keep a playable checkpoint visible until the user chooses to open the new one.
function gpQueueReload() { clearTimeout(reloadTimer); renderWorkflow(); }
function gpReplayCrew() {
  if (mode !== 'edit') return;
  for (const message of inworldMessages(null, inworldState, true)) rt.send(message);
  if (previewExpected?.workshop && validConstruction(proj?.game?.construction)) rt.send({ type: 'construction', snapshot: proj.game.construction, restore: true });
  if (previewExpected?.workshop) { sceneEnabled = canEditScene(); rt.send({ type: 'editor_control', enabled: sceneEnabled }); }
  syncPrimaryPresentation(true);
}
function onRuntime(ev) {
  // Runtime already checks event.source against this iframe. The navigation token also
  // excludes late messages from an earlier document sharing the same WindowProxy.
  if (isGodot() && previewExpected && ev.previewSession !== previewExpected.session) return;
  if (ev.type === 'module_focus') return;
  if (isGodot() && previewExpected?.workshop) {
    if (ev.type === 'editor_selection') {
      const snapshot = proj?.game?.construction;
      if (validConstruction(snapshot) && ev.revision === snapshot.revision) {
        sceneSelection = ev.id ? { id: ev.id, label: ev.label, position: ev.position, pending: ev.pending === true, revision: ev.revision } : null;
        renderSceneEditor(); layout();
      }
    } else if (ev.type === 'editor_move') { saveSceneMove(ev); }
    else if (ev.type === 'construction_applied') {
      const receipt = assessConstructionReceipt(ev, proj?.game?.construction);
      if (receipt) { constructionReceipt = receipt; constructionReceipts.set(receipt.runId + ':' + receipt.revision, receipt); renderConstructionStatus(); }
    } else if (ev.type === 'ready' || ev.type === 'workshop_ready') {
      rt.ready = true; rt.q = []; clearTimeout(previewTimer); $('#rtLoading').hidden = true;
      const failed = ev.loaded === false || ev.errors?.length;
      preview = { status: failed ? 'failed' : 'workshop', message: failed ? '制作现场未能完整载入，请重新打开预览。' : is2dGodot() ? '搭建舞台已载入；第一版画面生成后会直接出现在这里。' : observeConstruction ? '施工观察视图已载入；点击试玩才会进入游戏。' : '施工现场已载入；等待用户游戏的首个试玩包。' };
      if (!failed) gpReplayCrew(); renderWorkflow();
    }
    else if (ev.type === 'js_error' || (ev.type === 'code_status' && ev.errors?.length)) { clearTimeout(previewTimer); $('#rtLoading').hidden = true; preview = { status: 'failed', message: '施工现场遇到问题：' + (ev.message || '场景载入失败') }; renderWorkflow(); }
    return;
  }
  if (ev.type === 'workshop_ready' || ['workshop', 'construction'].includes(ev.surface)) return;
  if (ev.type === 'ready' && isGodot()) { $('#rtLoading').hidden = true; clearTimeout(previewTimer); recordPreview(ev); gpReplayCrew(); if (!running && ev.loaded) setTimeout(maybeCover, 2500); }
  else if (ev.type === 'ready') { $('#rtLoading').hidden = true; if (proj) loadRuntime(); }
  else if (ev.type === 'code_status' && isGodot()) recordPreview(ev);
  else if (ev.type === 'build_idle') maybeCover();
  else if (ev.type === 'select') setSelection(ev.id);
  else if (ev.type === 'moved' && proj) {
    api('/projects/' + pid + '/move', { body: { id: ev.id, position: ev.position } }).catch(e => toast('位置保存失败：' + e.message));
    const entity = ev.id === '__player' ? proj.game.player : proj.game.entities[ev.id]; if (entity) entity.position = ev.position;
  } else if (ev.type === 'js_error') { if (isGodot()) recordPreview(ev); else { addError(ev.message || '场景运行失败'); } }
}
async function recordPreview(ev) {
  if (previewExpected?.workshop || ev.type === 'workshop_ready' || ['workshop', 'construction'].includes(ev.surface)) return;
  const result = assessPreview(ev, previewExpected);
  if (['stale', 'ignore'].includes(result.status)) return;
  clearTimeout(previewTimer);
  const session = previewExpected.session;
  // Once a runtime error occurred, a delayed ready cannot clear that error.
  if (preview.status === 'failed' && result.status === 'verified') return;
  if (result.status === 'verified') loadedBuild = { buildId: ev.buildId, sourceRevision: ev.sourceRevision, loaded: true };
  else if (['failed', 'unverified'].includes(result.status)) loadedBuild = null;
  preview = { ...result, message: result.status === 'verified' ? '当前版本已载入并绘制首帧，正在保存预览回执。' : result.message || result.errors.join('\n') };
  $('#rtLoading').hidden = true; renderWorkflow();
  if (result.status === 'failed') setWorkflowOpen(true, false);
  if (!result.receipt) return;
  const key = session + ':' + JSON.stringify(result.receipt);
  if (receiptKeys.has(key)) return;
  receiptKeys.add(key);
  try {
    const saved = await api('/projects/' + pid + '/preview_receipt', { body: result.receipt });
    // HTTP success acknowledges a saved receipt. Its ok flag describes the game result,
    // so a correctly recorded failure legitimately returns ok: false.
    if (typeof saved.ok !== 'boolean' || (result.status === 'verified' && !saved.ok)) throw new Error('服务未确认回执');
    if (previewExpected?.session !== session) return;
    if (saved.workflow?.id === workflow?.id) updateWorkflow(saved.workflow);
    if (result.status === 'verified' && preview.status === 'verified') preview.message = '当前版本已在此预览载入并绘制首帧，回执已保存。';
    renderWorkflow();
  } catch (error) {
    receiptKeys.delete(key);
    if (previewExpected?.session !== session) return;
    preview = { ...preview, status: result.status === 'failed' ? 'failed' : 'receipt_failed', message: preview.message + '\n预览回执保存失败：' + error.message };
    renderWorkflow();
  }
}
function assetStates() {
  const out = {};
  for (const [id, asset] of Object.entries(proj.game.assets || {})) out[id] = { kind: asset.kind, state: asset.state, url: asset.url || '' };
  return out;
}
function loadRuntime(nextMode = mode) {
  if (!proj) return;
  if (isGodot()) return gpShow({ force: true });
  rt.send({ type: 'load', spec: proj.game, assets: assetStates(), mode: nextMode });
}
function syncInworld(event) {
  const next = reduceInworldEvent(inworldState, event, workflow, proj);
  const previous = inworldState; inworldState = next;
  if (mode === 'edit') for (const message of inworldMessages(previous, next)) rt.send(message);
  renderParticipation();
}
function restoreInworld() {
  const next = restoreInworldWorkflow(workflow, proj, inworldState);
  const previous = inworldState; inworldState = next;
  if (mode === 'edit') for (const message of inworldMessages(previous, next)) rt.send(message);
  renderParticipation();
}
// SSE and polling feed one contiguous cursor, so a later live event cannot hide a gap.
let es = null, lastEventAt = 0, gotData = false, pollTimer = null, pollRequest = null, resetting = null;
let eventCursor = createEventCursor();
const eventsDuringReset = [];
const snapshotTextThrough = new Map();
const snapshotSummaries = new Set();
let snapshotReceivedAt = 0;
function route(ev) {
  if (ev.type === 'reset') { recoverEvents(ev).catch(showConnectionError); return; }
  if (resetting) { eventsDuringReset.push(ev); return; }
  lastEventAt = Date.now(); gotData = true;
  for (const ready of eventCursor.ingest(ev)) handle(ready);
  if (eventCursor.gap && !pollRequest && !resetting) queueMicrotask(() => pollEvents(true));
}
function connect() {
  es?.close(); clearInterval(pollTimer);
  es = new EventSource('/api/projects/' + pid + '/events?stream=1&since=' + eventCursor.seq);
  es.onmessage = e => { try { route(JSON.parse(e.data)); } catch (error) { showConnectionError(error); } };
  es.onerror = () => { pollEvents(true); };
  pollTimer = setInterval(pollEvents, 4000);
}
function showConnectionError(error) {
  $('#workflowStatus').textContent = '制作状态同步中，正在重连';
  $('#workflowBtn').dataset.tone = 'error';
  $('#workflowBtn').title = '状态同步失败：' + (error?.message || '网络连接中断');
}
async function recoverEvents(result) {
  if (resetting) return resetting;
  resetting = (async () => {
    // A truncated log needs a current authoritative snapshot, including the active pack.
    const fresh = await api('/projects/' + pid);
    proj = fresh; observeConstruction ||= validConstruction(fresh.game?.construction); updateWorkflow(fresh.workflow || result.workflow); invalidateSceneTests();
    restoreChat(fresh.chat);
    syncTitle(); syncRetryAssets(); setRunning(!!fresh.running);
    const boundary = Number.isSafeInteger(fresh.seq) ? fresh.seq : result.seq;
    for (const ready of eventCursor.reset(boundary)) handle(ready);
    if (isGodot()) {
      pckUrl = fresh.pck || '';
      if (validConstruction(fresh.game?.construction)) { constructionReceipt = null; presentConstruction(true); }
      else if (fresh.pck) { if (!shownPckUrl) gpShow(); else renderWorkflow(); }
    }
    delete $('#workflowBtn').title;
  })();
  try { await resetting; } finally {
    resetting = null;
    for (const ev of eventsDuringReset.splice(0)) route(ev);
  }
}
async function pollEvents(force = false) {
  if (pollRequest) return pollRequest;
  if (!force && !eventCursor.gap && gotData && Date.now() - lastEventAt < 12000) return;
  pollRequest = (async () => {
    try {
      const result = await api('/projects/' + pid + '/events?since=' + eventCursor.seq);
      if (result.reset) await recoverEvents(result);
      else for (const ev of result.events || []) route(ev);
      delete $('#workflowBtn').title;
      renderWorkflow();
    } catch (error) { showConnectionError(error); }
  })();
  try { await pollRequest; } finally { pollRequest = null; }
}
addEventListener('pagehide', () => { es?.close(); es = null; sketch.close(); clearInterval(pollTimer); clearTimeout(previewTimer); clearInterval(studioTimer); clearTimeout(watchTimer); cancelWatchRequest(); browserTests.suspend('页面已离开'); });
addEventListener('pageshow', event => { if (event.persisted && proj && !es) { connect(); sketch.connect(pid); pollEvents(true); pollWatch(); browserTests.sync(); studioTimer = setInterval(renderClock, 1000); } });
document.addEventListener('visibilitychange', () => {
  clearTimeout(watchTimer); cancelWatchRequest(); browserTests.sync();
  if (document.visibilityState === 'hidden') { syncPrimaryPresentation(); return; }
  // Bring the current factual state into the paused workshop before it renders again.
  // Runtime tests own their separate lifecycle; presentation is sent only through rt.
  if (isGodot() && rt.ready && mode === 'edit' && previewExpected?.workshop && primaryPresentation === false
    && !(watchChoice === 'testing' && (browserTestView || playtestState.watch))) gpReplayCrew();
  renderPlaytest(); pollWatch();
});
function handle(ev) {
  if (returnsToMaking(ev) || isWritingProgress(ev) && (!writingProgress || (writingProgress.id || '') !== (ev.id || ''))) { watchChoice = 'making'; renderPlaytest(); }
  updateWritingProgress(ev);
  if (isWritingProgress(ev)) return;
  const activity = activityFromEvent(ev, workflow?.id);
  if (activity) { liveActivity = [...liveActivity.filter(row => row.id !== activity.id), activity].slice(-60); }
  switch (ev.type) {
    case 'workflow': case 'task': updateWorkflow(reduceWorkflow(workflow, ev)); break;
    case 'participation': proj.participation = mergeParticipation(proj.participation, ev.participation); if (ev.participationDelivery) proj.participationDelivery = ev.participationDelivery; renderParticipation(); layout(); break;
    case 'code_write': if (workflow && ev.sourceRevision && (!ev.runId || ev.runId === workflow.id)) workflow.sourceRevision = ev.sourceRevision; break;
    case 'runtime_test': browserTests.receive(ev); break;
    case 'playtest_watch': receivePlaytest(ev.watch); break;
    case 'construction': {
      const next = acceptConstruction(proj?.game?.construction, ev.snapshot, workflow?.id, ev.runId);
      if (next && next !== proj.game.construction) {
        proj.game.construction = next; observeConstruction = true; constructionReceipt = null;
        if (sceneSelection && !next.objects.some(row => row.id === sceneSelection.id)) sceneSelection = null;
        presentConstruction(ev.origin === 'user');
      }
      break;
    }
    case 'scene_edit': proj.sceneDirty = ev.sceneDirty ?? ev.dirty ?? true; proj.sceneSourceRevision = ev.sceneSourceRevision || ev.sourceRevision; invalidateSceneTests(); renderWorkflow(); break;
    case 'turn_start':
      if (typeof ev.model === 'string' && proj) proj.model = ev.model;
      if (ev.engine === 'godot' && proj) proj.game.meta.engine = 'godot';
      syncParticipationDelivery(ev.engine); setRunning(true); break;
    case 'tool_start': endStream(); break;
    case 'text':
      // A different agent may still be streaming while this agent is in the snapshot.
      if (typeof ev.t === 'number' && ev.t <= (snapshotTextThrough.get(ev.agent || '') || 0)) break;
      if (curText && (ev.agent || '') !== curAgent) endStream();
      if (!curText) { curText = addAi('', true); curAgent = ev.agent || ''; }
      curText.textContent += ev.delta || ''; notifyReply(); scroll(); break;
    case 'plan': if (ev.title) { proj.game.meta.title = ev.title; syncTitle(); } break;
    case 'design':
      proj.game.design = ev.design;
      if (ev.design?.title) { proj.game.meta.title = ev.design.title; syncTitle(); }
      break;
    case 'roadmap': if (proj.game.design) { proj.game.design.milestones = ev.milestones; proj.game.design.current = ev.current; } break;
    case 'ops':
      if (isGodot() || ev.ops.some(op => op.op === 'pck')) {
        for (const op of ev.ops) {
          if (op.op === 'pck') { pckUrl = proj.pck = op.url; proj.build = { buildId: op.buildId, sourceRevision: op.sourceRevision, contentHash: op.contentHash, version: op.version }; if (!observeConstruction && (!shownPckUrl || liveBuild())) gpShow(); else gpQueueReload(); }
          else if (op.op === 'ai_play' && mode === 'edit' && !previewExpected?.workshop && !playtestState.watch) { aiPlaying = true; if (!rtSrc) gpShow({ ai: true }); }
          else if (op.op === 'eval' && !previewExpected?.workshop && !playtestState.watch && canForwardTestInput(mode, isGodot(), loadedBuild, proj?.build)) rt.send({ type: 'eval', code: op.code });
          else if (op.op === 'set_meta') { proj.game.meta = op.meta; syncParticipationDelivery(op.meta?.engine); syncTitle(); layout(); }
          else if (op.op === 'asset') proj.game.assets[op.id] = { ...(proj.game.assets[op.id] || {}), id: op.id, kind: op.kind, state: 'pending', url: '' };
        }
        syncRetryAssets(); break;
      }
      // the agent's test drive plays in the preview itself, outside the build queue
      if (ev.ops.some(op => op.op === 'ai_play' || op.op === 'eval')) {
        for (const op of ev.ops) {
          if (op.op === 'ai_play' && mode === 'edit' && !playtestState.watch) rt.send({ type: 'ai_play', spec: proj.game });
          else if (op.op === 'eval' && !playtestState.watch && canForwardTestInput(mode, false, null, null)) rt.send({ type: 'eval', code: op.code });
        }
        break;
      }
      for (const op of ev.ops) {
        if (op.op === 'asset') proj.game.assets[op.id] = { ...(proj.game.assets[op.id] || {}), id: op.id, kind: op.kind, state: 'pending', url: '' };
        if (op.op === 'add' || op.op === 'update') proj.game.entities[op.id] = op.entity;
        if (op.op === 'remove') delete proj.game.entities[op.id];
        if (op.op === 'set_player') proj.game.player = op.player;
        if (op.op === 'set_world') proj.game.world = op.world;
        if (op.op === 'set_rules') proj.game.rules = op.rules;
        if (op.op === 'set_meta') { proj.game.meta = op.meta; syncParticipationDelivery(op.meta?.engine); }
        if (op.op === 'code') proj.game.code = { files: op.files };
      }
      if (mode === 'edit') rt.send({ type: 'ops', ops: ev.ops });
      syncRetryAssets(); layout(); break;
    case 'asset': case 'asset_stage': {
      const asset = proj.game.assets[ev.id] = { ...(proj.game.assets[ev.id] || {}), ...ev, type: undefined };
      if (ev.type === 'asset') asset.state = ev.state;
      syncRetryAssets();
      if (ev.type === 'asset' && (ev.state === 'ready' || ev.state === 'failed') && !isGodot() && mode === 'edit') rt.send({ type: 'asset', id: ev.id, kind: ev.kind, state: ev.state, url: ev.url || '' });
      break;
    }
    case 'error': endStream(); addError(ev.message || '暂时遇到问题，请稍后重试。'); break;
    case 'turn_end': {
      endStream();
      const inSnapshot = typeof ev.t === 'number' && (ev.t <= (snapshotTextThrough.get('') || 0)
        || (ev.t <= snapshotReceivedAt && snapshotSummaries.has(ev.summary)));
      if (!inSnapshot) { if (ev.summary) addAi(ev.summary); addSugg(ev.suggestions); }
      setRunning(false);
      updateWorkflow(reduceWorkflow(workflow, ev));
      if (ev.build) proj.build = ev.build;
      if (ev.engine === 'godot') { aiPlaying = false; if (ev.pck) pckUrl = proj.pck = ev.pck; if (!observeConstruction && !shownPckUrl) gpShow(); }
      else if (ev.engine === 'code' && mode === 'edit') loadRuntime(mode);
      break;
    }
  }
  syncInworld(ev);
  if (mode === 'edit' && hasBuildStage() && ['design', 'turn_start'].includes(ev.type)) gpShow();
  if (activity || ['ops', 'turn_end', 'design', 'plan', 'roadmap'].includes(ev.type)) renderWorkflow();
}
function setRunning(value) {
  if (!value) clearWritingProgress();
  running = value; $('#stopBtn').hidden = !value; $('#stopBtn').disabled = false;
  $('#iterationTier').disabled = value;
  renderWorkflow();
  browserTests.sync();
  scheduleWatchPoll();
}
function syncParticipationDelivery(engine) {
  if (proj && engine) proj.participationDelivery = engine === 'godot' ? 'live' : 'next_round';
}
function syncTitle() { $('#title').value = proj.game.meta.title || '未命名游戏'; document.title = $('#title').value + ' · 造梦'; }
function syncRetryAssets() {
  const assets = Object.values(proj?.game?.assets || {});
  const button = $('#retryAssetsBtn');
  button.hidden = !assets.some(asset => asset.state === 'failed' || asset.fallback);
  button.textContent = assets.some(asset => asset.fallback) ? '重试未完成素材' : '重试失败素材';
}
$('#retryAssetsBtn').onclick = async () => {
  const button = $('#retryAssetsBtn'); button.disabled = true;
  try { await api('/projects/' + pid + '/retry_assets', { body: {} }); toast('正在重新生成素材'); }
  catch (error) { toast('重试失败：' + error.message); }
  finally { button.disabled = false; }
};

// Fit to the scene's own space, leaving the workshop outside the game and its HUD.
const portrait = () => (proj?.game?.meta?.orientation || qs.get('ori')) === 'portrait';
function layout() {
  const stage = $('#sceneSpace'), frame = $('#frameWrap');
  const viewportHeight = Math.round(window.visualViewport?.height || innerHeight);
  document.documentElement.style.setProperty('--appH', viewportHeight + 'px');
  const por = portrait(); document.body.classList.toggle('por', por); document.body.classList.toggle('lan', !por);
  const landscapePreview = !por && !document.body.classList.contains('chat-view');
  document.body.classList.toggle('landscape-preview', landscapePreview);
  const statusBars = document.body.classList.contains('chat-view') ? $('.scene-toolbar').offsetHeight + 8 + ($('#constructionStatus').hidden ? 0 : $('#constructionStatus').offsetHeight + 4) : 0;
  const barHeight = mode !== 'play' ? statusBars + ($('#sceneEditBar').hidden ? 0 : $('#sceneEditBar').offsetHeight + 6) : 0;
  const width = Math.max(0, stage.clientWidth), height = Math.max(0, stage.clientHeight - barHeight), aspect = por ? 9 / 16 : 16 / 9;
  const rotated = landscapePreview && height > width;
  document.body.classList.toggle('preview-rotated', rotated);
  stage.style.setProperty('--previewToolbarH', barHeight + 'px');
  const frameWidth = Math.floor(landscapePreview ? (rotated ? height : width) : Math.min(width, height * aspect));
  const frameHeight = Math.floor(landscapePreview ? (rotated ? width : height) : frameWidth / aspect);
  frame.style.setProperty('--frameW', frameWidth + 'px'); frame.style.setProperty('--frameH', frameHeight + 'px');
  // Keep fixed-layout games at their authored aspect inside the iframe. Fill
  // the preview surface without clipping HUD/controls or exposing unused world.
  const runtimeHeight = Math.max(1, Math.round(frameWidth / aspect));
  frame.style.setProperty('--runtimeH', runtimeHeight + 'px');
  frame.style.setProperty('--runtimeScaleY', String(frameHeight / runtimeHeight));
}
function resizeInput() { input.style.height = 'auto'; input.style.height = Math.min(110, input.scrollHeight) + 'px'; layout(); }
addEventListener('resize', layout);
window.visualViewport?.addEventListener('resize', layout);
new ResizeObserver(layout).observe($('#stage'));
new ResizeObserver(layout).observe($('#sceneSpace'));
input.addEventListener('input', () => { resizeInput(); renderParticipation(); });
input.addEventListener('compositionstart', () => { composing = true; });
input.addEventListener('compositionend', () => { composing = false; });
input.addEventListener('keydown', event => {
  if (event.key === 'Enter' && !event.shiftKey && !event.isComposing && !composing && event.keyCode !== 229) { event.preventDefault(); send(); }
});
async function send() {
  const text = input.value.trim(); if (!text || !proj || composing || participationPending) return;
  if (running || participationAttempt?.key === JSON.stringify([text, focusedModule?.file || ''])) return submitParticipation(text);
  if (modelSelection.pending) { toast('模型选择正在保存，请稍候'); return; }
  input.value = ''; resizeInput(); endStream(); addUser(text); setRunning(true);
  try {
    const selected = focusedModule ? focusedModule.label + '（模块文件 ' + focusedModule.file + '）' : sceneSelection ? (sceneSelection.label || sceneSelection.id) + '（场景 id=' + sceneSelection.id + '）' : selection ? (selection === '__player' ? '主角' : (proj.game.entities[selection]?.name || selection) + '（id=' + selection + '）') : '';
    await api('/projects/' + pid + '/chat', { body: { text, dimension: qs.get('dim') || proj.game.meta.dimension, selection: selected, iteration: iterationRequest($('#iterationTier').value) } });
  } catch (error) {
    setRunning(false); addError('发送失败：' + error.message);
    if (!input.value) { input.value = text; resizeInput(); }
  }
}
async function submitParticipation(text) {
  const file = focusedModule?.file || '', key = JSON.stringify([text, file]);
  const moduleFile = (proj.game.design?.modules || []).some(row => row.file === file) ? file : '';
  const content = file && !moduleFile ? '关于「' + focusedModule.label + '」（' + file + '）：\n' + text : text;
  if (content.length > 800) { participationError = '建议还未提交：请缩短到 800 字以内，草稿已保留'; renderParticipation(); layout(); return; }
  if (participationAttempt?.key !== key) participationAttempt = { key, body: { text: content, ...(moduleFile ? { moduleFile } : {}), requestId: uuid() } };
  participationPending = true; participationError = ''; renderParticipation();
  try {
    const { response, result } = await sceneRequest('/participation', participationAttempt.body);
    if (!response.ok || !result?.ok || !Array.isArray(result.participation)) throw new Error(result?.error || '建议暂未确认收到');
    proj.participation = mergeParticipation(proj.participation, result.participation);
    if (input.value.trim() === text) { input.value = ''; resizeInput(); }
    participationAttempt = null;
  } catch (error) {
    participationError = '建议未确认收到，草稿已保留：' + (error.name === 'AbortError' ? '连接超时，请重试' : error.message);
  } finally { participationPending = false; renderParticipation(); layout(); }
}
$('#sendBtn').onclick = send;
$('#moduleFocusClear').onclick = () => { focusedModule = null; renderParticipation(); layout(); };
$('#moduleSuggestions').onclick = event => {
  const button = event.target.closest('[data-module-suggestion]'), suggestion = button && moduleSuggestions(focusedModule)[Number(button.dataset.moduleSuggestion)];
  if (!suggestion) return;
  input.value = (input.value.trim() ? input.value.trim() + '\n' : '') + suggestion; resizeInput(); input.focus({ preventScroll: true });
};
$('#stopBtn').onclick = async () => {
  const button = $('#stopBtn'); button.disabled = true;
  try { await api('/projects/' + pid + '/stop', { body: {} }); }
  catch (error) { button.disabled = false; addError('停止失败：' + error.message); }
};
function setSelection(id) {
  selection = id || null; const chip = $('#selChip'); chip.hidden = !selection;
  if (!selection || !proj) return;
  const name = selection === '__player' ? '主角' : (proj.game.entities[selection]?.name || selection);
  chip.innerHTML = '<span>已选中「' + esc(name) + '」</span><button aria-label="取消选择">×</button>';
  $('button', chip).onclick = () => setSelection(null);
}
function setMode(nextMode, silent = false) {
  if (nextMode === 'play' && (sceneEditPending || sceneBuildPending)) { toast('请等待场景保存和试玩版本生成完成'); return; }
  if (nextMode === 'play' && proj?.sceneDirty) return buildSceneForPlay().then(ok => { if (ok) setMode(nextMode, silent); });
  if (nextMode === 'play') watchChoice = 'making';
  mode = nextMode; $$('#modeSeg button').forEach(button => {
    const active = button.dataset.m === nextMode;
    button.classList.toggle('on', active); button.setAttribute('aria-pressed', String(active));
  });
  document.body.classList.toggle('playing', nextMode === 'play'); if (nextMode === 'play') setChat(false, false); renderConstructionStatus(); syncSketch(); layout();
  clearTimeout(watchTimer); cancelWatchRequest(); watchFrameEpoch++; watchImagePending = null; renderPlaytest();
  browserTests.sync();
  if (nextMode === 'edit') pollWatch();
  if (!silent) { loadRuntime(nextMode); if (nextMode === 'play') { setSelection(null); setTimeout(() => rt.focus(), 100); } }
}
$$('#modeSeg button').forEach(button => { button.onclick = () => {
  if (!proj) return;
    if (isGodot() && button.dataset.m === 'play' && !pckUrl && !proj.sceneDirty) { toast('可运行版本生成后就可以试玩'); return; }
  setMode(button.dataset.m);
}; });
function setMenu(open) { $('#moreMenu').hidden = !open; $('#moreBtn').setAttribute('aria-expanded', String(open)); }
$('#moreBtn').onclick = event => { event.stopPropagation(); setMenu($('#moreMenu').hidden); };
$('#moreMenu').addEventListener('click', event => { if (event.target.closest('button')) setMenu(false); });
document.addEventListener('click', event => { if (!event.target.closest('#moreMenu')) setMenu(false); });
document.addEventListener('keydown', event => {
  if (event.key !== 'Escape' || event.isComposing) return;
  if (!$('#moreMenu').hidden) { setMenu(false); $('#moreBtn').focus(); }
  else if (!feed.hidden) { event.preventDefault(); setChat(false); }
  else if (!$('#workflowPanel').hidden) { event.preventDefault(); setWorkflowOpen(false); }
});
$('#frameBtn').onclick = () => rt.send(previewExpected?.workshop ? { type: 'editor_control', action: 'frame' } : { type: 'frame' });
let muted = false;
$('#muteBtn').onclick = () => { muted = !muted; rt.send({ type: 'mute', value: muted }); $('#muteBtn').textContent = muted ? '打开声音' : '关闭声音'; };
$('#fsBtn').onclick = async () => { try { await $('#frameWrap').requestFullscreen?.(); await screen.orientation?.lock?.(portrait() ? 'portrait' : 'landscape'); } catch {} };

let coverTime = 0;
async function maybeCover() {
  if (!proj || previewExpected?.workshop || Date.now() - coverTime < 20000 || (!Object.keys(proj.game.entities).length && !proj.game.code && !(isGodot() && proj.game.design))) return;
  coverTime = Date.now(); const data = await rt.snapshot();
  if (data) api('/projects/' + pid + '/cover', { body: { data } }).catch(() => {});
}
$('#verBtn').onclick = async () => {
  try {
    proj = await api('/projects/' + pid);
    updateWorkflow(proj.workflow);
    const modal = document.createElement('div'); modal.className = 'modal-bg';
    modal.innerHTML = '<div class="modal"><h3>版本历史</h3><p>每次搭建完成都会自动保存，可以随时回到之前的版本。</p><div class="ver-list">' + (proj.versions.slice().reverse().map(version => '<button data-v="' + version.v + '"><b>v' + version.v + '</b><span style="flex:1">' + esc((version.prompt || '').slice(0, 40)) + '</span><span class="hint">' + ago(version.t) + '</span></button>').join('') || '<div class="hint">还没有版本</div>') + '</div><div style="text-align:right;margin-top:14px"><button class="btn" id="vClose">关闭</button></div></div>';
    document.body.appendChild(modal); $('#vClose', modal).onclick = () => modal.remove();
    $$('.ver-list button', modal).forEach(button => { button.onclick = async () => {
      try {
        proj = await api('/projects/' + pid + '/restore', { body: { v: +button.dataset.v } });
        observeConstruction = validConstruction(proj.game?.construction) || (proj.game?.meta?.dimension === '3d' && !proj.pck);
        updateWorkflow(proj.workflow);
        pckUrl = proj.pck || '';
        modal.remove(); syncTitle(); syncRetryAssets(); setSelection(null); setMode('edit', true); loadRuntime('edit'); addAi('已回到 v' + button.dataset.v + ' 版本。');
      } catch (error) { toast('恢复失败：' + error.message); }
    }; });
  } catch (error) { toast('读取版本失败：' + error.message); }
};
async function coverShot() {
  if (proj.game.meta.dimension !== '3d' || mode === 'play') return rt.snapshot();
  const previous = mode; await setMode('play');
  if (mode !== 'play') throw new Error('当前场景尚未生成可试玩版本');
  try { await new Promise(resolve => setTimeout(resolve, 2600)); return await rt.snapshot(); }
  finally { setMode(previous); }
}
$('#pubBtn').onclick = async () => {
  if (!proj) return;
  if (running) { toast('搭建完成后就可以发布'); return; }
  if (!Object.keys(proj.game.entities).length && !proj.game.code?.files?.['main.gd'] && !(isGodot() && pckUrl && proj.game.design)) { toast('先搭建一个游戏再发布'); return; }
  try {
    const check = await api('/projects/' + pid + '/check'), shot = await coverShot();
    const modal = document.createElement('div'); modal.className = 'modal-bg';
    modal.innerHTML = '<div class="modal"><h3>发布游戏</h3><p>发布后，大家可以在「发现」里游玩或改编你的游戏。</p>' + (shot ? '<div class="pub-cover" style="background-image:url(data:image/jpeg;base64,' + shot + ')"></div>' : '') + '<div class="field"><label>游戏名称</label><input id="pTitle" maxlength="40"></div><div class="field"><label>一句话介绍</label><input id="pPitch" maxlength="120"></div>' + (check.ok ? '' : '<div class="check bad" style="margin:0 0 14px">自检发现问题：' + esc(check.issues.filter(issue => issue.level === 'error').map(issue => issue.text).join('；')) + '</div>') + '<div style="display:flex;gap:10px;justify-content:flex-end"><button class="btn" id="pCancel">取消</button><button class="btn pri" id="pGo">发布</button></div></div>';
    document.body.appendChild(modal); $('#pTitle', modal).value = $('#title').value; $('#pPitch', modal).value = proj.game.meta.pitch || '';
    $('#pCancel', modal).onclick = () => modal.remove();
    $('#pGo', modal).onclick = async () => {
      const button = $('#pGo', modal); button.disabled = true;
      try {
        const result = await api('/projects/' + pid + '/publish', { body: { title: $('#pTitle', modal).value, pitch: $('#pPitch', modal).value, cover: shot } });
        modal.innerHTML = '<div class="modal" style="text-align:center"><h3>发布成功</h3><p>你的游戏已经出现在「发现」里了。</p><div style="display:flex;gap:10px;justify-content:center"><a class="btn" href="/">去发现页</a><a class="btn pri" href="' + esc(result.url) + '">打开游戏</a></div></div>';
        modal.onclick = event => { if (event.target === modal) modal.remove(); };
      } catch (error) { button.disabled = false; toast('发布失败：' + error.message); }
    };
  } catch (error) { toast('准备发布失败：' + error.message); }
};
$('#title').onchange = () => { if (proj) { proj.game.meta.title = $('#title').value; document.title = $('#title').value + ' · 造梦'; } };

// History loads quietly. Only later replies receive an unread marker.
$('#iterationTier').value = iterationRequest(qs.get('tier')).tier;
setWorkflowOpen(false, false);
studioTimer = setInterval(renderClock, 1000);
renderClock();
setChat(true, false);
(async () => {
  try {
    if (!pid) throw new Error('没有找到项目，请返回首页选择一个作品。');
    proj = await api('/projects/' + pid); observeConstruction = validConstruction(proj.game?.construction) || (proj.game?.meta?.dimension === '3d' && !proj.pck); snapshotReceivedAt = Date.now(); syncTitle(); layout();
    modelSelection.sync(proj.model, !!proj.running); modelSelection.load();
    eventCursor = createEventCursor(proj.seq);
    updateWorkflow(proj.workflow);
    restoreChat(proj.chat);
    syncEmpty(); syncRetryAssets(); setRunning(!!proj.running); restoringHistory = false; connect(); sketch.connect(pid);
    if (isGodot()) { pckUrl = proj.pck || ''; gpShow(); renderWorkflow(); }
    else rt.reload('/game/index.html');
    pollWatch();
    await pollEvents(true);
    const go = qs.get('go');
    if (go && (!proj.chat.length || (qs.get('remix') === '1' && !proj.chat.some(message => message.role === 'user')))) {
      history.replaceState(null, '', '/editor.html?id=' + pid + '&dim=' + (qs.get('dim') || '2d'));
      input.value = go; resizeInput(); setTimeout(send, 300);
    }
  } catch (error) { restoringHistory = false; setRunning(false); addError(error.message); toast('项目加载失败：' + error.message); }
})();
