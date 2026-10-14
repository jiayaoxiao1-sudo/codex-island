# Codex Island：Agent 交接入口

这是 macOS 像素灵动岛安装与操作包。先读本文件，再读 `plugins/codex-island/skills/use-codex-island/SKILL.md`。这两份文件足以理解如何安装、使用和核对结果；无需原始聊天历史。

## 用户可直接交给 Agent 的提示词

> 请阅读这个包里的 AGENT-START.md，帮我安装并启动 Codex Island，核对它能显示我的主对话、用量和未查看结果。保留已有未读记录，告诉我首次 hooks 信任需要在哪里完成。

## 安装

1. macOS 13+；安装包包含 Apple Silicon / Intel 通用二进制。
2. 需要已安装 Codex/ChatGPT 桌面应用，并创建过本地 Codex 聊天。
3. 当前监控器依赖 Apple Command Line Tools 的 `/usr/bin/python3`。缺少时可由用户安装：`xcode-select --install`。
4. 双击 `Codex-Island-2.8.pkg`，按 macOS Installer 的步骤安装。它将安装辅助文件，并为当前登录用户配置应用、插件和登录服务。若安装时没有桌面用户，按提示稍后执行用户配置。
5. 配置命令：`/usr/bin/python3 "/Library/Application Support/Codex Island Installer/install.py" --prebuilt`。不需要重新编译，不应以 root 身份直接运行此命令。
6. 首次插件 hooks 信任须通过 Codex 正常审阅入口完成；CLI 可用 `/hooks`。安装程序不绕过审批。

## 怎么用

点击顶部条展开；任务竖向排列，过多时滚动；点击卡片打开用户主对话；点击窗外收起。内部 Guardian review 不显示，子代理归到主对话。音效是短像素提示音，通知只显示主对话标题和该轮最终输出。未读结果保留至从悬浮窗点击查看，重启仍保留。菜单栏可静音或退出。

## Agent 如何检查

运行插件中的 `scripts/islandctl.py status`（只读）。检查 `installed`、`processAlive`、`reportAgeSeconds`、`health.build`、`health.windowVisible` 和任务计数。没有新报告时不要声称是实时数据。读取的仅为该用户本机记录，远程或云端聊天不自动包含。

安装后位置：

- 应用：`~/Library/Application Support/Codex Island/Codex Island.app`
- 状态：同目录 `health.json`
- 未读记录：同目录 `pending-completions.json`、`read-receipts/`
- 插件：`codex-island@codex-island-local`，包含自动发现的 `use-codex-island` 技能
- 登录服务：`~/Library/LaunchAgents/local.codex.island.watcher.plist`

升级、修复时保留未读记录。不读取或分享 `~/.codex/auth.json`。本包没有作者的账户、聊天快照或个人用量。macOS 安装包尚无 Developer ID 签名、公证；分发前应如实说明。

卸载用户插件和自动启动：`/usr/bin/python3 "/Library/Application Support/Codex Island Installer/uninstall.py"`。该操作保留应用和本地未读记录。
