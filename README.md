# 造梦 · AI UGC 游戏平台 Demo

说一句话 → 看 AI 无人机在 Godot 引擎里一块一块把游戏搭出来 → 一键发布到发现页给所有人玩 / Remix。

## 创作工作流首版（2026-10-27）

默认新项目使用完整 Godot 工程。现在支持独立任务并行制作、按源码版本验收、浏览器实际加载回执，以及中断后的继续修复。创作页的「制作进度」可展开查看真实任务、测试和待处理问题；已合入文件与已通过验收分别显示。

- 不同任务各自修改分配的文件，候选通过归属、基线冲突检查后合入。默认最多两个任务同时执行；一个失败不撤销其他独立任务的成果。
- 完成需要当前源码版本的编译/启动检查、含有效断言的 `auto_test()`、不可变预览包和该包的浏览器启动回执。素材仍在生成、失败任务未修复或测试过期时只能保存部分成果。
- 服务重启、取消或失败后保存工作记录、候选和错误；点击「继续修复」或输入「继续」接着处理。不会在平台启动时自动重跑外部请求。
- 发布使用同一个已验收的构建。旧项目仍可打开和试玩；旧包未带版本身份时显示尚未验证，继续创作并通过验收后即可获得新构建。

模块与验收边界见 [工作流接入说明](docs/workflow-integration.md)。独立开发任务的候选区与文件允许列表不是操作系统沙箱；浏览器回执证明该包已启动，完整玩法仍以项目测试和实际试玩为准。

本轮回归：`node --test "server/test/**/*.test.mjs" test/workflow-view.test.mjs`。
隔离验证可设置 `UGC_DATA_DIR` 和 `PORT`，数据目录不会混入默认 `data/`。`server/scripts/workflow-demo.mjs` 会在指定的隔离目录创建一个故意包含计分错误的样例，供继续修复流程测试；已存在同名项目时拒绝覆盖。

## 启动

```powershell
cd D:\ugc-ai
.\Start-Services.ps1     # 启动主站 5300 和游戏服务 5178
# .\Start-Services.ps1 -Tunnel  # 同时启动公网隧道

# 也可以单独启动主站：
cd D:\ugc-ai\server
node server.mjs          # http://10.0.4.94:5300
```

整个项目自包含在 `D:\ugc-ai`：Godot 可执行文件在 `tools\godot\`，不依赖别的目录。
找不到时可用环境变量 `GODOT_BIN` 指定任意一份 Godot 4.7.2 console 版。

- LLM：公司网关 AiGate，OpenAI 兼容 Base URL 为 `https://aigate.mini1.cn/v1`，创作请求发到 `/v1/chat/completions`。`AIGATE_URL` 可覆盖这个 base；若仍填旧的 `/v1/messages` 地址，也会改写到 Chat Completions。平台本地 `model-config.local.json` 的 `model`、`codeModel` 默认均为 `kimi-k3.1-pro-highspeed`；完整 Godot 工程与分工任务共同使用 `codeModel`。`UGC_MODEL` 环境变量覆盖两项，`UGC_CODE_MODEL` 优先覆盖工程/分工模型。配置修改后由平台维护者重启生效；保留原配置或显式指定模型名即可恢复，不会在请求失败后自动换模型。
  对话输入附近和新建作品入口支持按作品选择模型。2026-10-29 起目录包含已验证能调用工具的 GPT 5.2–6.1，以及 Opus 5.5、Opus 5、Opus 4.8，并保留 Sonnet 5.5、DeepSeek V4.1 Flash、Kimi K3.1 高速。完整 ID 见 `server/model-config.mjs`。选择单独保存在作品中，刷新与续作保留；未选择的旧作品沿用上述默认配置。制作中禁止切换，同一轮主制作与协作任务固定使用本轮选择，不影响其他作品。
  `GET /api/models` 返回可选目录；`POST /api/projects/:id/model` 接收 `{ "model": "实际模型 ID" }`。未知选项返回 400，制作或保存中返回 409。创建和对话请求也可显式携带 `model`，并通过同一校验。
  Opus、Sonnet、DeepSeek、Kimi 与 GPT 5.x 使用 Chat Completions 与 `max_completion_tokens`。GPT 6 与 GPT 6.1 的函数工具在 Chat Completions 上会被拒绝，因此改走同一 base 下的 Responses（`/v1/responses`）。Opus 5.5 不接受强制指定工具，这类请求会改成自动选择。工具执行、取消和断线恢复逻辑不变，不会自动改选其他模型。2026-10-28 的四模型真实工具与图像小样验证记录位于 `artifacts/model-selection/`；这不是完整游戏质量或长期稳定性的保证。
  `server/model-config.mjs` 导出实际选择与来源，配置文件只存模型名，非法配置直接报错。此网关的 Kimi 工具图片会在原工具结果之后转为独立用户图片消息，保留工具结果文本和调用 ID；随机数字/图形的真实工具循环已通过，证据见 `artifacts/module-workshop/model-probe.json`。这只证明图像传输可用，游戏仍需实际输入与断言验收。开启思考时不使用强制指定工具模式。
  Key 读 `AIGATE_API_KEY` 环境变量，否则读 `~/.dsh/.credentials.yaml`。
