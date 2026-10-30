/** Deployment contract, not a claim that every Godot subsystem has been tested. */
export const GODOT_CAPABILITIES = Object.freeze({
  id: 'godot-web-compatibility-v1', engine: 'Godot 4.7', target: 'Web', language: 'GDScript', renderer: 'gl_compatibility', threads: false, nativeExtensions: false,
  available: ['2D/3D scenes and nodes', 'signals and autoloads', 'Control UI', 'AnimationPlayer and Tween', '2D/3D physics', 'Navigation', 'TileMapLayer', 'text resources', 'Compatibility shaders and particles', 'generated image/audio/GLB import', 'res:// reading and user:// saves'],
  unavailable: ['C#', 'GDExtension', 'Thread/WorkerThreadPool', 'RenderingDevice/compute shaders', 'Forward+ effects', 'OS commands', 'direct HTTP/WebSocket/WebRTC/ENet', 'editor plugins and @tool', 'arbitrary filesystem access', 'desktop/mobile export'],
  verification: 'Interface availability only. Each requested behavior needs compilation, actual Web input, assertions and an exact build/source receipt.',
  limits: { textFiles: 120, charsPerFile: 200000, construction3dObjects: 96, constructionBatch: 8 },
});

export function compatibilityIssues(file, src) {
  const issues = [];
  const gd = file.endsWith('.gd');
  const sourceLines = String(src).split('\n');
  const codeLines = (gd ? withoutGdText(String(src)) : String(src)).split('\n');
  for (const [index, line] of sourceLines.entries()) {
    const code = codeLines[index];
    if (gd && /\b(?:Thread|WorkerThreadPool|RenderingDevice)\b/.test(code)) issues.push(file + ':' + (index + 1) + ' 当前 Web 交付不支持线程或 RenderingDevice，请使用主线程分帧处理和 Compatibility 着色器');
    if (file === 'project.godot' && /^\s*renderer\/rendering_method(?:\.mobile)?\s*=\s*"(?!gl_compatibility")/.test(line)) issues.push(file + ':' + (index + 1) + ' 当前 Web 交付必须使用 gl_compatibility 渲染器');
  }
  return issues;
}

// Keep newlines and identifiers; skip quoted strings (including triple quotes) and comments.
function withoutGdText(source) {
  let out = '', quote = '', comment = false;
  for (let i = 0; i < source.length; i++) {
    const char = source[i];
    if (comment) { if (char === '\n') { comment = false; out += char; } else out += ' '; continue; }
    if (quote) {
      if (char === '\\') { out += ' '; if (i + 1 < source.length) out += source[++i] === '\n' ? '\n' : ' '; }
      else if (source.startsWith(quote, i)) { out += ' '.repeat(quote.length); i += quote.length - 1; quote = ''; }
      else out += char === '\n' ? '\n' : ' ';
      continue;
    }
    if (char === '#') { comment = true; out += ' '; }
    else if (char === '"' || char === "'") { quote = source.startsWith(char.repeat(3), i) ? char.repeat(3) : char; out += ' '.repeat(quote.length); i += quote.length - 1; }
    else out += char;
  }
  return out;
}
