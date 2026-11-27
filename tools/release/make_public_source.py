"""Makes the public source snapshot of Polox: a new folder with a new git repository holding one
commit of the committed files of this checkout, minus what is private, then checks every file in
it. Nothing is pushed or uploaded, and this checkout and its history are not touched.

    python tools/release/make_public_source.py <new folder> [--private-words FILE] [--gitleaks EXE]
                                               [--author "Name <email>"] [--message "..."] [--report FILE]
    add --worktree to snapshot the files as they are now (committed or not) instead of the last commit
    python tools/release/make_public_source.py --check-checkout [--private-words FILE]
        makes no snapshot; runs the text, machine and words checks over every file of this checkout
        that Git sees (committed or not, docs/history/ and storefront/ included). check.bat runs it.

Why a snapshot and not this repository: the history here predates the privacy pass and still holds
this PC's network addresses, machine name and user folder (docs/RELEASES.md "History"). A fresh
repository carries none of it.

What is left out of the snapshot (EXCLUDED):
  docs/history/   old plans, prompts and verification notes written for the owner
  storefront/     the private Hub's download page
Anything git-ignored was never committed, so it can't be in the snapshot either: PersonalData/,
assets/local/ (the private soundtrack, Soul and pictures), local-addons/, assets/music/, build/, the
downloaded toolchains and signing keys.

What is checked, in every file of the snapshot:
  text      e-mail addresses, Tailscale names, user folders, API-key and private-key shapes
  machine   this PC's own user name, computer name, home folder, network addresses and tailnet
            name, read from the system when the tool runs (in text and inside binary files)
  words     every line of --private-words (your name, your phone's name, your street...); a line
            ending in * is a prefix ("SM-A12*"), and . - _ and space stand for each other
  files     nothing over 50 MB, no key stores, no settings.json, no .env
  pictures  JPEG, PNG, WebP and SVG metadata (EXIF, XMP, text chunks, editor author and export
            paths) is reported for review
  gitleaks  the whole new repository, when --gitleaks is given (https://github.com/gitleaks/gitleaks)

Exit code 0 when nothing was found. Findings print as path:line  what.
"""

import argparse
import io
import json
import os
import re
import socket
import struct
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
EXCLUDED = ("docs/history/", "storefront/")
BIG_FILE_BYTES = 50 * 1024 * 1024   # GitHub warns at this size and refuses files of 100 MB
FORBIDDEN_NAMES = re.compile(r"(^|/)(settings\.json|\.env|[^/]*\.(keystore|jks|pem|p12|pfx))$", re.I)
DEFAULT_AUTHOR = "Polox <polox@users.noreply.github.com>"

