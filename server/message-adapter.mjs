/** AiGate's Kimi Messages bridge does not reliably forward images nested inside
 * tool_result.content, or mixed with tool_result blocks. A separate user image
 * message is verified by a random visual tool-loop probe. Keep tool IDs/text and
 * lift only the images; never alter stored history. */
export function messagesForModel(messages, model) {
  if (model !== 'kimi-k3.1-pro-highspeed') return messages;
  return messages.flatMap(message => {
    if (message.role !== 'user' || !Array.isArray(message.content)) return [message];
    const attachments = [];
    const content = message.content.map(block => {
      if (block.type !== 'tool_result' || !Array.isArray(block.content)) return block;
      const images = block.content.filter(item => item.type === 'image');
      if (!images.length) return block;
      attachments.push({ type: 'text', text: 'Image attachment from tool response ' + String(block.tool_use_id || '') + ':' }, ...images);
      const rest = block.content.filter(item => item.type !== 'image');
      return { ...block, content: rest.length ? rest : [{ type: 'text', text: 'The tool image is attached below.' }] };
    });
    return attachments.length ? [{ ...message, content }, { role: 'user', content: attachments }] : [message];
  });
}
