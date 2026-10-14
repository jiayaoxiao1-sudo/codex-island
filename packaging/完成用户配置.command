#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
if [[ $(id -u) == 0 ]]; then
  echo "请以要使用悬浮窗的普通桌面用户运行此程序。"
  exit 1
fi
/usr/bin/python3 install.py --prebuilt
echo "用户配置完成。首次 hooks 信任请在 Codex 中审阅。"
read -k 1 '?按任意键关闭。'
