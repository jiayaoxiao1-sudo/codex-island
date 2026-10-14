#!/usr/bin/env python3
"""Build a standard unsigned macOS installer and agent handoff bundle."""
from pathlib import Path
import json
import shutil
import subprocess
import plistlib

ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / "build/installer-stage"
DIST = ROOT / "build/release"

def main():
    subprocess.run(["/bin/zsh", str(ROOT / "build.sh")], check=True)
    with (ROOT / "build/Codex Island.app/Contents/Info.plist").open("rb") as handle:
        version = plistlib.load(handle)["CFBundleShortVersionString"]
    if STAGE.exists():
        shutil.rmtree(STAGE)
    DIST.mkdir(parents=True, exist_ok=True)
    payload = STAGE / "payload"
    helper = payload / "Library/Application Support/Codex Island Installer"
    helper.mkdir(parents=True)
    ignore = shutil.ignore_patterns("__pycache__", "*.pyc")
    for folder in ["plugins", "distribution", "Sources", "bridge", "assets", "tests"]:
        shutil.copytree(ROOT / folder, helper / folder, ignore=ignore)
    for name in ["install.py", "uninstall.py", "README.md", "AGENT-START.md", "LICENSE", "build.sh"]:
        shutil.copy2(ROOT / name, helper / name)
    shutil.copy2(ROOT / "packaging/完成用户配置.command", helper / "完成用户配置.command")
    (helper / "完成用户配置.command").chmod(0o755)
    shutil.copytree(ROOT / "build/Codex Island.app", helper / "build/Codex Island.app")
    # Expose the app in Applications; per-user setup installs its own running copy.
    shutil.copytree(ROOT / "build/Codex Island.app", payload / "Applications/Codex Island.app")
    scripts = STAGE / "scripts"
    shutil.copytree(ROOT / "packaging/scripts", scripts)
    for path in scripts.iterdir():
        path.chmod(0o755)
    component = DIST / "Codex-Island-component.pkg"
    components = STAGE / "components.plist"
    subprocess.run(["/usr/bin/pkgbuild", "--analyze", "--root", str(payload), str(components)], check=True)
    with components.open("rb") as handle:
        bundles = plistlib.load(handle)
    for bundle in bundles:
        bundle["BundleIsRelocatable"] = False
    with components.open("wb") as handle:
        plistlib.dump(bundles, handle)
    subprocess.run(["/usr/bin/pkgbuild", "--root", str(payload), "--component-plist", str(components), "--scripts", str(scripts), "--ownership", "recommended", "--identifier", "local.codex.island.installer", "--version", version, "--install-location", "/", str(component)], check=True)
    package = DIST / f"Codex-Island-{version}.pkg"
    distribution = STAGE / "distribution.xml"
    distribution.write_text((ROOT / "packaging/distribution.xml").read_text().replace("2.4", version))
    subprocess.run(["/usr/bin/productbuild", "--distribution", str(distribution), "--resources", str(ROOT / "packaging/resources"), "--package-path", str(DIST), str(package)], check=True)
    handoff = STAGE / "Codex-Island-Agent-Pack"
    shutil.copytree(helper, handoff)
    shutil.copy2(package, handoff / package.name)
    (handoff / "AGENTS.md").write_text("# Codex Island handoff\n\nRead AGENT-START.md before installing, operating or repairing this companion. It describes dependencies, user setup, verification and the bundled skill. Preserve local unread records.\n")
    archive = DIST / f"Codex-Island-{version}-Agent-Pack.zip"
    subprocess.run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(handoff), str(archive)], check=True)
    print(json.dumps({"installer": str(package), "agentPack": str(archive)}, ensure_ascii=False))

if __name__ == "__main__":
    main()
