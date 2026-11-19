"""Builds Polox's own Godot 4.7.2 export templates from Godot's official source, with Polox's engine fixes
(native/godot/patches) and only the parts of the engine the game uses (native/godot/polox_profile.py).

    tools\\pyenv\\Scripts\\python tools\\build_engine.py android web windows

Everything it uses is portable inside tools\\ (nothing is installed system-wide, and nothing is downloaded
here except by Gradle on its first run, into tools\\gradle-home):
  downloads\\godot-4.7.2-stable.tar.xz   Godot's source, checked against tools\\godot\\SHA512-SUMS.txt
  pyenv\\                                SCons (native\\godot\\build-requirements.txt, installed by hash)
  jdk17\\, android-sdk\\                  Java 17, NDK 29.0.14206865, platform 36, build-tools 36.1.0
  emsdk\\                                Emscripten 4.0.11 (web)
  llvm-mingw\\                           LLVM-MinGW (Windows)
The source is unpacked into tools\\godot-src\\ with the patches applied; when the patches change, the files they
touch come back from the tarball and are patched again. Results go to tools\\engine\\<platform>\\, and tools\\engine\\build_info.json records the source hash,
the patches, every switch and the hash of every file made. The compilers run at below-normal priority so the
PC stays responsive. Logs: build\\engine\\<platform>.log.
"""

import datetime
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tarfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")
VERSION = "4.7.2-stable"
TARBALL = os.path.join(TOOLS, "downloads", "godot-%s.tar.xz" % VERSION)
SUMS = os.path.join(TOOLS, "godot", "SHA512-SUMS.txt")
SRC_PARENT = os.path.join(TOOLS, "godot-src")
SRC = os.path.join(SRC_PARENT, "godot-%s" % VERSION)
STAMP = os.path.join(SRC, ".polox_patches")
NATIVE = os.path.join(ROOT, "native", "godot")
PATCHES = os.path.join(NATIVE, "patches")
PROFILE = os.path.join(NATIVE, "polox_profile.py")
REMOVED = os.path.join(NATIVE, "removed_classes.txt")
OUT = os.path.join(TOOLS, "engine")
LOGS = os.path.join(ROOT, "build", "engine")
JDK = os.path.join(TOOLS, "jdk17")
SDK = os.path.join(TOOLS, "android-sdk")
NDK_VERSION = "29.0.14206865"
EMSDK = os.path.join(TOOLS, "emsdk")
LLVM_MINGW = os.path.join(TOOLS, "llvm-mingw")
GRADLE_HOME = os.path.join(TOOLS, "gradle-home")

# The game's own files: what a removed engine class must never appear in (tests/ and tools/ never ship).
GAME_DIRS = ("scripts", "scenes", "assets", "shaders", "audio", "addons")
GAME_EXTS = (".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc", ".import", ".cfg")

# Per platform: the SCons switches on top of the profile, and the files SCons/Gradle leave in bin/.
COMMON = ["production=yes", "target=template_release"]
ANDROID_ABIS = {"arm64": "arm64-v8a", "x86_64": "x86_64"}  # the phone, and the emulator / BlueStacks x86 mode
ANDROID = ["platform=android", "vulkan=no", "swappy=no", "debug_symbols=yes", "separate_debug_symbols=yes"]
WEB = ["platform=web", "arch=wasm32", "threads=no"]
WINDOWS = ["platform=windows", "arch=x86_64", "use_mingw=yes", "use_llvm=yes", "d3d12=no", "angle=no", "accesskit=no"]


class BuildError(Exception):
    pass


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def patch_digest():
    h = hashlib.sha256()
    for name in sorted(os.listdir(PATCHES)):
        if name.endswith(".patch"):
            h.update(name.encode())
            with open(os.path.join(PATCHES, name), "rb") as f:
                h.update(f.read())
    return h.hexdigest()


def patched_files():
    files = set()
    for name in os.listdir(PATCHES):
        if name.endswith(".patch"):
            files |= {line[6:].strip() for line in open(os.path.join(PATCHES, name)) if line.startswith("+++ b/")}
    return files


def _writable(func, path, _exc):
    os.chmod(path, stat.S_IWRITE)
    func(path)


