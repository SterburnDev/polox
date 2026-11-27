"""Checks what is inside exported Polox builds, per release flavour (docs/RELEASES.md).

    python tools/release/verify_pack.py --flavor public  --windows build/public/windows/Polox.exe
    python tools/release/verify_pack.py --flavor private --windows build/windows/Polox.exe \
                                        --web build/web/index.pck --apk build/android/polox.apk
    add --list FILE to write every packed path (one per line, per artifact) for the asset audit

It reads the Godot pack directory straight from the artifact (the .exe's embedded pack, the web
index.pck, the APK's assets/), so it checks what really ships, not what the presets intend.

Every flavour   nothing from PersonalData/, .polox-local/, local-addons/, tests/, tools/, build/,
                docs/ or the old assets/music/ folder; Polox Originals and the eight public
                Music-secret pictures are there; the build id matches build_id.txt when it is packed.
public          nothing at all from assets/local/ (the private content pack), by path or by the
                imported copy Godot makes of each private file.
private         from assets/local/ exactly what its manifests list (songs, cue music, textures,
                secret_images) and nothing else that happens to sit in that folder.

Run it from anywhere: paths are resolved from the project root this file lives in, unless --root
names another checkout (the public source snapshot). Exit code 0 when every artifact passes.
"""

import argparse
import json
import mmap
import re
import struct
import sys
import zipfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
PACK_MAGIC = b"GDPC"
# Pack directory entry, after the path: offset (8), size (8), MD5 (16), flags (4).
ENTRY_TAIL_BYTES = 36

NEVER_PACKED = ("PersonalData/", "PersonalData.migrating/", ".polox-local/", "local-addons/", "tests/",
                "tools/", "build/", "docs/", "assets/music/")
PRIVATE_PACK = "assets/local"
PRIVATE_MANIFESTS = (f"{PRIVATE_PACK}/addon.json", f"{PRIVATE_PACK}/addons/utdr-theme/addon.json")
ALWAYS_PACKED = ("bundled-addons/polox-originals/addon.json",)
PUBLIC_SECRET_PICTURES = tuple(f"assets/secret/yam_{n:02d}_{name}.svg" for n, name in enumerate(
    ("hello", "family", "afloat", "moonlight", "tower", "peek", "seaside", "garden"), start=1))


class Failure(Exception):
    """One artifact broke a rule; the message says which."""


# --- Reading packs -----------------------------------------------------------------------------------

def pack_index(data, start):
    """{path: (offset, size)} for the pack that begins at `start` in `data`."""
    if data[start:start + 4] != PACK_MAGIC:
        raise Failure("no Godot pack found where one was expected")
    file_base, directory_offset = struct.unpack_from("<QQ", data, start + 24)
    cursor = start + directory_offset
    (count,) = struct.unpack_from("<I", data, cursor)
    cursor += 4
    index = {}
    for _ in range(count):
        (path_bytes,) = struct.unpack_from("<I", data, cursor)
        cursor += 4
        path = data[cursor:cursor + path_bytes].rstrip(b"\x00").decode("utf-8")
        cursor += path_bytes
        offset, size = struct.unpack_from("<QQ", data, cursor)
        cursor += ENTRY_TAIL_BYTES
        index[path] = (start + file_base + offset, size)
    if len(index) != count:
        raise Failure("the pack lists the same path twice")
    return index


def embedded_pack_start(data):
    """Where the pack starts inside an exported .exe (Godot appends: pack, its size, the magic)."""
    if data[-4:] != PACK_MAGIC:
        raise Failure("this .exe has no embedded pack (was it exported with embed_pck?)")
    (pack_bytes,) = struct.unpack_from("<Q", data, len(data) - 12)
    return len(data) - 12 - pack_bytes


class PackedFiles:
    """The paths in one artifact and a way to read one of them."""

    def __init__(self, label, paths, read):
        self.label = label
        self.paths = set(paths)
        self.read = read


def open_pack_file(label, path, embedded):
    handle = path.open("rb")
    data = mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ)
    index = pack_index(data, embedded_pack_start(data) if embedded else 0)
    return PackedFiles(label, index, lambda name: bytes(data[index[name][0]:index[name][0] + index[name][1]]))


def open_apk(label, path):
    archive = zipfile.ZipFile(path)
    names = {n[len("assets/"):] for n in archive.namelist() if n.startswith("assets/") and not n.endswith("/")}
    return PackedFiles(label, names, lambda name: archive.read("assets/" + name))


# --- What the source tree says should (not) be there --------------------------------------------------

def imported_copies(import_file):
    """The res:// paths Godot wrote for one source file (.godot/imported/..., or several per format)."""
    text = import_file.read_text(encoding="utf-8")
    return set(re.findall(r'^path(?:\.[\w]+)?="res://([^"]+)"$', text, re.M))


def packed_names_for(root, source):
    """Everything a pack holds for one imported source file: its .import and the imported copies."""
    import_file = root / (source + ".import")
    if not import_file.is_file():
        raise Failure(f"{source} has no .import file: run the editor's import first")
    return {source + ".import"} | imported_copies(import_file)


def private_media(root):
    """The files the private pack's manifests list, as project-relative paths (empty without a pack)."""
    listed = set()
    for manifest_name in PRIVATE_MANIFESTS:
        manifest_path = root / manifest_name
        if not manifest_path.is_file():
            continue
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        overrides = manifest.get("overrides", {})
        relatives = {song["file"] for song in overrides.get("songs", [])}
        for kind in ("music", "textures", "sfx", "tiles"):
            relatives.update(v for v in overrides.get(kind, {}).values() if not str(v).startswith("@"))
        relatives.update(manifest.get("secret_images", []))
        for relative in relatives:
            parts = Path(relative).parts
            if Path(relative).is_absolute() or ".." in parts:
                raise Failure(f"{manifest_name} lists a path outside its folder: {relative}")
            listed.add(f"{Path(manifest_name).parent.as_posix()}/{Path(relative).as_posix()}")
    return listed


