// Server-committed scene snapshots are authoritative; streamed code is never geometry.
export function validConstruction(snapshot) {
  return Boolean(snapshot && snapshot.schema === 1 && snapshot.dimension === '3d'
    && Number.isSafeInteger(snapshot.revision) && snapshot.revision >= 0
    && typeof snapshot.runId === 'string' && Array.isArray(snapshot.objects));
}
export function acceptConstruction(current, snapshot, activeRunId, eventRunId) {
  if (!validConstruction(snapshot)) return current;
  if (eventRunId && (eventRunId !== snapshot.runId || activeRunId && eventRunId !== activeRunId)) return current;
  if (validConstruction(current) && snapshot.revision <= current.revision) return current;
  return snapshot;
}
export function assessConstructionReceipt(event, snapshot) {
  if (!validConstruction(snapshot) || event.type !== 'construction_applied' || event.surface !== 'construction'
    || event.runId !== snapshot.runId || event.revision !== snapshot.revision) return null;
  const errors = (Array.isArray(event.errors) ? event.errors : []).map(error => typeof error === 'string' ? error : error.message || '场景应用失败');
  if (event.objectCount !== snapshot.objects.length) errors.push('实际落地对象数量与本次场景不一致');
  return { revision: event.revision, runId: event.runId, loaded: event.loaded === true && errors.length === 0, objectCount: event.objectCount, errors };
}
