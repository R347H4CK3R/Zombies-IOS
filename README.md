# Zombies-IOS

Native iOS Zombies project targeting iPhone 16 Plus.

## Phase 1: PS3 dump scanner/importer (frozen)

The scanner is now considered stable enough for development. Runtime work should consume verified imported files progressively instead of blocking on repeated filtering passes.

The first component is an on-device scanner that lets the user select a PS3 game folder from the iOS Files app, including folders located on an attached USB drive.

It recursively inventories the selected folder, identifies likely Call of Duty: Black Ops II / Zombies resources, groups files by type, and produces a JSON report. The scanner does **not** upload or copy the entire dump to GitHub.

### Initial goals

- Select a folder using the iOS document picker.
- Work with Files-app locations, including USB storage exposed by iOS.
- Use security-scoped access for external folders.
- Recursively scan `PS3_GAME` / `USRDIR`.
- Flag likely Zombies files such as `zm_*`, FastFiles, scripts, executable modules, audio, textures, models, and archives.
- Export a portable JSON inventory for later converter development.

### Current runtime phase

1. Persist verified BO2 Zombies files even when the legacy manifest is incomplete.
2. Build a Tranzit runtime index from imported FastFiles, IPAKs, audio banks, and discovered references.
3. Resolve Tranzit area resources into native map/runtime structures.
4. Add map metadata, collision, textures, models, animation, and audio conversion.
5. Add native Zombies gameplay, iPhone touch controls, and HUD.
6. Continue producing IPA builds through GitHub Actions.

## Content and redistribution boundary

The repository and distributed IPA are intended to contain only project-authored material or material with explicit redistribution rights. BO2/PS3 game files are supplied separately by the user through iOS Files or attached storage and are read from that external location; the project does not bundle them into the IPA or mirror the selected game folder into app-private storage.

Generated metadata such as hashes, paths, offsets, and compatibility information may be cached separately. Decoded textures, reconstructed map geometry, extracted meshes, converted audio, copied scripts, and similar expressive derivatives remain user-local runtime data and are excluded from release artifacts by default.

See [`docs/CONTENT_POLICY.md`](docs/CONTENT_POLICY.md) for the full contribution, provenance, allow-list, and CI audit rules.

## Important

Do not commit full PS3 dumps, FastFiles, IPAKs, audio banks, ISOs, PKGs, EBOOT/SELF/SPRX binaries, extracted game assets, or other copyrighted game archives to this repository. Converting, renaming, compressing, decompiling, encrypting, or repackaging a third-party asset does not by itself change its copyright status. Keep source dumps and expressive derivatives local and use the importer for user-supplied data.
