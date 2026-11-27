"""Exports Polox for Windows into a folder of your choice and checks what went into it.

    python tools/release/build_windows.py --flavor private --out build/release/private/windows
    python tools/release/build_windows.py --flavor public  --out build/release/public/windows --root ../polox-public

--flavor   private: this checkout, with assets/local/ (your soundtrack, Soul and pictures).
           public:  a tree without assets/local/ (the public source snapshot made by
                    tools/release/make_public_source.py). The export is refused if the tree has one.
--out      where Polox.exe goes (made if needed; relative paths start at the project root).
--root     the source tree to export (default: this checkout).
--phone    copy the phone version (build/web) and Polox for Android (build/android/polox.apk) beside
           Polox.exe when they exist, as tools/export_windows.bat does. Off by default.

The export uses this checkout's Godot editor binary and Polox's own engine template
(tools/engine/windows, built by tools/build_engine.py). When --root is another tree, its tools/engine
and tools/godot/templates folders are linked to this checkout's (directory junctions: no copy, no admin).
The result is checked by tools/release/verify_pack.py; a failed check fails the build.
"""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
GODOT = PROJECT_ROOT / "tools" / "godot" / "Godot_v4.7.2-stable_win64_console.exe"
ENGINE_TEMPLATE = Path("tools") / "engine" / "windows" / "windows_release_x86_64.exe"
# Folders the export presets expect inside the tree being exported, shared from this checkout.
SHARED_TOOL_FOLDERS = (Path("tools") / "engine", Path("tools") / "godot" / "templates")
EXPORT_TIMEOUT_S = 1800


def run_godot(root, arguments, log_path):
    """Runs the editor binary headless on `root`; the whole output goes to `log_path`."""
    command = [str(GODOT), "--headless", "--path", str(root)] + arguments
    with open(log_path, "w", encoding="utf-8", errors="replace") as log:
        return subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=EXPORT_TIMEOUT_S).returncode


def link_shared_tools(root):
    """Gives another source tree this checkout's engine templates (junctions, removed by rmdir)."""
    for folder in SHARED_TOOL_FOLDERS:
        target, link = PROJECT_ROOT / folder, root / folder
        if link.exists() or not target.is_dir():
            continue
        link.parent.mkdir(parents=True, exist_ok=True)
        made = subprocess.run(["cmd", "/c", "mklink", "/J", str(link), str(target)], capture_output=True, text=True)
        if made.returncode != 0:
            sys.exit(f"Could not link {link} to {target}: {made.stderr.strip() or made.stdout.strip()}")


def main():
    parser = argparse.ArgumentParser(description="Export Polox for Windows and check the result.")
    parser.add_argument("--flavor", choices=("public", "private"), required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--root", default=str(PROJECT_ROOT))
    parser.add_argument("--phone", action="store_true")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    out = Path(args.out)
    out = (out if out.is_absolute() else PROJECT_ROOT / out).resolve()
    private_pack = root / "assets" / "local"
    if args.flavor == "public" and ((private_pack / "secret").exists() or (private_pack / "addons").exists()):
        sys.exit(f"{root} has assets/local/secret/ or assets/local/addons/: a public build must not include private secret vault images or add-ons.")
    if args.flavor == "private" and not (private_pack / "addon.json").is_file():
        sys.exit(f"{root} has no assets/local/addon.json: there is nothing private to build.")
    if not GODOT.is_file():
        sys.exit("Godot 4.7.2 was not found: run tools\\get_godot.bat first.")
    if root != PROJECT_ROOT:
        link_shared_tools(root)
    if not (root / ENGINE_TEMPLATE).is_file():
        sys.exit("Polox's Windows engine is missing: run tools\\pyenv\\Scripts\\python tools\\build_engine.py windows first.")

    out.mkdir(parents=True, exist_ok=True)
    logs = out.parent / (out.name + "-logs")
    logs.mkdir(parents=True, exist_ok=True)
    # Godot must not import build output as game assets.
    for build_folder in {root / "build", PROJECT_ROOT / "build"}:
        build_folder.mkdir(exist_ok=True)
        (build_folder / ".gdignore").touch()

    print(f"Importing {root} ...", flush=True)
    # The very first import of a fresh tree can end with an error code after doing all its work
    # (classes registered late); a second pass then has nothing left to do and says so.
    if run_godot(root, ["--import"], logs / "import.log") != 0:
        print("The first import pass ended with an error code; running it once more ...", flush=True)
        if run_godot(root, ["--import"], logs / "import-second-pass.log") != 0:
            sys.exit(f"Import failed twice: see {logs / 'import.log'} and {logs / 'import-second-pass.log'}")

    # The exe carries this source's build id, so it and its phone version agree.
    build_id_file = root / "build_id.txt"
    build_id_file.unlink(missing_ok=True)
    scratch_save = logs / "export_save"
    run_godot(root, ["--", f"--save-root={scratch_save}", "--write-build-id"], logs / "build-id.log")
    if not build_id_file.is_file():
        sys.exit(f"Could not write the build id: see {logs / 'build-id.log'}")
    build_id = build_id_file.read_text(encoding="utf-8-sig").strip()

    exe = out / "Polox.exe"
    exe.unlink(missing_ok=True)
    print(f"Exporting Windows ({args.flavor}, build {build_id}) ...", flush=True)
    code = run_godot(root, ["--export-release", "Windows", str(exe)], logs / "export.log")
    if code != 0 or not exe.is_file():
        sys.exit(f"Export failed (exit {code}): see {logs / 'export.log'}")

    if args.phone:
        web, apk = PROJECT_ROOT / "build" / "web", PROJECT_ROOT / "build" / "android" / "polox.apk"
        if (web / "index.html").is_file():
            shutil.copytree(web, out / "web", dirs_exist_ok=True)
            print("  + the phone version (web/)")
        if apk.is_file():
            shutil.copy2(apk, out / "polox.apk")
            if apk.with_suffix(".json").is_file():
                shutil.copy2(apk.with_suffix(".json"), out / "polox.json")
            print("  + Polox for Android (polox.apk)")

    verify = [sys.executable, str(PROJECT_ROOT / "tools" / "release" / "verify_pack.py"), "--flavor", args.flavor,
              "--root", str(root), "--windows", str(exe), "--list", str(logs / "packed-paths.txt")]
    if subprocess.run(verify).returncode != 0:
        sys.exit("The exported build failed its content check; do not ship it.")
    print(f"Done: {exe} ({exe.stat().st_size / 1048576:.1f} MB)")


if __name__ == "__main__":
    main()
