"""Builds the Windows setup program (Polox-<version>-Setup.exe) and the portable zip from an
exported build, and writes their SHA-256 checksums.

    python tools/release/build_installer.py --source build/release/private/windows --out build/release/private
    python tools/release/build_installer.py --source build/release/public/windows  --out build/release/public --root ../polox-public

--source   an exported build folder (tools/release/build_windows.py --out): Polox.exe, and when
           present web\\, polox.apk and polox.json.
--out      where the setup program, the portable zip and the checksum file go.
--root     the source tree the build came from (default: this checkout): the version comes from its
           project.godot and the notices from its LICENSE and THIRD_PARTY_NOTICES.md.
--label    a word added to the file names, e.g. "Private" -> Polox-1.29.0-Private-Setup.exe.
--iscc     the Inno Setup compiler (default: tools/innosetup/ISCC.exe in this checkout, then the
           usual install folders).
--sign     a signtool command line with "$f" for the file, to sign the setup program
           (Inno Setup's SignTool). Without it the setup is unsigned, and this script says so.

Nothing here downloads anything. Inno Setup comes from https://jrsoftware.org/isdl.php; see
docs/BUILDING.md for the portable install into tools/innosetup/.
"""

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
GODOT = PROJECT_ROOT / "tools" / "godot" / "Godot_v4.7.2-stable_win64_console.exe"
SCRIPT = PROJECT_ROOT / "tools" / "release" / "installer" / "polox.iss"
NOTICE_FILES = ("LICENSE", "THIRD_PARTY_NOTICES.md")
ISCC_CANDIDATES = (
    PROJECT_ROOT / "tools" / "innosetup" / "ISCC.exe",
    Path(r"C:\Program Files\Inno Setup 7\ISCC.exe"),
    Path(r"C:\Program Files (x86)\Inno Setup 7\ISCC.exe"),
    Path(r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe"),
)


def game_version(root):
    text = (root / "project.godot").read_text(encoding="utf-8")
    found = re.search(r'^config/version="([^"]+)"', text, re.M)
    if not found:
        sys.exit(f"No config/version in {root / 'project.godot'}")
    return found.group(1)


def sha256_of(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def find_iscc(given):
    candidates = (Path(given),) if given else ISCC_CANDIDATES
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    sys.exit("The Inno Setup compiler (ISCC.exe) was not found. Install Inno Setup 7 (docs/BUILDING.md) "
             "or pass --iscc PATH.")


def collect_notices(root, work):
    """LICENSE, THIRD_PARTY_NOTICES.md and the engine's own notices, in one folder for the setup."""
    notices = work / "notices"
    shutil.rmtree(notices, ignore_errors=True)
    notices.mkdir(parents=True)
    for name in NOTICE_FILES:
        if (root / name).is_file():
            shutil.copy2(root / name, notices / name)
    # The engine reports its own licence texts; ask it on an empty project (never Polox's autoloads).
    scratch_project = work / "empty-project"
    scratch_project.mkdir(exist_ok=True)
    (scratch_project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="notices"\n', encoding="utf-8")
    engine_notices = notices / "GODOT_ENGINE_NOTICES.txt"
    writer = PROJECT_ROOT / "tools" / "release" / "write_engine_notices.gd"
    made = subprocess.run([str(GODOT), "--headless", "--path", str(scratch_project), "--script", str(writer),
                           "--", f"--out={engine_notices}"], capture_output=True, text=True, timeout=300)
    if made.returncode != 0 or not engine_notices.is_file():
        sys.exit("Could not write the engine's notices:\n" + made.stdout + made.stderr)
    return notices


def make_portable_zip(source, zip_path, folder_name, notices):
    """The portable copy: the exported folder as it is, plus the notices. No marker file, so it keeps
    PersonalData beside Polox.exe (scripts/core/personal_data.gd)."""
    members = {}
    for path in sorted(source.rglob("*")):
        if path.is_file() and "PersonalData" not in path.relative_to(source).parts:
            members[f"{folder_name}/{path.relative_to(source).as_posix()}"] = path
    for path in sorted(notices.iterdir()):
        members[f"{folder_name}/licenses/{path.name}"] = path
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name, path in members.items():
            archive.write(path, name)
    with zipfile.ZipFile(zip_path) as archive:
        if archive.testzip() is not None or set(archive.namelist()) != set(members):
            sys.exit(f"{zip_path} did not verify after writing")
    return len(members)


def signature_status(path):
    """'signed by <subject>' or 'unsigned', as Windows itself reports it."""
    query = ("$s = Get-AuthenticodeSignature -LiteralPath '%s'; "
             "if ($s.SignerCertificate) { 'signed by ' + $s.SignerCertificate.Subject + ' (' + $s.Status + ')' } "
             "else { 'unsigned' }") % str(path).replace("'", "''")
    result = subprocess.run(["powershell", "-NoProfile", "-Command", query], capture_output=True, text=True)
    return result.stdout.strip() or "unknown (could not ask Windows)"


def main():
    parser = argparse.ArgumentParser(description="Build the Windows setup program and the portable zip.")
    parser.add_argument("--source", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--root", default=str(PROJECT_ROOT))
    parser.add_argument("--label", default="")
    parser.add_argument("--iscc", default="")
    parser.add_argument("--sign", default="")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    source = Path(args.source)
    source = (source if source.is_absolute() else PROJECT_ROOT / source).resolve()
    out = Path(args.out)
    out = (out if out.is_absolute() else PROJECT_ROOT / out).resolve()
    if not (source / "Polox.exe").is_file():
        sys.exit(f"{source} has no Polox.exe: export first (tools/release/build_windows.py).")
    out.mkdir(parents=True, exist_ok=True)
    work = out / "installer-work"
    work.mkdir(exist_ok=True)

    version = game_version(root)
    label = f"-{args.label}" if args.label else ""
    setup_name = f"Polox-{version}{label}-Setup"
    zip_name = f"Polox-{version}{label}-Windows-Portable.zip"
    notices = collect_notices(root, work)

    iscc = find_iscc(args.iscc)
    command = [str(iscc), "/Qp", f"/DAppVersion={version}", f"/DSourceDir={source}", f"/DOutputDir={out}",
               f"/DOutputName={setup_name}", f"/DNoticesDir={notices}"]
    if not (notices / "LICENSE").is_file():
        command.remove(f"/DNoticesDir={notices}")
        print("Note: no LICENSE in the source tree, so the setup shows no licence page and ships no notices folder.")
    if args.sign:
        command += [f"/Ssigntool={args.sign}", "/DSign"]
    command.append(str(SCRIPT))
    print(f"Compiling {setup_name}.exe with {iscc} ...", flush=True)
    compiled = subprocess.run(command, capture_output=True, text=True)
    (work / "iscc.log").write_text(compiled.stdout + compiled.stderr, encoding="utf-8")
    setup = out / (setup_name + ".exe")
    if compiled.returncode != 0 or not setup.is_file():
        sys.exit(f"Inno Setup failed (exit {compiled.returncode}):\n{(compiled.stdout + compiled.stderr)[-3000:]}")

    print(f"Writing {zip_name} ...", flush=True)
    file_count = make_portable_zip(source, out / zip_name, f"Polox-{version}", notices)

    checksum_file = out / f"Polox-{version}{label}-SHA256.txt"
    lines = [f"{sha256_of(out / name)}  {name}" for name in (setup.name, zip_name)]
    checksum_file.write_text("\n".join(lines) + "\n", encoding="ascii")
    print(f"\n{setup.name}: {setup.stat().st_size / 1048576:.1f} MB, {signature_status(setup)}")
    print(f"{zip_name}: {(out / zip_name).stat().st_size / 1048576:.1f} MB, {file_count} files")
    print(f"Polox.exe inside both: {signature_status(source / 'Polox.exe')}")
    print("\n".join(lines))
    print(f"Checksums written to {checksum_file}")


if __name__ == "__main__":
    main()
