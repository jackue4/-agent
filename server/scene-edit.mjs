import { applyConstruction } from './construction.mjs';

/** User transforms use the same canonical scene as AI construction and exported play. */
export function moveConstruction(snapshot, body = {}) {
  if (!snapshot || snapshot.dimension !== '3d' || !Array.isArray(snapshot.objects)) throw new Error('当前关卡还没有可编辑的实体');
  if (!Number.isSafeInteger(body.baseRevision) || body.baseRevision !== snapshot.revision) {
    const error = new Error('场景已经更新，请在最新位置上重试'); error.status = 409; throw error;
  }
  if (typeof body.requestId !== 'string' || !/^[a-zA-Z0-9_-]{8,100}$/.test(body.requestId)) throw new Error('编辑请求标识无效');
  const object = snapshot.objects.find(row => row.id === body.id);
  if (!object) throw new Error('所选实体已不存在');
  if (!Array.isArray(body.position) || body.position.length !== 3 || body.position.some(n => typeof n !== 'number' || !Number.isFinite(n) || Math.abs(n) > 200)) throw new Error('位置需要三个 -200 到 200 范围内的有限数字');
  return applyConstruction(snapshot, { baseRevision: body.baseRevision, step: '调整「' + (object.label || object.id) + '」的位置', ops: [{ op: 'upsert', id: object.id, position: body.position }] }, { runId: snapshot.runId });
}