# Placeholders the tests and docs use on purpose.
SAFE_EMAIL = re.compile(r"@(example\.(com|org|net)|[a-z0-9.-]+\.(example|test|invalid|localhost)|users\.noreply\.github\.com)$", re.I)
SAFE_USERS = {"player", "you", "user", "username", "public", "default", "example", "me", "x", "<you>", "<name>", "<user>", "%username%"}
TEXT_CHECKS = (
    ("e-mail address", re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")),
    ("Tailscale name", re.compile(r"\b[a-z0-9-]+\.tail(?!0+\b)[0-9a-f]{4,}\.ts\.net\b", re.I)),
    ("user folder", re.compile(r"\b[A-Za-z]:(?:\\\\|\\|/)Users(?:\\\\|\\|/)([^\\/\"'<>\s`,;:)\]]+)", re.I)),
    ("key", re.compile(r"\b(sk-(?!ant-test-)[A-Za-z0-9_-]{20,}|gsk_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{30,}|"
                       r"AQ\.[A-Za-z0-9_.-]{20,}|VENICE-[A-Za-z0-9_-]{16,}|hf_[A-Za-z0-9]{25,}|xai-[A-Za-z0-9_-]{20,}|"
                       r"gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|xox[abp]-[A-Za-z0-9-]{10,}|"
                       r"AKIA[0-9A-Z]{16}|tskey-[a-z]+-[A-Za-z0-9-]{10,})")),
    ("private key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
)
# Addresses every PC with the same software has, so they identify nobody: VirtualBox's host-only adapter.
GENERIC_ADDRESSES = {"192.168.56.1"}
# Keys the test suite makes up; they follow a key's shape on purpose and unlock nothing.
KNOWN_FAKE_KEYS = re.compile(r"sk-(test|fake|example|not-?real|x{6,}|0{6,}|a{6,})", re.I)


def run(arguments, cwd=None, data=None):
    return subprocess.run(arguments, cwd=cwd, input=data, capture_output=True, check=True)


# --- This PC's own facts -------------------------------------------------------------------------------

def on_ci_runner():
    """A hosted CI machine (GitHub Actions): its user name, host name and addresses belong to the build
    robot, not to the owner (the runner's user is "runner", which matches every "test runner" in the
    code), so there are no facts about the owner's PC to look for there."""
    return os.environ.get("GITHUB_ACTIONS", "").lower() == "true"


def machine_facts():
    """Strings that identify this PC or its owner's accounts: [(what, text)]. Short or generic values
    are skipped, because they would match ordinary words. None on a CI runner (on_ci_runner)."""
    if on_ci_runner():
        return []
    facts = []

    def add(what, value):
        value = (value or "").strip()
        if len(value) >= 4 and value.lower() not in SAFE_USERS and value not in GENERIC_ADDRESSES and (what, value) not in facts:
            facts.append((what, value))

    add("this PC's user name", os.environ.get("USERNAME") or os.environ.get("USER"))
    add("this PC's name", os.environ.get("COMPUTERNAME") or socket.gethostname())
    home = str(Path.home())
    add("this PC's home folder", home)
    add("this PC's home folder", home.replace("\\", "/"))
    add("this PC's home folder", home.replace("\\", "\\\\"))
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            address = info[4][0]
            if not address.startswith("127."):
                add("this PC's network address", address)
    except OSError:
        pass
    for tailscale in ("tailscale", r"C:\Program Files\Tailscale\tailscale.exe"):
        try:
            status = json.loads(subprocess.run([tailscale, "status", "--json"], capture_output=True, text=True, timeout=15).stdout)
        except (OSError, ValueError, subprocess.SubprocessError):
            continue
        self_node = status.get("Self", {})
        add("this PC's Tailscale name", str(self_node.get("DNSName", "")).rstrip("."))
        add("this tailnet's name", str(status.get("MagicDNSSuffix", "")))
        for address in self_node.get("TailscaleIPs", []) or []:
            add("this PC's Tailscale address", address)
        for peer in (status.get("Peer") or {}).values():
            add("a device on this tailnet", str(peer.get("HostName", "")))
            for address in peer.get("TailscaleIPs", []) or []:
                add("a tailnet device's address", address)
        break
    return facts


def whole_word(text):
    """Matches `text` when it isn't part of a longer word or number (so 192.0.2.5 doesn't match 192.0.2.55).
    The separators . - _ and space stand for each other, so an address is also found where it was
    written into a file name (192-0-2-5) and a model number with either spelling (AB-123, AB_123).
    A trailing * makes `text` a prefix: "robin*" also finds "robins-phone"."""
    prefix = text.endswith("*")
    body = "".join(r"[.\-_ ]" if ch in ".-_ " else re.escape(ch) for ch in text.rstrip("*"))
    return re.compile(r"(?<![A-Za-z0-9])" + body + ("" if prefix else r"(?![A-Za-z0-9])"), re.I)


# --- Making the snapshot -------------------------------------------------------------------------------

def worktree_tree():
    """A Git tree of this checkout as it is now: committed and uncommitted files, never ignored ones
    (git add -A respects .gitignore and .gitattributes, as a commit would). It is built in a scratch
    index, so HEAD, the branch, the real index and the files on disk are all left as they were."""
    with tempfile.TemporaryDirectory() as scratch:
        environment = dict(os.environ, GIT_INDEX_FILE=str(Path(scratch) / "index"))
        for arguments in (["read-tree", "HEAD"], ["add", "-A"]):
            subprocess.run(["git", "-C", str(PROJECT_ROOT)] + arguments, env=environment, capture_output=True, check=True)
        return subprocess.run(["git", "-C", str(PROJECT_ROOT), "write-tree"], env=environment,
                              capture_output=True, check=True).stdout.decode().strip()


def copy_committed_files(destination, tree_ish="HEAD"):
    """Extracts `tree_ish` (HEAD: committed files only) and returns the paths that were left out."""
    archive = run(["git", "-C", str(PROJECT_ROOT), "archive", "--format=tar", tree_ish]).stdout
    left_out = []
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        members = []
        for member in tar.getmembers():
            if member.name.startswith(EXCLUDED) or (member.name + "/").startswith(EXCLUDED):
                if member.isfile():
                    left_out.append(member.name)
                continue
            members.append(member)
        tar.extractall(destination, members=members, filter="data")
    return left_out


def commit_snapshot(destination, author, message):
    found = re.match(r"^\s*(.+?)\s*<([^>]+)>\s*$", author)
    if not found:
        sys.exit('--author must look like: Name <email>')
    environment = dict(os.environ, GIT_AUTHOR_NAME=found.group(1), GIT_AUTHOR_EMAIL=found.group(2),
                       GIT_COMMITTER_NAME=found.group(1), GIT_COMMITTER_EMAIL=found.group(2))
    run(["git", "init", "-q", "-b", "main"], cwd=destination)
    run(["git", "add", "-A"], cwd=destination)
    subprocess.run(["git", "commit", "-q", "-F", "-"], cwd=destination, input=message.encode("utf-8"), env=environment, check=True)
    return run(["git", "log", "-1", "--format=%an <%ae>"], cwd=destination).stdout.decode().strip()


# --- Checking ------------------------------------------------------------------------------------------

def picture_metadata(name, data):
    """What a JPEG or PNG says about itself beyond its pixels, for a person to look at."""
    notes = []
    lower = name.lower()
    if lower.endswith((".jpg", ".jpeg")):
        if b"Exif\x00\x00" in data[:65536]:
            notes.append("EXIF metadata" + (" with GPS tags" if b"GPS" in data[:65536] else ""))
        if b"http://ns.adobe.com/xap/1.0/" in data[:262144]:
            notes.append("XMP metadata")
    elif lower.endswith(".png") and data[:8] == b"\x89PNG\r\n\x1a\n":
        cursor, keys = 8, []
        while cursor + 8 <= len(data):
            (length,) = struct.unpack(">I", data[cursor:cursor + 4])
            kind = data[cursor + 4:cursor + 8]
            if kind in (b"tEXt", b"iTXt", b"zTXt"):
                keys.append(data[cursor + 8:cursor + 8 + length].split(b"\x00", 1)[0].decode("latin-1", "replace"))
            if kind == b"IEND":
                break
            cursor += 12 + length
        if keys:
            notes.append("PNG text chunks: " + ", ".join(sorted(set(keys))))
    elif lower.endswith(".webp") and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        for chunk, what in ((b"EXIF", "EXIF metadata"), (b"XMP ", "XMP metadata")):
            if chunk in data[12:]:
                notes.append(what)
    elif lower.endswith(".svg"):
        # Editors write who made a drawing and where it was saved or exported on their PC.
        text = data.decode("utf-8", "replace")
        found = sorted(set(re.findall(r"(dc:creator|dc:rights|cc:Agent|sodipodi:docname|inkscape:export-filename|"
                                      r"inkscape:export-xdpi|sodipodi:absref|xlink:href=\"file:)", text)))
        if found:
            notes.append("SVG editor metadata: " + ", ".join(found))
    return notes


def snapshot_files(destination):
    """Every file of the snapshot: [(relative path, path)]."""
    out = []
    for folder, folders, files in os.walk(destination):
        folders[:] = [f for f in folders if f != ".git"]
        for file_name in files:
            path = Path(folder) / file_name
            out.append((path.relative_to(destination).as_posix(), path))
    return out


def checkout_files():
    """Every file of this checkout Git would see: committed or not, but not ignored. Unlike the
    snapshot this includes docs/history/ and storefront/, which are private but still shouldn't
    carry personal details."""
    listed = run(["git", "-C", str(PROJECT_ROOT), "ls-files", "-co", "--exclude-standard", "-z"]).stdout
    names = sorted({name for name in listed.decode("utf-8").split("\0") if name})
    return [(name, PROJECT_ROOT / name) for name in names if (PROJECT_ROOT / name).is_file()]


def scan(files, private_words, facts):
    findings, pictures = [], []
    word_patterns = [(word, whole_word(word)) for word in private_words]
    fact_patterns = [(what, text, whole_word(text)) for what, text in facts]
    for relative, path in files:
        size = path.stat().st_size
        if size >= BIG_FILE_BYTES:
            findings.append((relative, 0, "a file of %d MB" % (size // 1048576)))
        if FORBIDDEN_NAMES.search(relative):
            findings.append((relative, 0, "a kind of file that must not be public"))
        data = path.read_bytes()
        for note in picture_metadata(relative, data):
            pictures.append((relative, note))
        if b"\x00" in data[:8000]:
            # Binary: look for this PC's facts as UTF-8 and as UTF-16 (how Windows tools embed paths).
            haystack = data.lower()
            for what, text, _pattern in fact_patterns:
                for encoded in (text.lower().encode("utf-8"), text.lower().encode("utf-16-le")):
                    if encoded in haystack:
                        findings.append((relative, 0, f"{what} inside a binary file"))
                        break
            continue
        text = data.decode("utf-8", "replace")
        for number, line in enumerate(text.splitlines(), 1):
            for what, pattern in TEXT_CHECKS:
                for match in pattern.finditer(line):
                    if what == "e-mail address" and SAFE_EMAIL.search(match.group(0)):
                        continue
                    if what == "user folder" and match.group(1).lower() in SAFE_USERS:
                        continue
                    if what == "key" and KNOWN_FAKE_KEYS.match(match.group(0)):
                        continue
                    findings.append((relative, number, f"{what}: {match.group(0)}"))
            for what, _text, pattern in fact_patterns:
                if pattern.search(line):
                    findings.append((relative, number, what))
            for index, (_word, pattern) in enumerate(word_patterns):
                if pattern.search(line):
                    findings.append((relative, number, "a private word (entry %d of the list)" % (index + 1)))
    return findings, pictures


def main():
    parser = argparse.ArgumentParser(description="Make and check the public source snapshot of Polox.")
    parser.add_argument("dest", nargs="?", default="")
    parser.add_argument("--author", default=DEFAULT_AUTHOR, help='who the one commit is by (default: "%s")' % DEFAULT_AUTHOR)
    parser.add_argument("--message", default="")
    parser.add_argument("--private-words", default="", help="a text file, one word or phrase per line; keep it outside the repository")
    parser.add_argument("--gitleaks", default="", help="path to gitleaks.exe")
    parser.add_argument("--report", default="", help="also write the result here (Markdown)")
    parser.add_argument("--worktree", action="store_true",
                        help="snapshot the files as they are now (committed or not; git-ignored files never) instead of the last commit")
    parser.add_argument("--check-checkout", action="store_true",
                        help="make no snapshot: check every file of this checkout that Git sees (committed or not), docs/history/ and storefront/ included")
    args = parser.parse_args()

    private_words = []
    if args.private_words:
        with open(args.private_words, encoding="utf-8") as handle:
            private_words = [line.strip() for line in handle if line.strip() and not line.lstrip().startswith("#")]

    if args.check_checkout:
        files = checkout_files()
        facts = machine_facts()
        findings, _pictures = scan(files, private_words, facts)
        for relative, number, what in findings:
            print(f"  {relative}:{number}  {what}")
        print(f"[privacy] {len(findings)} finding(s) in {len(files)} files of this checkout; checked against {len(facts)} facts about this PC"
              + (f" and {len(private_words)} private words." if private_words else " (no --private-words file given).")
              + (" On a CI runner: the machine's own names and addresses are the robot's, so only keys and patterns were checked." if on_ci_runner() else ""))
        sys.exit(1 if findings else 0)
    if not args.dest:
        parser.error("give the new folder for the snapshot, or --check-checkout")

    destination = Path(args.dest).resolve()
    if PROJECT_ROOT in destination.parents or destination == PROJECT_ROOT:
        sys.exit("Put the snapshot outside this repository.")
    if destination.exists() and any(destination.iterdir()):
        sys.exit(f"{destination} isn't empty.")
    source_commit = run(["git", "-C", str(PROJECT_ROOT), "rev-parse", "--short", "HEAD"]).stdout.decode().strip()
    uncommitted = bool(run(["git", "-C", str(PROJECT_ROOT), "status", "--porcelain"]).stdout.strip())
    tree_ish = "HEAD"
    if args.worktree:
        tree_ish = worktree_tree()
        if uncommitted:
            source_commit += " plus uncommitted changes"
    elif uncommitted:
        print("Note: uncommitted changes aren't in the snapshot (it is made from the last commit; --worktree takes them).")
    version = re.search(r'^config/version="([^"]+)"', (PROJECT_ROOT / "project.godot").read_text(encoding="utf-8"), re.M)
    message = args.message or "Polox %s" % (version.group(1) if version else "")

    destination.mkdir(parents=True, exist_ok=True)
    left_out = copy_committed_files(destination, tree_ish)
    committed_by = commit_snapshot(destination, args.author, message.strip() + "\n")
    file_count = int(run(["git", "ls-files"], cwd=destination).stdout.count(b"\n"))
    print(f"Snapshot made: {destination} ({file_count} files, one commit by {committed_by}; {len(left_out)} private files left out)")

    facts = machine_facts()
    findings, pictures = scan(snapshot_files(destination), private_words, facts)
    for relative, number, what in findings:
        print(f"  {relative}:{number}  {what}")
    print(f"{len(findings)} finding(s) in {file_count} files; checked against {len(facts)} facts about this PC"
          + (f" and {len(private_words)} private words." if private_words else " (no --private-words file given)."))
    for relative, note in pictures:
        print(f"  picture metadata to review: {relative}: {note}")

    leaks = 0
    gitleaks_summary = "not run"
    if args.gitleaks:
        gitleaks = Path(args.gitleaks).resolve()   # (Windows won't start a relative path written with forward slashes)
        if not gitleaks.is_file():
            sys.exit(f"gitleaks was not found at {gitleaks}")
        result = subprocess.run([str(gitleaks), "git", str(destination), "--no-banner", "--redact"], capture_output=True, text=True)
        gitleaks_summary = (result.stdout.strip() or result.stderr.strip()).splitlines()[-1] if (result.stdout or result.stderr) else "no output"
        print("gitleaks: " + gitleaks_summary)
        leaks = result.returncode

    if args.report:
        lines = [f"# Public source snapshot check", "",
                 f"- Made from commit `{source_commit}` of the private checkout ({message.strip()}).",
                 f"- {file_count} files in one commit by `{committed_by}`; {len(left_out)} files left out ({', '.join(EXCLUDED)}).",
                 f"- Text, binary and file-name checks: **{len(findings)} finding(s)**, against {len(facts)} facts about the build PC"
                 + (f" and {len(private_words)} private words." if private_words else "; no private-words list was given."),
                 f"- gitleaks: {gitleaks_summary}.", ""]
        if findings:
            lines += ["## Findings", ""] + [f"- `{relative}:{number}` {what}" for relative, number, what in findings] + [""]
        lines += ["## Picture metadata to review", ""] + ([f"- `{relative}`: {note}" for relative, note in pictures] or ["None."]) + [""]
        Path(args.report).write_text("\n".join(lines), encoding="utf-8")
    sys.exit(1 if findings or leaks else 0)


if __name__ == "__main__":
    main()
