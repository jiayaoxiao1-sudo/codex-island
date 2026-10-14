# Codex Island

Mac 原生像素风灵动岛，支持 macOS 13 及以上，使用 AppKit，无第三方运行依赖。

收起为 480×38 的扁长像素条；点击展开后根据任务数量调整高度，最高 592 点。在像素角色或边缘拖动可调整位置。菜单栏入口可以隐藏、重新定位、打开 Codex 或退出。

## 已提供的功能

- 顶部显示账户用量窗口、已用比例与运行任务数。
- 本机正在运行和等待确认的任务直接竖向排列，每项显示独立的像素动画、状态、累计 token、输入、输出和活动摘要。超过窗口高度时向下滚动；新任务刷新时保留当前可见任务的位置。没有运行任务时显示空状态。
- 点击任务卡片通过 `codex://threads/<thread-id>` 打开对应 Codex 页面，并收起悬浮窗。链接使用任务的真实 ID，按路径编码，不依赖标题，因此同名任务也能分别打开。该链接是[官方支持的任务链接](https://learn.chatgpt.com/docs/app/commands)。
- 像素动画根据可观察的操作状态变化：检索资料、修改文件、执行任务、验证结果、等待确认、完成和失败。它不展示或声称还原模型内部思考。
- 每 2 秒读取一次本机新记录。token 和账户额度按 Codex 返回的统计更新，模型生成期间不会凭空估算；显示报告年龄和重置时间。累计 token 包含重复上下文输入及缓存输入，不代表付费 token 数量，也不等同于账户额度。
- 每张卡片显示 Codex 已展示的简短状态标题和进度说明。只取摘要标题，不显示原始推理或摘要正文。
- 展开后点击悬浮窗外会自动收起，点击任务卡片仍会打开对应聊天。
- 步骤完成播放短像素音效，明确的整体完成事件播放四音上升旋律。菜单栏「完成音效」可以静音。
- 任务完成时在灵动岛下方弹出 8 秒的完成提示，点击提示可以打开结果。
- 已完成但未查看的任务继续留在列表中，标注「已完成 · 未查看」。点击卡片或完成提示，并成功请求打开对应 Codex 页面后，才标记为已查看并移出列表。未读状态保存在本机，悬浮窗或 Codex 重启后仍保留；同一聊天不同轮次分别记录，不会因开始下一轮而覆盖。查看判定以悬浮窗里的点击为准。
- 2.4 按用户主对话合并运行卡片及未查看轮次，子代理不会重复增加运行数量。内部 Guardian 审批会话从列表、未读记录和通知中排除，点击子任务结果也回到主对话。
- 小任务/本轮回复结束使用约 0.18 秒的轻像素提示音，完成弹窗只显示主对话标题与该轮公开的最终输出；长输出显示可容纳的前几行，点击打开主对话查看全文。不会把单轮结束宣称为整个长期目标完成。
- 2.5 增加明确的 `step` / `final` 两种事件，声音随对应弹窗播放。Agent 可用插件内 `scripts/notify.py notify` 指定阶段；整体完成必须由 Agent 在工作已完成时明确发出 `final`。普通轮次结束默认仍是小步骤，不能据此判断整个项目已完成。`notify.py demo` 可实际演示“两次小音效 → 一次最终音效”，并等待悬浮窗的播放回执。
- 通过本地插件的生命周期 hooks 接收任务状态；当前桌面版还可读取本机 SQLite 与 rollout 的状态和用量事件，因此未信任 hooks 时也可以显示已有本地任务。
- 用户级登录服务等待 Codex 启动并显示悬浮窗，Codex 退出后收起窗口并停止数据监控。所有数据均保留本机，不发送至外部服务，不读取登录凭证。

## 安装及首次配置

运行 `python3 install.py`，安装范围为：

1. `~/Library/Application Support/Codex Island/Codex Island.app`
2. 本地插件市场 `codex-island-local` 及插件 `codex-island@codex-island-local`
3. `~/Library/LaunchAgents/local.codex.island.watcher.plist`

安装后需在 Codex 中审阅并信任此插件 hooks 一次。Codex 自身按 hook 定义的 hash 管理信任，升级 hook 后可能需要重新审阅；安装脚本不会绕过信任检查。CLI 可通过 `/hooks` 检查和信任；桌面版使用其 hooks 审阅入口。插件生命周期事件从信任后的新会话开始生效。

直接运行 `zsh build.sh` 只构建应用，不安装插件及登录服务。源码为 `Sources/main.m`、`bridge/monitor.py` 和 `plugins/codex-island/hooks/event.py`。

退出菜单会结束悬浮窗；下次登录仍由登录服务启动。异常退出时登录服务会自动恢复。运行 `python3 uninstall.py` 可移除插件和登录服务，保留应用和本地记录。

## 数据范围与兼容性

只监控当前用户、本机 Codex 的任务。远程主机、云端任务或其他用户的数据不会自动出现。账户用量显示最近一条 Codex 用量报告，不进行持续网络查询；上游没有返回新报告时会显示它已过去多少秒。

本机任务数据库和 rollout 格式不是稳定的公共接口，当前实现已针对本机 `state_5.sqlite`、`thread_history_1.sqlite` 验证。若 Codex 版本改变该结构，组件会显示未同步或等待插件事件，不伪造数据。最近 100 项任务参与本地扫描；长时间无新事件的未结束任务标记为状态待确认。

## 验证

`python3 -m unittest discover -s tests -v` 验证状态结束、用量、并发 hooks、断连、过期状态和不会输出原始推理/工具参数。应用的 `--test-list` 模式验证 40 个同名任务、列表滚动、滚动锚点、点击路由到正确 ID、URL 编码、重排序、列表减少、空列表和列表增长，需要正常的 macOS 图形会话。2.1 使用独立卡片替代下拉框。

`--render <snapshot.json> <preview.png>` 从实际数据快照生成可检查的离屏预览。运行版每 10 秒写入本机 `health.json`，供核对运行版本、窗口状态和最近同步时间。

官方接入说明：[插件打包](https://developers.openai.com/plugins/build/plugins)、[hooks 和信任要求](https://learn.chatgpt.com/docs/hooks)。

### Todo CLI (2.6)

展开灵动岛后点击“待办”，勾选完成或取消完成。已完成事项保留。Agent 可通过插件技能调用 `scripts/todo.py`；仓库使用示例：

```sh
/usr/bin/python3 plugins/codex-island/scripts/todo.py add "整理项目文档"
/usr/bin/python3 plugins/codex-island/scripts/todo.py list --all
/usr/bin/python3 plugins/codex-island/scripts/todo.py done <id>
```

支持 `reopen`、`remove`，所有命令输出 JSON。数据存储在用户 Application Support 的 `todos.json`，并发锁和原子写入保护数据；升级保留待办。

## 会话角色与主题 (2.8)

12 种像素角色：吃豆人、水管工、蘑菇头、星星、幽灵、猫咪、兔子、史莱姆、火箭、机器人、外星人、企鹅。提供红橙黄绿青蓝紫七色主题。每个主会话按 ID 固定分配角色和颜色，不同会话可能共享同一组合。

主界面跟随最近开始一轮工作的运行会话。明确的 `final` 通知锁定对应角色，直到从卡片或通知成功请求打开会话；多个未查看整体结果按最新优先显示。任务卡片和通知使用各自会话配色。查看判断以灵动岛内点击为准。

## 构建安装包

```sh
/usr/bin/python3 packaging/build-installer.py
```

在 `build/release/` 生成当前版本的 `.pkg` 和 Agent 交接 ZIP。当前安装包采用临时签名，未进行 Developer ID 签名或公证。

## 开源许可

本项目按 [MIT License](LICENSE) 发布，是独立社区项目，与 OpenAI、任天堂及其他游戏品牌无隶属关系。像素图案由代码绘制，未打包官方游戏素材；品牌名称及相关权利属于各自权利人。