def ensure_source():
    """The patched source tree. When the patch set changes, the files the old and new patches touch come back
    from the checked tarball and every patch is applied again (the rest of the tree, and what SCons already
    compiled from it, stays); a missing tree is unpacked whole."""
    digest = patch_digest()
    stamp = {}
    if os.path.isfile(STAMP):
        text = open(STAMP).read().strip()
        try:
            stamp = json.loads(text)
        except ValueError:
            stamp = {"digest": text}   # (the first stamps held only the digest)
    if stamp.get("digest") == digest:
        return
    if not os.path.isfile(TARBALL):
        raise BuildError("Missing %s (Godot's source, from github.com/godotengine/godot/releases)." % TARBALL)
    wanted = None
    for line in open(SUMS):
        parts = line.split()
        if len(parts) == 2 and parts[1] == os.path.basename(TARBALL):
            wanted = parts[0]
    h = hashlib.sha512()
    with open(TARBALL, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    if wanted is None or h.hexdigest() != wanted:
        raise BuildError("%s doesn't match Godot's SHA-512 in %s." % (TARBALL, SUMS))
    top = os.path.basename(SRC) + "/"
    if os.path.isdir(SRC) and stamp:
        refresh = patched_files() | set(stamp.get("files", []))
        print("Restoring %d file(s) from Godot %s (SHA-512 checked) and applying the patches again..." % (len(refresh), VERSION))
        for f in refresh:
            if os.path.isfile(os.path.join(SRC, f)):
                os.remove(os.path.join(SRC, f))   # (a file only a patch made is made again by it)
        with tarfile.open(TARBALL, "r|xz") as t:   # (one pass through the stream)
            for m in t:
                if m.name.startswith(top) and m.name[len(top):] in refresh:
                    t.extract(m, SRC_PARENT, filter="data")
    else:
        print("Unpacking Godot %s (SHA-512 checked) and applying the patches..." % VERSION)
        if os.path.isdir(SRC):
            shutil.rmtree(SRC, onerror=_writable)
        os.makedirs(SRC_PARENT, exist_ok=True)
        with tarfile.open(TARBALL, "r:xz") as t:
            t.extractall(SRC_PARENT, filter="data")
    # git apply as a plain patch tool: the ceiling keeps it from finding Polox's own repository above the
    # source (inside a repository it would skip every path outside the current folder without a word).
    git_env = dict(os.environ, GIT_CEILING_DIRECTORIES=SRC_PARENT)
    for name in sorted(os.listdir(PATCHES)):
        if name.endswith(".patch"):
            path = os.path.join(PATCHES, name)
            for args in (["--check"], [], ["--check", "--reverse"]):   # applies, apply, now applied
                r = subprocess.run(["git", "apply", "--whitespace=nowarn"] + args + [path], cwd=SRC, env=git_env,
                                   capture_output=True, text=True)
                if r.returncode != 0:
                    raise BuildError("Patch %s doesn't apply:\n%s" % (name, r.stderr))
            print("  applied", name)
    with open(STAMP, "w") as f:
        json.dump({"digest": digest, "files": sorted(patched_files())}, f)


def profile_switches():
    switches = {}
    exec(compile(open(PROFILE).read(), PROFILE, "exec"), {}, switches)
    return switches


def _doc_names(folder):
    return {f[:-4] for f in os.listdir(folder) if f.endswith(".xml")} if os.path.isdir(folder) else set()


def module_classes(module):
    folder = os.path.join(SRC, "modules", module)
    names = _doc_names(os.path.join(folder, "doc_classes"))
    config = open(os.path.join(folder, "config.py")).read()
    m = re.search(r"def get_doc_classes\(\):\s*return \[(.*?)\]", config, re.S)
    if m:
        names |= set(re.findall(r'"(\w+)"', m.group(1)))
    return names


def removed_classes():
    """Every class the profile takes out of the engine, written to native/godot/removed_classes.txt."""
    switches = profile_switches()
    names = set()
    for key, value in switches.items():
        m = re.fullmatch(r"module_(\w+)_enabled", key)
        if m and value == "no":
            names |= module_classes(m.group(1))
    if (switches.get("disable_navigation_2d") == "yes") != (switches.get("disable_navigation_3d") == "yes"):
        raise BuildError("The profile must switch 2D and 3D navigation off together (the class list assumes it).")
    prefixes = (["XR"] if switches.get("disable_xr") == "yes" else []) + (
        ["Navigation"] if switches.get("disable_navigation_3d") == "yes" else [])
    every = _doc_names(os.path.join(SRC, "doc", "classes"))
    for module in os.listdir(os.path.join(SRC, "modules")):
        every |= _doc_names(os.path.join(SRC, "modules", module, "doc_classes"))
    names |= {n for n in every if n.startswith(tuple(prefixes))} if prefixes else set()
    text = "# Classes Polox's engine leaves out (written by tools/build_engine.py from native/godot/polox_profile.py).\n"
    text += "".join(n + "\n" for n in sorted(names))
    with open(REMOVED, "w", newline="\n") as f:
        f.write(text)
    return names


def check_game(names):
    """Refuse to build an engine without a class the game uses."""
    rx = re.compile(r"\b(" + "|".join(sorted(map(re.escape, names), key=len, reverse=True)) + r")\b")
    found = []
    paths = [os.path.join(ROOT, "project.godot")]
    for top in GAME_DIRS:
        for root, _dirs, files in os.walk(os.path.join(ROOT, top)):
            paths += [os.path.join(root, f) for f in files if f.endswith(GAME_EXTS)]
    for path in paths:
        text = open(path, encoding="utf-8", errors="replace").read()
        for m in rx.finditer(text):
            found.append("%s: %s" % (os.path.relpath(path, ROOT), m.group(1)))
    if found:
        raise BuildError("The game uses classes this engine leaves out:\n  " + "\n  ".join(found[:40]))
    print("The game uses none of the %d classes this engine leaves out (%d files checked)." % (len(names), len(paths)))


def run(cmd, env, log_name, cwd=SRC):
    os.makedirs(LOGS, exist_ok=True)
    log_path = os.path.join(LOGS, log_name)
    flags = getattr(subprocess, "BELOW_NORMAL_PRIORITY_CLASS", 0)
    with open(log_path, "a", encoding="utf-8", errors="replace") as log:
        log.write("\n$ %s\n" % " ".join(cmd))
        log.flush()
        code = subprocess.call(cmd, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, creationflags=flags)
    if code != 0:
        tail = open(log_path, encoding="utf-8", errors="replace").read().splitlines()[-30:]
        raise BuildError("%s failed (exit %d). Last lines of %s:\n%s" % (cmd[0], code, log_path, "\n".join(tail)))


def scons(args, env, log_name):
    jobs = max(1, (os.cpu_count() or 2) - 2)
    env = dict(env, BUILD_NAME="polox")   # the engine reports itself as 4.7.2.stable.polox (Engine.get_version_info)
    run([sys.executable, "-m", "SCons", "-j%d" % jobs, "profile=" + PROFILE] + COMMON + args, env, log_name)


def need(path, what):
    if not os.path.exists(path):
        raise BuildError("Missing %s: %s" % (what, path))


def collect(platform, files):
    """Copies results from the source tree's bin/ to tools/engine/<platform>/ and returns their record."""
    dest = os.path.join(OUT, platform)
    os.makedirs(dest, exist_ok=True)
    made = {}
    for src_name, dest_name in files:
        src = os.path.join(SRC, "bin", src_name)
        need(src, "build result")
        shutil.copyfile(src, os.path.join(dest, dest_name))
        made[dest_name] = {"bytes": os.path.getsize(src), "sha256": sha256_file(src)}
        print("  %s: %.1f MB" % (dest_name, os.path.getsize(src) / 1e6))
    return made


def build_android():
    need(os.path.join(SDK, "ndk", NDK_VERSION), "Android NDK " + NDK_VERSION)
    need(os.path.join(SDK, "platforms", "android-36"), "Android platform 36")
    need(os.path.join(SDK, "build-tools", "36.1.0"), "Android build-tools 36.1.0")
    need(os.path.join(JDK, "bin", "java.exe"), "JDK 17")
    env = dict(os.environ, ANDROID_HOME=SDK, ANDROID_SDK_ROOT=SDK, JAVA_HOME=JDK, GRADLE_USER_HOME=GRADLE_HOME,
               ANDROID_USER_HOME=os.path.join(TOOLS, "android-home"))
    # Godot's Gradle project looks for scons on PATH even when it has nothing left to compile.
    env["PATH"] = os.pathsep.join([os.path.join(JDK, "bin"), os.path.dirname(sys.executable), env["PATH"]])
    libs = os.path.join(SRC, "platform", "android", "java", "lib", "libs")
    if os.path.isdir(libs):
        shutil.rmtree(libs, onerror=_writable)   # only this build's libraries go into the templates
    for arch in ANDROID_ABIS:
        print("Compiling the Android engine for %s..." % arch)
        scons(ANDROID + ["arch=" + arch], env, "android.log")
    print("Packaging the Android library and templates with Gradle...")
    java = os.path.join(SRC, "platform", "android", "java")
    run(["cmd", "/c", os.path.join(java, "gradlew.bat"), "generateGodotTemplates", "--no-daemon"], env,
        "android.log", cwd=java)   # (by full path: cmd may be set not to run programs from the current folder)
    return {"switches": ANDROID, "abis": list(ANDROID_ABIS.values()), "ndk": NDK_VERSION,
            "files": collect("android", [
                ("godot-lib.template_release.aar", "godot-lib.template_release.aar"),
                ("android_source.zip", "android_source.zip"),
                ("android_release.apk", "android_release.apk"),
                ("android-template-release-native-symbols.zip", "native-symbols.zip")])}


def build_web():
    emscripten = os.path.join(EMSDK, "upstream", "emscripten")
    need(os.path.join(emscripten, "emcc.bat"), "Emscripten 4.0.11 (tools\\emsdk)")
    node = os.path.join(EMSDK, "node", "22.16.0_64bit", "bin")
    python = os.path.join(EMSDK, "python", "3.13.3_64bit")
    env = dict(os.environ, EMSDK=EMSDK, EM_CONFIG=os.path.join(EMSDK, ".emscripten"),
               EMSDK_NODE=os.path.join(node, "node.exe"), EMSDK_PYTHON=os.path.join(python, "python.exe"))
    env["PATH"] = os.pathsep.join([EMSDK, emscripten, node, python, env["PATH"]])
    print("Compiling the web engine...")
    scons(WEB, env, "web.log")
    return {"switches": WEB, "emscripten": "4.0.11",
            "files": collect("web", [("godot.web.template_release.wasm32.nothreads.zip", "web_nothreads_release.zip")])}


def build_windows():
    need(os.path.join(LLVM_MINGW, "bin", "clang.exe"), "LLVM-MinGW (tools\\llvm-mingw)")
    env = dict(os.environ, MINGW_PREFIX=LLVM_MINGW)
    env["PATH"] = os.path.join(LLVM_MINGW, "bin") + os.pathsep + env["PATH"]
    print("Compiling the Windows engine...")
    scons(WINDOWS + ["mingw_prefix=" + LLVM_MINGW], env, "windows.log")
    return {"switches": WINDOWS,
            "files": collect("windows", [("godot.windows.template_release.x86_64.llvm.exe", "windows_release_x86_64.exe"),
                                         ("godot.windows.template_release.x86_64.llvm.console.exe",
                                          "windows_release_x86_64_console.exe")])}


BUILDERS = {"android": build_android, "web": build_web, "windows": build_windows}


def main(argv):
    targets = argv or list(BUILDERS)
    unknown = [t for t in targets if t not in BUILDERS]
    if unknown:
        raise BuildError("Unknown platform(s): %s (use %s)." % (", ".join(unknown), ", ".join(BUILDERS)))
    ensure_source()
    check_game(removed_classes())
    info_path = os.path.join(OUT, "build_info.json")
    info = json.load(open(info_path)) if os.path.isfile(info_path) else {}
    info.update({"godot": VERSION, "source_sha256": sha256_file(TARBALL),
                 "patches": {n: sha256_file(os.path.join(PATCHES, n)) for n in sorted(os.listdir(PATCHES)) if n.endswith(".patch")},
                 "profile": profile_switches()})
    for target in targets:
        started = datetime.datetime.now()
        record = BUILDERS[target]()
        record["built"] = started.isoformat(timespec="seconds")
        record["minutes"] = round((datetime.datetime.now() - started).total_seconds() / 60, 1)
        info.setdefault("platforms", {})[target] = record
        os.makedirs(OUT, exist_ok=True)
        with open(info_path, "w", newline="\n") as f:
            json.dump(info, f, indent=2)
        print("%s engine done in %.0f minutes." % (target, record["minutes"]))


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except BuildError as e:
        print("ERROR:", e)
        sys.exit(1)
