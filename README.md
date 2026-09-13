# BO2 Quake iOS

A native iOS runtime project for loading **user-supplied Call of Duty: Black Ops II PS3 data** into a Quake-style C gameplay runtime with Metal rendering. The target is a directly launched iOS app/IPA—not a PS3 emulator.

The first supported map target is **Hijacked (`mp_hijacked`)**. The current milestone focuses on the map-runtime foundation: signed T6 PS3 FastFile decoding, GfxWorld geometry extraction, MapEnts/spawn mapping, native movement/collision, first-person Metal rendering, touch controls, and reproducible iPhone Simulator/device builds.

## Architecture

`BO2 PS3 files -> T6 decoder -> BO2RuntimePackage -> native C runtime -> Metal renderer -> iOS touch gameplay`

Key production components:

- `Engine/Quake3/` — native C runtime boundary and GPLv2 licensing/attribution.
- `T6PS3PayloadDecoder` — signed PS3 T6 FastFile decoding/decompression.
- `T6GfxSurfaceMeshExtractor` — GfxWorld triangle-world reconstruction.
- `BO2EntityParser` — MapEnts and multiplayer-spawn extraction.
- `BO2RuntimePackage` — versioned user-local world interchange format.
- `BO2MapRuntimeLoader` — Hijacked decode/package pipeline.
- `QuakeRuntimeController` — Swift-to-C simulation bridge.
- `QuakeGameplayView` — Metal first-person renderer and touch controls.
- `BO2QuakeRootView` — production app entry.

Legacy SceneKit/Tranzit code remains in the source tree as development history/diagnostics, but it is **not the production gameplay entry path**.

## Current milestone

Implemented in the Quake-first branch:

- Recognize `mp_hijacked.ff`, `mp_hijacked.ipak`, and `mpl_hijacked.all.sabs` from a user-selected BO2 PS3 folder.
- Decode the PS3 FastFile locally on-device.
- Extract validated GfxWorld triangle geometry.
- Extract the MapEnts lump and multiplayer spawn records.
- Package geometry/entities/spawns into a versioned user-local runtime package using 32-bit indices.
- Load the package into a native C movement/collision runtime.
- Render through Metal rather than SceneKit.
- Drive first-person position/look from the C player state.
- Provide iPhone touch movement, look, aim, fire, reload, and jump inputs.
- Validate the native path on a fresh iPhone 17 Simulator in GitHub Actions before producing an unsigned device IPA.

This does **not** yet mean complete BO2 parity. Material/texture reconstruction, static models, full clip/collision semantics, weapon definitions/animations, audio, effects, HUD parity, multiplayer logic, Zombies logic, scripting and additional maps remain implementation work.

## Running with owned BO2 data

The app asks the user to choose a BO2 PS3 game folder through the iOS document picker. Retail game content is not distributed with this repository or the IPA. The source folder is read in place through iOS security-scoped access; it is not mirrored wholesale into the app container. Converted expressive runtime data stays user-local under the runtime cache.

## Builds

GitHub Actions performs source/content audits, contract tests, XcodeGen generation, iOS Simulator compilation, a fresh iPhone 17 launch/render validation, an unsigned device build, and IPA packaging. Successful `main` builds update the public `latest-build` release.

## Content and redistribution boundary

The repository and distributed IPA contain project-authored material or material with explicit redistribution rights. BO2/PS3 files remain user-supplied. Do not commit PS3 dumps, FastFiles, IPAKs, audio banks, ISOs, PKGs, EBOOT/SELF/SPRX binaries, extracted retail assets, or expressive derivatives.

Generated metadata such as hashes, paths, offsets and compatibility information may be cached. Decoded textures, reconstructed geometry, extracted meshes, converted audio and other expressive derivatives remain user-local runtime data and are excluded from release artifacts by default.

See [`docs/CONTENT_POLICY.md`](docs/CONTENT_POLICY.md) and the approved runtime design in [`docs/superpowers/specs/2026-09-13-bo2-quake3-ios-runtime-design.md`](docs/superpowers/specs/2026-09-13-bo2-quake3-ios-runtime-design.md).

## License / engine attribution

The `Engine/Quake3` subtree carries GNU GPL version 2 licensing information and documents the Quake III Arena source reference. See `Engine/Quake3/COPYING.txt` and `Engine/Quake3/README.md`.