def every_private_import(root):
    """Imported copies of everything under assets/local, listed or not."""
    copies = set()
    pack_dir = root / PRIVATE_PACK
    if pack_dir.is_dir():
        for import_file in pack_dir.rglob("*.import"):
            copies |= imported_copies(import_file)
    return copies


# --- The rules ---------------------------------------------------------------------------------------

def check(packed, flavor, root, build_id):
    problems = []
    paths = packed.paths

    stray = sorted(p for p in paths if p.startswith(NEVER_PACKED))
    if stray:
        problems.append(f"{len(stray)} path(s) that must never ship, e.g. {stray[0]}")

    required = set(ALWAYS_PACKED)
    for picture in PUBLIC_SECRET_PICTURES:
        required |= packed_names_for(root, picture)
    missing = sorted(required - paths)
    if missing:
        problems.append(f"{len(missing)} expected path(s) missing, e.g. {missing[0]}")

    in_private_pack = {p for p in paths if p.startswith(PRIVATE_PACK + "/")}
    public_addon = (root / PRIVATE_PACK / "addon.json").is_file()
    if flavor == "public" and not public_addon:
        if in_private_pack:
            problems.append(f"{len(in_private_pack)} path(s) from the private pack, e.g. {sorted(in_private_pack)[0]}")
        leaked = every_private_import(root) & paths
        if leaked:
            problems.append(f"{len(leaked)} imported cop(ies) of private files, e.g. {sorted(leaked)[0]}")
    else:
        if flavor == "public":
            for forbidden in (f"{PRIVATE_PACK}/secret/", f"{PRIVATE_PACK}/addons/"):
                bad = sorted(p for p in in_private_pack if p.startswith(forbidden))
                if bad:
                    problems.append(f"{len(bad)} private path(s) in public build, e.g. {bad[0]}")
        media = private_media(root)
        if not media:
            problems.append(f"a {flavor} build needs assets/local/ and its addon.json in the source tree")
        allowed = {m for m in PRIVATE_MANIFESTS if (root / m).is_file()}
        if flavor == "public":
            allowed = {f"{PRIVATE_PACK}/addon.json"}
        allowed_copies = set()
        for source in media:
            names = packed_names_for(root, source)
            allowed |= {n for n in names if n.startswith(PRIVATE_PACK + "/")}
            allowed_copies |= {n for n in names if not n.startswith(PRIVATE_PACK + "/")}
        if in_private_pack != allowed:
            extra, lacking = sorted(in_private_pack - allowed), sorted(allowed - in_private_pack)
            problems.append("the built-in pack's contents differ from its manifests: %d extra%s, %d missing%s" % (
                len(extra), f" (e.g. {extra[0]})" if extra else "", len(lacking), f" (e.g. {lacking[0]})" if lacking else ""))
        unlisted = (every_private_import(root) - allowed_copies) & paths
        if unlisted:
            problems.append(f"{len(unlisted)} imported cop(ies) of unlisted private files, e.g. {sorted(unlisted)[0]}")
        missing_copies = sorted(allowed_copies - paths)
        if missing_copies:
            problems.append(f"{len(missing_copies)} listed built-in file(s) not in the pack, e.g. {missing_copies[0]}")

    if build_id and "build_id.txt" in paths:
        packed_id = packed.read("build_id.txt").decode("utf-8").strip()
        if packed_id != build_id:
            problems.append(f"build id {packed_id} is packed, but build_id.txt says {build_id}")

    if problems:
        raise Failure(f"{packed.label}: " + "; ".join(problems))
    private_count = len(in_private_pack)
    print(f"{packed.label}: OK ({flavor}). {len(paths)} packed paths, {private_count} from the private pack, "
          f"8 public secret pictures, Polox Originals present, no test, tool or personal paths.")


def main():
    parser = argparse.ArgumentParser(description="Check what is inside exported Polox builds.")
    parser.add_argument("--flavor", choices=("public", "private"), required=True)
    parser.add_argument("--root", default=str(PROJECT_ROOT), help="the source tree the build was exported from")
    parser.add_argument("--windows", help="an exported Polox.exe (pack embedded)")
    parser.add_argument("--web", help="an exported index.pck")
    parser.add_argument("--apk", help="an exported .apk")
    parser.add_argument("--list", help="write every packed path here (for the asset audit)")
    args = parser.parse_args()
    root = Path(args.root).resolve()
    build_id_file = root / "build_id.txt"
    build_id = build_id_file.read_text(encoding="utf-8-sig").strip() if build_id_file.is_file() else ""

    artifacts = []
    try:
        if args.windows:
            artifacts.append(open_pack_file("Windows", Path(args.windows), embedded=True))
        if args.web:
            artifacts.append(open_pack_file("Web", Path(args.web), embedded=False))
        if args.apk:
            artifacts.append(open_apk("Android", Path(args.apk)))
        if not artifacts:
            parser.error("name at least one artifact: --windows, --web or --apk")
        failed = False
        for packed in artifacts:
            try:
                check(packed, args.flavor, root, build_id)
            except Failure as failure:
                failed = True
                print(f"FAILED  {failure}")
    except (Failure, OSError, zipfile.BadZipFile, struct.error) as error:
        print(f"FAILED  {error}")
        sys.exit(1)

    if args.list:
        with open(args.list, "w", encoding="utf-8", newline="\n") as out:
            for packed in artifacts:
                out.write(f"# {packed.label} ({args.flavor}): {len(packed.paths)} paths\n")
                out.writelines(path + "\n" for path in sorted(packed.paths))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
