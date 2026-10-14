#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p "build/Codex Island.app/Contents/MacOS" "build/Codex Island.app/Contents/Resources"
xcrun clang Sources/main.m -arch arm64 -arch x86_64 -fobjc-arc -fblocks -mmacosx-version-min=13.0 -o "build/Codex Island.app/Contents/MacOS/CodexIsland" -framework Cocoa -framework UniformTypeIdentifiers
cat > "build/Codex Island.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexIsland</string>
<key>CFBundleIdentifier</key><string>local.codex.island</string>
<key>CFBundleName</key><string>Codex Island</string>
<key>CFBundleVersion</key><string>12</string>
<key>CFBundleShortVersionString</key><string>2.8</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
cp plugins/codex-island/scripts/todo.py "build/Codex Island.app/Contents/Resources/todo.py"
cp bridge/monitor.py "build/Codex Island.app/Contents/Resources/monitor.py"
cp assets/complete.wav "build/Codex Island.app/Contents/Resources/complete.wav"
cp assets/step.wav "build/Codex Island.app/Contents/Resources/step.wav"
codesign --force --sign - "build/Codex Island.app"
echo "已生成：$PWD/build/Codex Island.app"
