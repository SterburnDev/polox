"""Builds the git-ignored local override pack under assets/local/.

Use this helper on your own machine to install local soundtrack overrides, a custom Soul image,
and built-in secret vault pictures without committing copyrighted or personal files to GitHub.

Example:
    python tools/setup_local_pack.py \\
        --survey  "/path/to/light_world_creation.mp3" \\
        --menu    "/path/to/title_menu.mp3" \\
        --dark    "/path/to/dream_world.mp3" \\
        --battle  "/path/to/battle.mp3" \\
        --light   "/path/to/light_world.mp3" \\
        --soul    "/path/to/soul.png" \\
        --secret-dir "/path/to/secret_images"
"""

import argparse
import json
import shutil
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
LOCAL_ROOT = PROJECT_ROOT / "assets" / "local"
AUDIO_EXTS = {".mp3", ".ogg", ".wav"}
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".svg"}
CUES = ("survey", "menu", "dark", "battle", "light")


def copy_asset(source: str, target_dir: Path, allowed_exts: set, rename_to: str = "") -> str:
    src = Path(source).expanduser().resolve()
    if not src.is_file():
        sys.exit(f"File not found: {src}")
    if src.suffix.lower() not in allowed_exts:
        sys.exit(f"Unsupported file type for {src.name} (expected: {', '.join(sorted(allowed_exts))})")
    target_dir.mkdir(parents=True, exist_ok=True)
    dest_name = rename_to if rename_to else src.name
    shutil.copy2(src, target_dir / dest_name)
    return dest_name


def main() -> None:
    parser = argparse.ArgumentParser(description="Install git-ignored local overrides into assets/local/.")
    parser.add_argument("--survey", default="", help="Light World creation soundtrack file")
    parser.add_argument("--menu", default="", help="Title menu soundtrack file")
    parser.add_argument("--dark", default="", help="Dream World soundtrack file")
    parser.add_argument("--battle", default="", help="Battle soundtrack file")
    parser.add_argument("--light", default="", help="Light World soundtrack file")
    parser.add_argument("--soul", default="", help="Custom Soul image (e.g. PNG)")
    parser.add_argument("--secret-dir", default="", help="Folder of built-in secret vault images")
    args = parser.parse_args()

    music_overrides = {}
    songs = []
    music_dir = LOCAL_ROOT / "music"
    for cue in CUES:
        given = getattr(args, cue)
        if not given:
            continue
        copied = copy_asset(given, music_dir, AUDIO_EXTS)
        rel = f"music/{copied}"
        music_overrides[cue] = rel
        songs.append({"file": rel, "title": Path(copied).stem, "from": "Local Soundtrack", "gain_db": 0.0})

    textures = {}
    if args.soul:
        ext = Path(args.soul).suffix.lower()
        copied = copy_asset(args.soul, LOCAL_ROOT / "pictures", IMAGE_EXTS, rename_to=f"soul{ext}")
        textures["soul"] = f"pictures/{copied}"

    secret_images = []
    if args.secret_dir:
        src_dir = Path(args.secret_dir).expanduser().resolve()
        if not src_dir.is_dir():
            sys.exit(f"Secret image directory not found: {src_dir}")
        for entry in sorted(src_dir.iterdir()):
            if entry.is_file() and entry.suffix.lower() in IMAGE_EXTS:
                copied = copy_asset(str(entry), LOCAL_ROOT / "secret", IMAGE_EXTS)
                secret_images.append(f"secret/{copied}")

    if not music_overrides and not textures and not secret_images:
        parser.print_help()
        sys.exit(1)

    LOCAL_ROOT.mkdir(parents=True, exist_ok=True)
    manifest = {
        "format": 1,
        "id": "built-in",
        "name": "Local Soundtrack & Pack",
        "version": "1.0.0",
        "description": "Local built-in overrides (git-ignored). Polox Originals restores Polox's built-in tunes and Dream Drop.",
        "overrides": {
            "music": music_overrides,
            "songs": songs,
            "textures": textures,
        },
        "secret_images": secret_images,
    }
    manifest_path = LOCAL_ROOT / "addon.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {manifest_path} ({len(music_overrides)} cues, {len(textures)} textures, {len(secret_images)} secret images).")


if __name__ == "__main__":
    main()
