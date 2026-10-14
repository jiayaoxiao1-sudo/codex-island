---
name: use-codex-island
description: Install, use, verify or troubleshoot the Codex Island pixel floating window for macOS, including todos, CLI todo management, local task status, unread results, notifications and startup. Use for this specific companion app, not generic Codex troubleshooting.
---

# Codex Island

Codex Island is a native macOS companion app. It reads the current user's local Codex task records and shows one card per user chat, live usage reports, public progress headings and unread round outputs. It filters internal Guardian review sessions. It never starts or submits Codex tasks itself.

## Locate and verify

- App: `~/Library/Application Support/Codex Island/Codex Island.app`.
- Agent helper: resolve `../../scripts/islandctl.py` relative to this skill folder. Run `/usr/bin/python3 <helper> status` for version, liveness, last update, card counts and prerequisite availability. Do not read `auth.json` or upload local records.
- Login service: `local.codex.island.watcher`, in the current user's GUI launchd domain.
- Full installer resources: `/Library/Application Support/Codex Island Installer`. Read its `AGENT-START.md` when installation or repair is needed.

## Operate

For explicitly tracked multi-step work, `../../scripts/notify.py notify --kind step --chat-id <root-id> --title <chat-title> --text <public-step-result>` sends a step sound and result. Use `--kind final` only once the user's overall requested work is complete. It selects the final fanfare and suppresses a duplicate automatic step notification for the same current turn. Do not infer overall completion merely from a tool call or an ordinary round ending. `notify.py demo` runs a labeled three-step example: two step sounds, then one final sound; no real Codex tasks are created.

When the user asks to show or restart the companion, use the helper's `show` or `restart` command. When asked to open a task, prefer Codex's native navigation tool when available. Otherwise use the helper's `open <user-chat-id>` command. Pass the user's root chat ID; never navigate to Guardian review or internal subagent IDs. A task completion is a round ending, not proof that a long-running goal is complete.

Clicking outside collapses the expanded panel. Cards group parent and child agents by root chat. Unread rounds persist locally until a card or result notification is clicked and navigation is accepted. Opening a grouped card acknowledges its unread rounds; clicking a notification acknowledges that notification's round. The menu bar has the sound toggle and quit action.

## Install or repair

Use the supplied `.pkg` on macOS 13+; its universal binary supports Apple Silicon and Intel. The current Python monitor requires Apple Command Line Tools' `/usr/bin/python3`. If missing, explain the prerequisite and follow the user's authorization for installing it. If Codex is missing, install Codex before completing companion setup.

If files are present but user setup was deferred, run `/usr/bin/python3 "/Library/Application Support/Codex Island Installer/install.py" --prebuilt` as the intended non-root user. Never configure the root account or overwrite another user's setup. Plugin hooks need Codex's normal trust review; do not bypass it. The status helper is read-only; show/restart/open are actions to use within the user's requested scope.

For stale data, inspect the helper report and the app's `health.json` before claiming it is running. Quotas are the latest upstream report, not a live estimate. Local SQLite schemas may change; a missing report should be shown as unavailable. Preserve `pending-completions.json` and read receipts when repairing or upgrading. Use the packaged `uninstall.py` to remove startup/plugin integration; it preserves the user's unread results.

## Todo list

When the user asks to add/list/complete/reopen/remove a personal todo, resolve `../../scripts/todo.py` relative to this skill folder and invoke it with `/usr/bin/python3`. Examples:

```sh
/usr/bin/python3 <todo-helper> add "明天整理项目文档" --note "检查 README 和安装说明"
/usr/bin/python3 <todo-helper> list
/usr/bin/python3 <todo-helper> list --all
/usr/bin/python3 <todo-helper> done <exact-id>
/usr/bin/python3 <todo-helper> reopen <exact-id>
/usr/bin/python3 <todo-helper> remove <exact-id>
```

Output is JSON. Resolve exact IDs with `list --all` before editing existing items; if the user's description matches multiple todos, ask which item. Quote arguments safely; never execute todo text as shell code. The companion's 待办 tab shows all items and supports checking/unchecking. Completed todos remain until explicitly removed. Store is `~/Library/Application Support/Codex Island/todos.json`; preserve it during upgrades. Todo text is not a reminder schedule or permission to perform the described work. Do not automatically add every conversation task as a personal todo.

## Session characters

Each root chat has a stable pixel character and color. The main island follows the running chat with the latest turn start; tool activity does not change selection. An explicit `notify.py notify --kind final` locks that chat's character/theme until its card or result notification successfully opens the chat. Step notifications do not lock the main display. Multiple final results are retained, with the newest displayed first; older unviewed finals remain eligible. Final display state survives app restart in `final-display.json`. Preserve it on upgrade along with todos and unread results. Cards and notifications always use their own root chat color.
