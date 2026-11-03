// A game keeps its hand-drawn pencil look for its whole life. AI assets and finished art are only
// produced when the player's own message asks for them; nothing upgrades the style on its own.

const ALL_KINDS = Object.freeze(['background', 'sprite', 'texture', 'model3d', 'music', 'sfx']);
const CLAUSE = '[^，。！？；,.!?;\\n]';
const NEGATED = new RegExp('(不要|别|不用|无需|不需要|禁止|先不|暂不|不想|不必)' + CLAUSE + '*', 'g');
const VISUAL = [
  new RegExp('(生成|做|出|换|上|加|接入|升级|替换|配|添加|来|弄|制作|用|画)' + CLAUSE + '{0,8}(正式美术|美术|素材|贴图|立绘|原画|画风|皮肤|精美画面|正式画面|AI ?图)', 'i'),
  new RegExp('(换成|改成|变成|改为|换个|换种|换一种|切换成|切换到)' + CLAUSE + '{0,10}(风格|画风|美术风|' + CLAUSE + '{1,6}风(?=$|[的，。！？；,.!?;\\s]))'),
  /正式美术|美化(一下)?(画面|美术|游戏)|画面(升级|美化)|升级画面|提升画质/,
];
const AUDIO = new RegExp('(生成|做|出|换|上|加|配|添加|来|弄|制作|要)' + CLAUSE + '{0,8}(背景音乐|音乐|BGM|配乐|音效|声音|音频)', 'i');
const MODEL = new RegExp('(生成|做|出|换|加|添加|制作)' + CLAUSE + '{0,8}(3D ?模型|三维模型)', 'i');

/**
 * What this message explicitly asks for. finalArt: replace the pencil look with generated art
 * (the art director runs, any asset kind may be requested). kinds: asset kinds the builder may
 * request this round; empty means stay pencil and generate nothing.
 */
export function assetIntent(text) {
  const s = String(text || '').replace(NEGATED, ' ');
  if (VISUAL.some(re => re.test(s))) return { finalArt: true, kinds: [...ALL_KINDS] };
  const kinds = [];
  if (AUDIO.test(s)) kinds.push('music', 'sfx');
  if (MODEL.test(s)) kinds.push('model3d');
  return { finalArt: false, kinds };
}