- 素材：aigc-tool MCP（nanobanana 出图 + removebg 抠图、suno 音乐、elevenlabs 音效、hunyuan_3d 模型）。
  可选环境变量：`UGC_3D_PROVIDER`（默认 hunyuan_3d）、`UGC_3D_TIMEOUT`（默认 360000ms，超时自动降级为抠图公告板）。

## 页面

| 页面 | 作用 |
|---|---|
| `/` | 响应式造梦首页：角色舞台、作品卡片、搜索与分类；底部五个入口（首页 / 角色 / ＋创造 / 聊天 / 我的） |
| `/editor.html?id=` | 极简创作页：完整游戏画面、底部输入框；点击聊天图标打开右侧对话栏，更多菜单包含发布与版本历史 |
| `/play.html?id=` | 游玩页：全屏游玩，按游戏方向横/竖自适应 |

点「＋」打开三步创作面板：先选类型（卡牌/消除/跑酷/射击/解谜/塔防/经营/自由），再选 2D/3D 和竖屏/横屏，最后描述灵感并选择制作档位。关闭或返回会保留本机草稿，提交沿用原有创作接口和编辑器。

首页角色、角色衣橱和个人头像共用五款原创形象，选择与个人昵称/简介保存在当前浏览器。个人中心的作品、发布状态、游玩/获赞数据来自真实 `/api/me` 接口，支持搜索、已发布/草稿筛选和继续编辑。聊天页提供搜索、联系人、会话、消息及草稿本机保存；当前服务没有账号/好友消息后端，所有示例会话明确标注“本机演示”，不会发送给其他用户。界面代码位于 `web/home.js`、`home.css`、`create-flow.js`/`.css`、`social.js`/`.css`。
方向会一路传下去：策划方案、屏幕布局、按钮尺寸、AI 自测截图尺寸都按竖屏/横屏走（竖屏 720x1280，横屏 1280x720）。

手机访问：默认绑定本机局域网 IP `10.0.4.94`，同一网络下用 `http://10.0.4.94:5300`；独立游戏服务为 `http://10.0.4.94:5178`。IP 变化后可用启动脚本的 `-ListenAddress` 或环境变量 `HOST` 覆盖监听地址，并同步调整测试脚本中的访问地址。
需要公网时用 `cloudflared tunnel --url http://10.0.4.94:5300`（临时链接，重开会变）。

## 经典模板项目的搭建过程

1. Claude 不写代码，只调用工具（`plan_game / set_world / add_entities / generate_assets / check_game / finish`…），**流式**返回。
2. 服务器 `engine.mjs` 把每次工具调用变成*构建操作*（ops），通过 SSE 推给浏览器。
3. 浏览器把 ops 交给 iframe 里的 Godot Web 运行时，**无人机飞过去、打光束、物体弹出 + 粒子 + 音效**，按节奏逐个播放。
4. AI 的执行反馈留在游戏场景中：无人机飞行、简短状态和逐项显现。网页不展示技术卡片、思考过程或常驻进度面板；对话与后续建议在按需打开的侧栏中。
5. AI 素材在后台并发生成，完成后**在游戏里原地换装**；失败素材可从更多菜单重试。
6. 可在画面里点选 / 拖动物体，选中后直接对话修改它；每轮自动存版本，可回退。

## 经典代码引擎（保留兼容旧项目）

以下是 `UGC_ENGINE=classic` 时的原有路线；默认的新项目使用上文的完整 Godot 工程工作流：

