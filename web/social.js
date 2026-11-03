import { esc } from '/common.js';

const STORAGE_KEY = 'dream.social.preview.v1';
const validTimestamp = at => Number.isFinite(at) && Math.abs(at) <= 8.64e15;
const ICONS = {
  search: '<circle cx="10.8" cy="10.8" r="6.8"/><path d="m16 16 4.5 4.5"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  arrow: '<path d="m14 6-6 6 6 6"/>',
  send: '<path d="m21 3-6 18-4-8-8-4 18-6ZM11 13 21 3"/>',
  chat: '<path d="M21 11.5a8.5 8.5 0 0 1-8.5 8.5H4l-2 2V11.5a9.5 9.5 0 0 1 19 0Z"/><path d="M7 11h.01M12 11h.01M17 11h.01"/>',
  group: '<circle cx="9" cy="8" r="3"/><path d="M3 20v-2a6 6 0 0 1 12 0v2M17 5a3 3 0 0 1 0 6M21 20v-2a6 6 0 0 0-3-5"/>',
  spark: '<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5L12 3Z"/>',
};
const svg = name => '<svg viewBox="0 0 24 24" aria-hidden="true">' + ICONS[name] + '</svg>';
const CONTACTS = [
  { id: 'momo', name: 'Momo', subtitle: '喜欢把奇思妙想变成小游戏', color: 'peach', face: '✿', seed: '今天的灵感：在云朵上开一家小小的咖啡店。', unread: 1 },
  { id: 'orbit', name: '小宇宙', subtitle: '探索每一种好玩的可能', color: 'purple', face: '✦', seed: '这里可以聊玩法、分享灵感，也可以约朋友一起玩。', unread: 0 },
  { id: 'leaf', name: '阿绿', subtitle: '收集像素世界里的小快乐', color: 'green', face: '☘', seed: '想试试一起创作的感觉？在下方写一句话吧。', unread: 1 },
];

function initialState() {
  return Object.fromEntries(CONTACTS.map(c => [c.id, { messages: [{ role: 'them', text: c.seed, at: 0 }], unread: c.unread, draft: '' }]));
}

function readState() {
  const state = initialState();
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null');
    if (!saved || saved.version !== 1 || typeof saved.chats !== 'object') return state;
    for (const contact of CONTACTS) {
      const record = saved.chats[contact.id];
      if (!record || !Array.isArray(record.messages)) continue;
      const messages = record.messages.filter(m => m && ['them', 'me'].includes(m.role) && typeof m.text === 'string' && validTimestamp(m.at))
        .slice(-100).map(m => ({ role: m.role, text: m.text.slice(0, 600), at: m.at }));
      state[contact.id] = { messages: messages.length ? messages : state[contact.id].messages, unread: record.unread ? 1 : 0, draft: typeof record.draft === 'string' ? record.draft.slice(0, 600) : '' };
    }
  } catch { /* A restricted browser still supports an in-memory preview. */ }
  return state;
}

function avatar(contact, small = false) {
  return '<span class="social-avatar social-avatar-' + contact.color + (small ? ' social-avatar-small' : '') + '" aria-hidden="true"><span>' + contact.face + '</span></span>';
}

function timeLabel(at) {
  if (at === 0) return '示例';
  if (!validTimestamp(at)) return '时间未知';
  return new Intl.DateTimeFormat('zh-CN', { hour: '2-digit', minute: '2-digit' }).format(at);
}

