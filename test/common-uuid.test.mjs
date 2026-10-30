import test from 'node:test';
import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
import { uuid } from '../web/common.js';

test('uuid works on plain-http LAN pages where crypto.randomUUID is missing', t => {
  const real = Object.getOwnPropertyDescriptor(globalThis, 'crypto');
  t.after(() => Object.defineProperty(globalThis, 'crypto', real));
  Object.defineProperty(globalThis, 'crypto', { configurable: true, value: { getRandomValues: a => webcrypto.getRandomValues(a) } });
  const ids = new Set(Array.from({ length: 200 }, uuid));
  assert.equal(ids.size, 200);
  for (const id of ids) assert.match(id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});
