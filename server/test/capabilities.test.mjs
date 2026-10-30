import test from 'node:test';
import assert from 'node:assert/strict';
import { compatibilityIssues, GODOT_CAPABILITIES } from '../capabilities.mjs';
test('Web deployment rejects native-only APIs without rejecting their names in UI strings', () => {
  assert.equal(GODOT_CAPABILITIES.threads, false);
  for (const type of ['Thread', 'WorkerThreadPool', 'RenderingDevice']) assert.equal(compatibilityIssues('main.gd', 'var native: ' + type).length, 1);
  assert.deepEqual(compatibilityIssues('main.gd', '# Thread\nvar help = "Thread"'), []);
  assert.deepEqual(compatibilityIssues('main.gd', 'var help = "Thread #1"'), []);
  assert.equal(compatibilityIssues('main.gd', 'var help = "#"; var worker = Thread.new()').length, 1);
  assert.deepEqual(compatibilityIssues('main.gd', 'var help = """Thread\nWorkerThreadPool # note\n"""'), []);
  assert.equal(compatibilityIssues('main.gd', 'var help = "escaped \\" quote"; var worker = Thread.new()').length, 1);
  assert.deepEqual(compatibilityIssues('main.gd', 'extends Node2D\nvar timer: Timer'), []);
  assert.equal(compatibilityIssues('project.godot', 'renderer/rendering_method="forward_plus"').length, 1);
  assert.deepEqual(compatibilityIssues('project.godot', 'renderer/rendering_method="gl_compatibility"'), []);
});