1. **设计师（Opus）** \`codegen.mjs → planGame\`：输出完整方案卡——最接近的已知游戏 + 关键差异（防同质化）、核心循环、具体规则数值、屏幕布局、模块拆分与接口、M1~M4 里程碑（每个带验收标准）、M1 搭建步骤、调色板/美术圣经、0-3 个 AI 素材（后台立即开始生成）。用户可以直接说"规则改成…"来修正。
2. **程序员（Opus）** \`runProgrammer\`：在平台 SDK \`G\`（\`runtime/kit.gd\`：卡牌/按钮/拖拽/飘字/数字滚动/粒子/音效/胜负…）之上写 GDScript 模块（\`write_module / patch_module\`），并在 \`main.gd\` 里写 \`auto_test()\` 真实地把核心流程点一遍。
3. **每写完一个模块**：静态安全检查（禁 OS/文件/网络/JS/load…）→ 真实 Godot 无头试加载（约 3 秒）→ 能跑就**热更新到用户预览**，无人机把新出现的节点一个个飞过去点亮。
4. **run_test**：真实 Godot 运行 \`auto_test()\`，返回编译/运行错误（文件:行号）、每条断言、胜负，并附一张截图给模型看布局；模型修到通过（每轮最多 8 次）。
5. **finish** → 存版本、推进里程碑；用户说"继续"就做下一个里程碑，或按反馈修改 / \`update_plan\` 调整路线。

创作界面默认只呈现游戏画面和简短输入框。首版等待时场景内显示游戏标题及一句状态，搭建过程中保留无人机反馈；详细方案、模块代码和自测卡不再占据用户界面。

相关文件：\`server/codegen.mjs\`（提示词、工具、会话）、\`server/runner.mjs\`（Godot 测试运行器 + 静态检查）、\`runtime/kit.gd\`（SDK，autoload \`G\`）、\`runtime/code_world.gd\`（动态加载/热更新/揭示动画）。
测试：\`node test/e2e_code.mjs "做一个小丑牌" ["继续"]\`（全流程）、\`node test/code_shot.mjs <id> out.jpg\`（渲染任意代码项目并跑自测）、\`node test/e2e_code_web.mjs\`（Web 导出里的动态编译）。

## 目录

```
tools/godot/  Godot 4.7.2 可执行文件（引擎本体）
runtime/   Godot 4.7 数据驱动运行时（解释 JSON 游戏 spec；2D 平台/俯视，3D 第三人称）
web/       前端（发现页、编辑器、游玩页）+ web/game 为运行时导出产物
server/    Node 服务：agent.mjs(LLM 工具循环) engine.mjs(spec + ops + 可玩性检查) aigc.mjs(素材) server.mjs(HTTP/SSE)
data/      项目、素材、封面
```

改了 runtime 之后需要重新导出：

```powershell
cd D:\ugc-ai\runtime
..\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release Web ../web/game/index.html
```

首次在新机器上跑（或删掉了 `.godot` 缓存）要先导入一次资源，否则字体会加载失败：

```powershell
cd D:\ugc-ai\runtime
..\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
```

## 质量保障

AI 生成的关卡不止“看起来能过”——每一层都有自动化验证：

| 层 | 内容 | 命令（在 D:\ugc-ai 下） |
|---|---|---|
| 服务端单测（130） | spec 规范化、跳跃物理模型（与运行时同一组参数）、可达性/关键路径、告示牌遮挡、重试退避、工具循环 | `cd server; npm test` |
| Godot 无头测试（66） | 实体构建、规则状态机、胜负/星级、暂停、触屏摇杆、主题别名 | `runtime\tests\run_tests.gd`（见 run_all，66 项） |
| **自动通关机器人** | 按服务端算出的关键路径，用真实运行时物理按键操作，从出生点打到终点（会踩怪/跳刺） | `node test\bot_play.mjs <项目id>` |
| 截图回归 | 编辑/游玩/开始卡/胜利/失败/暂停、2D+3D | `test\shots.ps1`（`-Project <id>` 渲染任意项目） |
| 浏览器端到端 | 桌面游玩页、手机竖屏（触屏模拟）、发布弹窗封面 | `node test\e2e_play.mjs <id>` / `e2e_mobile.mjs` / `e2e_publish.mjs` |
| AI 全流程 | 真实调用 LLM + 素材生成，输出关卡体检报告 | `node test\e2e_create.mjs 2d "<一句话>"` |

一键跑完（需服务已启动）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File test\run_all.ps1
```

## 已知限制（Demo）

- 单用户、无登录、无审核（审核钩子位置：发布接口 `/publish`）。
- 模板游戏：横版跳跃、俯视冒险（2D），3D 跳跃探索；其它 2D 类型走代码引擎（M1 约 6-10 分钟，Opus 较慢），3D 代码游戏暂不支持。
- 3D 模型生成 3~5 分钟；超时会自动降级为 2D 公告板，可在素材工坊点失败素材重试。
