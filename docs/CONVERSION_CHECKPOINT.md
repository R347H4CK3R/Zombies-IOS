# BO2 Full Conversion Checkpoint

## Resume Anchor
- Branch: `bo2-full-conversion`
- Current task: Exact retail-PS3 T6 typed asset traversal and GameData emission.
- Current substep: Replace heuristic GfxWorld scanning with an exact big-endian retail-PS3 serialized walker, using OpenAssetTools ZoneCode ordering as the behavioral reference while honoring PS3 ABI/layout differences.
- Current branch head at this checkpoint: `6dbed9b3fb59d0ba306b7dead1ec564837698e3b` (`fix: install x86 compiler runtime for OAT ZoneCode generation`).
- Do not restart from source classification, basic FastFile decryption, or Hijacked discovery; those stages are already proven.

## Proven Real-Data State
- Populated user-owned BO2 dump is in the earlier connected Drive tree under `PS3_GAME/USRDIR/english`; the later Hijacked-only Drive folder is not the complete source.
- Real FastFile decrypt/decompression is proven across all three game modes:
  - Multiplayer `mp_hijacked.ff` -> 52,391,343-byte decoded T6 zone.
  - Campaign `afghanistan.ff` -> 63,037,597-byte decoded T6 zone.
  - Zombies `common_zm.ff` -> 23,065,227-byte decoded T6 zone.
- FastFile encryption/decompression is therefore not the active blocker.

## Hijacked GfxWorld Regression Anchor
- Decoded-zone SHA-256: `f93655577fac1916c542f351dc908886290b51a14cfaae39c58aa0fc10002ffa`.
- GfxWorld serialized offset: `22967056`.
- GfxWorld raw size: `0x404` (1028 bytes).
- GfxWorldDraw embedded offset: `0x18c`.
- Counts read from the actual PS3 zone:
  - planes: 5570
  - nodes: 19219
  - surfaces: 2366
  - reflection probes: 19
  - lightmaps: 1
  - vertices: 109415
  - vertex-data-0 bytes: 888912
  - vertex-data-1 bytes: 1967176
  - indices: 232677
  - static models: 2406
  - static surfaces: 2338
- `0xFFFFFFFF` pointers are FOLLOWING/inline sentinels and must never be treated as literal offsets.

## Exact Traversal Progress
The serialized stream immediately after the raw 0x404-byte GfxWorld has been walked and verified through all 37 cells using actual Hijacked bytes. The validated pre-draw order is:
1. `streamInfo.aabbTrees` — 452 * 48 bytes.
2. `streamInfo.leafRefs` — 5304 * 4 bytes.
3. `sunLight` raw structure — 352 bytes.
4. shadow-map volumes and planes.
5. exposure volumes and planes.
6. world-fog volumes and planes.
7. LUT volumes and planes.
8. `dpvsPlanes.planes` — 5570 * 20 bytes.
9. `dpvsPlanes.nodes` — 19219 * 2 bytes.
10. 37 raw `GfxCell` records.
11. For every cell: raw AABB trees, FOLLOWING static-model index arrays, raw portals, FOLLOWING portal vertices, and cell reflection-probe byte arrays.

The full verified cell traversal ends at serialized offset `23272268`. At that position the real 19-record draw reflection-probe array begins.

## PS3 ABI Finding
- Retail PS3 `GfxReflectionProbe` records are empirically 80 bytes in this zone, while OpenAssetTools host-x86 reports 76 bytes. This confirms that generated host layouts are useful for member order/pointer semantics but not safe as byte-size authority for every vec4/alignment-sensitive PS3 structure.
- The 19 records contain plausible map-space probe origins, proving this is the correct draw reflection-probe array.
- Naively skipping 19 * 80 plus a lightmap record and then treating the next bytes as vd0/vd1/indices produces non-index data. Inline/reflection-image asset serialization and/or other nested members must be consumed first.

## OpenAssetTools Reference Work
- Current OAT v0.33.0 Linux binary has been acquired and made runnable with a bundled 32-bit loader/libs + qemu.
- Stock OAT does not directly type-load the retail PS3 fastfiles: it classifies the big-endian signed version as Xbox and sends BE files down the dump-only path. Do not fall back to OAT's stock Xbox/BE branch as a conversion solution.
- OAT remains the authoritative reference for T6 structure definitions, ZoneCode member order, pointer handling, and generated loader semantics.
- Exact host-x86 layout probes were generated successfully for GfxWorld, GfxWorldDraw, DPVS, GfxImage and related records.
- Helper workflow `.github/workflows/dump-t6-generated-loader.yml` is being used to capture generated `GfxWorld` loader source; after the previous missing-x86-toolchain failure it was patched to install `g++-multilib`/`libc6-dev-i386` before building `ZoneCode`.

## Current Implementation State
- Whole-game source classifier exists.
- `GameDataManifest` exists with source-hash + converter-version resume semantics.
- `BO2FullGameConverter` converts validated FastFiles to decoded zones and deliberately leaves unimplemented typed stages pending rather than falsely marking raw/indexed content converted.
- `FullGameValidationReport` prevents release unless Campaign, Multiplayer and Zombies pass startup/render/collision/weapon/audio validation with no fallbacks/placeholders/conversion failures and an unsigned IPA is built.
- `T6ZoneStreamCursor` contains correct logical-block alignment semantics for serialized payload walking.
- `T6GfxWorldDrawRelocator` still needs replacement/extension: its current guard rejects earlier FOLLOWING payloads instead of traversing the complete nested object graph.

## Next Concrete Actions
1. Finish capturing the generated OAT T6 GfxWorld loader and extract exact member-loading order/pointer semantics.
2. Port that order into a big-endian PS3-specific walker using verified PS3 sizes; never infer serialized offsets from host pointer values.
3. Traverse draw reflection probes including inline `GfxImage` assets and lightmaps until vd0/vd1/index FOLLOWING payloads are reached exactly.
4. Validate index bounds against 109,415 vertices and 232,677 indices, then emit real Hijacked world geometry without heuristic surface scanning.
5. Replace `T6GfxSurfaceMeshExtractor` fallback discovery with the exact GfxWorld/DPVS surface path and add real-zone regression verification.
6. Extend the typed asset dispatcher across images/materials/models/animations/audio/weapons/entities/scripts/collision/UI for every BO2 FastFile and associated IPAK/SABS/SABL input, preserving per-asset resume checkpoints.
7. Embed only converted GameData in the app bundle/build input; do not copy the raw PS3 source tree into app data or publish game assets in the repository.
8. Build the unsigned IPA and run representative Campaign, Multiplayer and Zombies runtime validation. Only `FullGameValidationReport.isPlayableRelease == true` qualifies as completion.

## User Input Required
None right now. The populated Drive dump and representative local FastFiles are available.

## Resume Rule
On any interruption/new session: read this file first, verify the `bo2-full-conversion` branch head and newest CI/helper runs, then continue from `Next Concrete Actions`. Do not restart from Hijacked discovery, basic FastFile decoding, or the old Zombies-only scanner.
