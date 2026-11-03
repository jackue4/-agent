import test from 'node:test';
import assert from 'node:assert/strict';
import { assetIntent } from '../art-intent.mjs';

test('ordinary requests keep the pencil look and generate nothing', () => {
  for (const text of ['做一个跑酷游戏', '把背景换成淡蓝色的天空', '继续', '加一个第二关，敌人更多', '主角跳得高一点', '换个玩法，改成三消', '画面更有层次一些']) {
    assert.deepEqual(assetIntent(text), { finalArt: false, kinds: [] }, text);
  }
});

test('asking for art or a new style opens finished art and every asset kind', () => {
  for (const text of ['帮我生成游戏素材', '上正式美术', '换成像素风', '改成赛博朋克风格', '给主角做个立绘', '美化一下画面', '把铅笔稿替换成正式美术']) {
    const r = assetIntent(text);
    assert.equal(r.finalArt, true, text);
    assert.ok(r.kinds.includes('sprite') && r.kinds.includes('music'), text);
  }
});

test('sound and 3D model requests open only their own kinds', () => {
  assert.deepEqual(assetIntent('加一段背景音乐和音效'), { finalArt: false, kinds: ['music', 'sfx'] });
  assert.deepEqual(assetIntent('配个BGM'), { finalArt: false, kinds: ['music', 'sfx'] });
  assert.deepEqual(assetIntent('生成一个3D模型的宝箱'), { finalArt: false, kinds: ['model3d'] });
});

test('a refused asset stays refused', () => {
  assert.deepEqual(assetIntent('不要生成素材，继续做玩法'), { finalArt: false, kinds: [] });
  assert.deepEqual(assetIntent('别换画风，加点音效'), { finalArt: false, kinds: ['music', 'sfx'] });
});
