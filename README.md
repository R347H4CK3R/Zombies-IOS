# Zombies-IOS

Native iOS Zombies project targeting iPhone 16 Plus.

## Phase 1: PS3 dump scanner/importer

The first component is an on-device scanner that lets the user select a PS3 game folder from the iOS Files app, including folders located on an attached USB drive.

It recursively inventories the selected folder, identifies likely Call of Duty: Black Ops II / Zombies resources, groups files by type, and produces a JSON report. The scanner does **not** upload or copy the entire dump to GitHub.

### Initial goals

- Select a folder using the iOS document picker.
- Work with Files-app locations, including USB storage exposed by iOS.
- Use security-scoped access for external folders.
- Recursively scan `PS3_GAME` / `USRDIR`.
- Flag likely Zombies files such as `zm_*`, FastFiles, scripts, executable modules, audio, textures, models, and archives.
- Export a portable JSON inventory for later converter development.

### Next phases

1. FastFile/zone inspection.
2. Texture conversion.
3. Model and animation conversion.
4. Audio conversion.
5. Map metadata and collision import.
6. Native Zombies gameplay runtime.
7. iPhone touch controls and HUD.
8. GitHub Actions iOS build pipeline.

## Important

Do not commit full PS3 dumps, ISOs, PKGs, EBOOT binaries, or other copyrighted game archives to this repository. Keep source dumps on local/USB storage and use the importer to generate metadata and converted assets that you are legally permitted to use.
