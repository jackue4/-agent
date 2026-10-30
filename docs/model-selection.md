# 按作品选择创作模型

2026-10-28，选择器位于编辑页对话输入框上方；首页新建作品的最后一步也可选择。默认维持 Kimi，旧作品没有显式选择时继续使用平台默认设置。

| 界面名称 | 网关实际 ID | 工具协议 |
| --- | --- | --- |
| Opus 5.5 | `claude-opus-5-5` | Chat Completions，工具选择只能自动 |
| Opus 5 | `claude-opus-5` | Chat Completions |
| Opus 4.8 | `claude-opus-4-8` | Chat Completions |
| Sonnet 5.5 | `claude-sonnet-5-5` | Chat Completions |
| GPT 6.1 Sol / Terra | `gpt-6.1-sol`、`gpt-6.1-terra` | Responses |
| GPT 6 Sol / Luna / Astra | `gpt-6-sol`、`gpt-6-luna`、`gpt-6-astra` | Responses |
| GPT 5.6 Sol / Luna / Terra | `gpt-5.6-sol`、`gpt-5.6-luna`、`gpt-5.6-terra` | Chat Completions |
| GPT 5.5、5.4 Pro、5.4、5.4 Mini、5.4 Nano、5.2 | 同名 ID | Chat Completions |
| DeepSeek V4.1 Flash | `deepseek-v4.1-flash` | Chat Completions |
| Kimi K3.1 高速 | `kimi-k3.1-pro-highspeed` | Chat Completions |

这些 ID 均来自当前网关的模型目录，标签对应该条目本身。带供应商标记的重复入口没有放进选择器。DeepSeek 仍用目录中的 V4.1 Flash 无日期入口。

选择保存在作品中，刷新和后续制作保留。制作或保存中禁止切换；已开始的一轮使用固定选择，主制作与协作任务保持一致。选择不会修改游戏源码、重新导出游戏或重载场景。保存失败时界面回读服务端状态并提示，避免显示未确认的选择。

`GET /api/models` 返回可选项及默认值；`POST /api/projects/:id/model` 保存选择。未知 ID 返回 400，忙碌返回 409；新建、对话、继续制作也接受经过相同校验的 `model` 字段。

选项都接入公司网关的 OpenAI 兼容 Base URL `https://aigate.mini1.cn/v1`。GPT 6 与 GPT 6.1 的函数工具走 Responses，其余走 Chat Completions。流式文本、工具调用与图片结果仍转换成同一套内部事件。不会因失败偷偷换模型。2026-10-29 新增的 GPT 与 Opus 通过了一次真实函数工具调用；这不是完整游戏或图像理解验收。

四个模型分别通过了真实的两轮工具调用与随机图像观察小样。初次失败和修复后记录保留在 `artifacts/model-selection/model-probes.json`、`tool-probes-followup.json`、`image-probes.json`。这些验证说明当前网关传输和工具链可用，不等同于四个模型各自完成了完整游戏质量验收。

最终平台回归 530 / 530 通过，日志为 `artifacts/model-selection/all-tests.log`。真实浏览器已验证首页创建步骤的四选项、编辑页逐项保存、Sonnet 刷新保留、对话栏展开时选择器可见，并将示例作品恢复为原 Kimi 选择。切换期间游戏 iframe 会话未改变，示例源码版本与构建 ID 保持原值。截图位于同目录的 `create-model-picker.png`、`editor-dialog-model.png`。
