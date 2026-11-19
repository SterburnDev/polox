# Licensing

> **Status: chosen by the owner: GPL-2.0-or-later, 17 November 2026**, replacing the MIT
> licence picked on 10 November. Nothing had been published under MIT. The `LICENSE` file takes effect
> when the owner publishes the repository with it; until then nothing here grants anyone anything.

## What is licensed how

| What | Licence | Why |
| --- | --- | --- |
| Code: `scripts/`, `tests/`, `tools/`, `native/`, `shaders/`, `scenes/`, build files | **GPL-2.0-or-later** | Anyone may use, study, change and share Polox, but whoever distributes a changed version (or a build of one) must share its source under the same terms. Forks stay open. "Or later" lets a build be shipped under GPL-3.0, which the Apache-2.0 parts of the Godot engine need (below) |
| Art and sound made for Polox: the furniture models built by `tools/blender_scripts/`, the battle sprites in `assets/battles/`, the Music-secret drawings, the synthesized sounds, Polox Originals | **GPL-2.0-or-later** too | One licence for the whole repository keeps reuse simple. The alternative for art is CC BY-SA 4.0, below |
| The name "Polox", the logo and the app icon (`assets/icon/`) | **Not licensed for reuse** | So a fork is recognisably a fork. They may be used to refer to Polox and in unmodified builds |
| Third-party files | Their own licences | Listed in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md); all bundled ones are CC0 or MIT, which the GPL allows |

Copyright (C) 2026 The Polox authors. Put your own name or handle there if you would rather be credited
by name; it is the one place the repository names its owner.

The notice that goes with `LICENSE`:

> Polox is free software; you can redistribute it and/or modify it under the terms of the GNU General
> Public License as published by the Free Software Foundation; either version 2 of the License, or (at
> your option) any later version. Polox is distributed in the
> hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
> MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
> details.

## What the GPL asks of whoever publishes builds

- **Source next to every build.** A setup program, portable zip, web build or APK given to anyone must
  come with the matching source, or with a written offer of it. Publishing each build as a GitHub release
  of the public repository does this: the release carries the source archive of the same commit.
- **The licence travels with the build.** The setup program and the portable zip already install
  `LICENSE` and the notices into `licenses\` (`tools/release/build_installer.py`).
- **Changed files say so.** A fork that changes a file notes that it changed it, and when.
- **Playing needs nothing.** Running the game isn't restricted, so the setup program shows no licence
  page.

The private builds (with `assets/local/`) never leave the owner's own devices, so none of this applies to
them.

## Alternatives, and what would change

- **GPL-2.0-only.** The same terms without "or later". Under the Free Software Foundation's reading it
  can't be combined with Apache-2.0 code, and several parts of the Godot engine inside every build are
  Apache-2.0 (the Vulkan headers, SPIRV-Reflect, Basis Universal and others), so a fork could not
  lawfully ship builds. That is why "or later" was chosen: a build is then shipped under GPL-3.0's terms.
- **GPL-3.0 only.** Adds patent terms and rules against locked-down devices. Compatible with Godot's MIT
  licence, with Apache-2.0 and with CC0 assets.
- **MIT** (the earlier choice). Anyone may reuse the code, including in closed programs, with credit.
- **CC BY-SA 4.0 for original art and sound.** The usual open choice for game art: reuse is allowed with
  credit, and changed art stays under the same terms. Each art folder would then carry a short notice.
- **All rights reserved for art.** The code stays open and the art may only be used in Polox. This is
  what many open-source games do; it would mean a contributor can't reuse a model elsewhere.

## What a licence does not cover

- **Private content** is never in the repository: the owner's soundtrack, Soul picture and personal
  pictures live in the git-ignored `assets/local/` and are not cleared for redistribution
  ([ASSET_AUDIT.md](ASSET_AUDIT.md)).
- **Your worlds** are yours. Nothing in a save folder is part of the project.
- **Add-ons** you make or load from `PersonalData/addons/` are your own; they are data the game reads.
- **AI providers** have their own terms. Polox sends them only what a conversation needs, with the key
  you supply, and ships no key of its own.

## Contributions

By sending a change you agree it may be distributed under the repository's licence
([CONTRIBUTING.md](../CONTRIBUTING.md)). Only add assets you made yourself or that are CC0, and record
their source in `docs/ASSET_AUDIT.md`.