/** This is a local UI preview until an authenticated social service is available. */
export function mountSocial(root, { profile = {} } = {}) {
  if (!root) throw new Error('Missing social root');
  let chats = readState(), active = null, section = 'messages', query = '', persistOK = true;
  root.classList.add('social-root');
  root.innerHTML = '<div class="social-workspace"><aside class="social-sidebar" aria-label="会话列表">'
    + '<div class="social-list-heading"><h2>聊天<span class="social-unread-total"></span></h2><button class="social-icon-button social-new" aria-label="新建示例聊天" title="新建示例聊天">' + svg('plus') + '</button></div>'
    + '<div class="social-tabs" role="tablist" aria-label="社交分类"><button type="button" role="tab" id="socialMessagesTab" aria-controls="socialContactList" data-section="messages" aria-selected="true">消息</button><button type="button" role="tab" id="socialFriendsTab" aria-controls="socialContactList" data-section="friends" aria-selected="false">好友</button></div>'
    + '<label class="social-search">' + svg('search') + '<input type="search" placeholder="搜索名字或聊天内容" aria-label="搜索聊天" autocomplete="off"></label>'
    + '<div class="social-contact-list" id="socialContactList" role="tabpanel" aria-labelledby="socialMessagesTab"></div>'
    + '<div class="social-local-note">' + svg('spark') + '<span>消息仅保存在此设备，<br>尚未连接好友服务</span></div></aside>'
    + '<section class="social-conversation" aria-label="聊天详情"></section></div>';

  const list = root.querySelector('.social-contact-list');
  const conversation = root.querySelector('.social-conversation');
  const search = root.querySelector('.social-search input');

  function persist() {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify({ version: 1, chats })); persistOK = true; }
    catch { persistOK = false; }
  }

  function updateUnread() {
    const count = CONTACTS.reduce((total, c) => total + chats[c.id].unread, 0);
    const el = root.querySelector('.social-unread-total');
    el.textContent = count || ''; el.hidden = !count;
    root.dispatchEvent(new CustomEvent('social:unread', { bubbles: true, detail: { count } }));
  }

  function renderList() {
    const needle = query.toLocaleLowerCase();
    const contacts = CONTACTS.filter(c => (c.name + ' ' + (section === 'friends' ? c.subtitle : chats[c.id].messages.map(m => m.text).join(' '))).toLocaleLowerCase().includes(needle));
    list.setAttribute('aria-labelledby', section === 'messages' ? 'socialMessagesTab' : 'socialFriendsTab');
    list.innerHTML = (section === 'friends' ? '<div class="social-section-label">示例好友 · ' + contacts.length + '</div>' : '')
      + (contacts.length ? contacts.map(c => {
        const record = chats[c.id], last = record.messages.at(-1);
        return '<button type="button" class="social-contact' + (active === c.id ? ' is-active' : '') + '" data-contact="' + c.id + '" aria-label="打开 ' + c.name + ' 的示例聊天" aria-pressed="' + (active === c.id) + '">'
          + avatar(c) + '<span class="social-contact-copy"><span class="social-contact-title"><b>' + c.name + '</b><small>示例</small></span><span class="social-preview">' + esc(section === 'friends' ? c.subtitle : (last.role === 'me' ? '我：' : '') + last.text) + '</span></span>'
          + '<span class="social-contact-meta"><time>' + (section === 'friends' ? '' : timeLabel(last.at)) + '</time>'
          + (section === 'messages' && record.unread ? '<i class="social-unread" aria-label="1 条示例未读消息">1</i>' : '') + '</span></button>';
      }).join('') : '<div class="social-empty-search">' + svg('search') + '<b>还没找到</b><span>试试其他名字或关键词</span></div>');
    list.querySelectorAll('[data-contact]').forEach(button => button.onclick = () => openConversation(button.dataset.contact));
    updateUnread();
  }

  function showWelcome() {
    conversation.innerHTML = '<div class="social-welcome"><div class="social-welcome-art"><i class="social-orbit social-orbit-one"></i><i class="social-orbit social-orbit-two"></i><span class="social-welcome-bubble">' + svg('chat') + '</span><span class="social-welcome-star">✦</span><span class="social-welcome-spark">✳</span></div><span class="social-eyebrow">A LITTLE HELLO, A NEW WORLD</span><h2>从一句「你好」开始</h2><p>分享一个脑洞，遇见一起造梦的人。<br>先选一位示例好友，试试新的聊天体验。</p><button type="button" class="social-primary social-start">' + svg('plus') + '发起示例聊天</button><small>这里是交互预览，不会向其他用户发送消息。</small></div>';
    conversation.querySelector('.social-start').onclick = () => openConversation(CONTACTS[0].id);
  }

  function renderMessages() {
    const contact = CONTACTS.find(c => c.id === active), record = chats[active];
    const stream = conversation.querySelector('.social-stream');
    stream.innerHTML = '<div class="social-day">这是一个示例会话</div>' + record.messages.map(m => '<div class="social-message ' + (m.role === 'me' ? 'social-message-mine' : '') + '">'
      + (m.role === 'them' ? avatar(contact, true) : '<span class="social-my-avatar" aria-hidden="true">' + esc(String(profile.name || profile.nickname || '我').slice(0, 1)) + '</span>')
      + '<div class="social-message-body"><div class="social-bubble">' + esc(m.text) + '</div><small>' + (m.role === 'me' ? (persistOK ? '仅本机 · ' : '暂存于此页面 · ') + timeLabel(m.at) : '示例消息') + '</small></div></div>').join('');
    stream.scrollTop = stream.scrollHeight;
  }

  function openConversation(id) {
    if (!chats[id]) return;
    active = id; chats[id].unread = 0; persist(); renderList();
    root.classList.add('social-chat-open');
    const contact = CONTACTS.find(c => c.id === id);
    conversation.innerHTML = '<header class="social-chat-head"><button type="button" class="social-icon-button social-back" aria-label="返回聊天列表">' + svg('arrow') + '</button>' + avatar(contact, true)
      + '<div><h2>' + contact.name + '<span>示例好友</span></h2><p>聊聊下一个好玩的想法</p></div><span class="social-demo">本机演示</span></header>'
      + '<div class="social-chat-notice">消息仅保存在此设备，尚未连接好友服务</div>'
      + '<div class="social-stream" role="log" aria-live="polite" aria-label="与 ' + contact.name + ' 的示例聊天记录"></div>'
      + '<form class="social-compose"><div class="social-quick-replies" aria-label="试试这些开场白"><button type="button">一起做个小游戏？</button><button type="button">有个灵感想分享</button></div>'
      + '<div class="social-compose-field"><label class="social-visually-hidden" for="socialMessageInput">输入本机演示消息</label><textarea id="socialMessageInput" rows="1" maxlength="600" placeholder="聊点什么…" aria-describedby="socialMessageHelp"></textarea><button class="social-send" type="submit" aria-label="发送本机演示消息" disabled>' + svg('send') + '</button></div>'
      + '<div class="social-compose-footer"><span id="socialMessageHelp">Enter 发送 · Shift + Enter 换行</span><span class="social-character-count">0 / 600</span></div><p class="social-save-status" role="status" hidden></p></form>';
    const input = conversation.querySelector('textarea'), submit = conversation.querySelector('.social-send');
    input.value = chats[id].draft;
    function syncInput() {
      submit.disabled = !input.value.trim();
      conversation.querySelector('.social-character-count').textContent = input.value.length + ' / 600';
      input.style.height = 'auto'; input.style.height = Math.min(input.scrollHeight, 110) + 'px';
      chats[id].draft = input.value;
    }
    syncInput(); renderMessages();
    input.oninput = () => { syncInput(); persist(); };
    input.onkeydown = event => {
      if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) { event.preventDefault(); conversation.querySelector('form').requestSubmit(); }
    };
    conversation.querySelector('form').onsubmit = event => {
      event.preventDefault();
      const text = input.value.trim().slice(0, 600);
      if (!text) return;
      chats[id].messages.push({ role: 'me', text, at: Date.now() });
      chats[id].messages = chats[id].messages.slice(-100);
      input.value = ''; syncInput(); persist(); renderMessages(); renderList();
      const status = conversation.querySelector('.social-save-status');
      status.textContent = persistOK ? '已保存在此设备，未发送给其他用户。' : '浏览器未允许保存，这条消息暂存于当前页面。';
      status.hidden = false; input.focus();
    };
    conversation.querySelectorAll('.social-quick-replies button').forEach(button => button.onclick = () => { input.value = button.textContent; syncInput(); persist(); input.focus(); });
    conversation.querySelector('.social-back').onclick = () => {
      const previous = active;
      active = null; root.classList.remove('social-chat-open'); renderList(); showWelcome();
      list.querySelector('[data-contact="' + previous + '"]')?.focus();
    };
    if (matchMedia('(min-width: 701px)').matches) input.focus();
  }

  function switchSection(value) {
    section = value;
    root.querySelectorAll('[data-section]').forEach(button => { const selected = button.dataset.section === section; button.setAttribute('aria-selected', String(selected)); button.tabIndex = selected ? 0 : -1; });
    search.placeholder = section === 'friends' ? '搜索示例好友' : '搜索名字或聊天内容';
    renderList();
  }
  root.querySelectorAll('[data-section]').forEach(button => {
    button.onclick = () => switchSection(button.dataset.section);
    button.onkeydown = event => {
      if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
      event.preventDefault();
      switchSection(event.key === 'Home' ? 'messages' : event.key === 'End' ? 'friends' : section === 'messages' ? 'friends' : 'messages');
      root.querySelector('[data-section="' + section + '"]').focus();
    };
  });
  root.querySelector('.social-new').onclick = () => { switchSection('friends'); query = ''; search.value = ''; renderList(); list.querySelector('[data-contact]')?.focus(); };
  search.oninput = () => { query = search.value.trim(); renderList(); };
  switchSection('messages'); showWelcome();
  return {
    refresh(nextProfile) { if (nextProfile) profile = nextProfile; updateUnread(); },
    get unread() { return CONTACTS.reduce((total, c) => total + chats[c.id].unread, 0); },
  };
}
