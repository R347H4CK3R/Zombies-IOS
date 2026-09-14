# BO2 Full Conversion Checkpoint

## Resume Anchor
- Branch: `bo2-full-conversion`
- Current task: Exact retail-PS3 T6 typed asset traversal and GameData emission.
- Current substep: Traverse nested inline `GfxImage` assets inside GfxWorld reflection probes/lightmaps using generated T6 ZoneCode ordering and verified PS3 layouts, then reach vd0/vd1/index payloads exactly.
- Current branch head before this checkpoint update: `7b7c082503ed0bc56c3ab4b36598e9782aad62d5` (`fix: decode T6 zone pointers through verified API`).
- Latest fully green isolated CI: `34799035005` (`BO2 Full Conversion CI` run #62). Unit tests, unsigned device build, IPA packaging, and artifact upload all passed.
- Do not restart from source classification, basic FastFile decryption, Hijacked discovery, or the now-verified pre-draw GfxWorld fixes.

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

## Verified PS3 ABI / Walker Fixes
- `GfxWorldFogVolume` serialized size is 100 bytes; regression test is green.
- Inline `sunLight` consumes the verified 352-byte retail-PS3 `GfxLight` body aligned to 16 bytes; nested `GfxLightDef*` remains a typed-asset case rather than a guessed skip.
- Retail PS3 `GfxReflectionProbe` records are empirically 80 bytes in this zone, while OpenAssetTools host-x86 reports 76 bytes. The walker now uses 80-byte records aligned to 16, with PS3 offsets `reflectionImage=64`, `probeVolumes=68`, `probeVolumeCount=72`.
- `T6ZonePointer.decode(_:)` is the canonical pointer decoder; the temporary erroneous `rawValue:` construction was removed.
- These changes are verified by CI run `34799035005`.

## Generated OpenAssetTools Reference
- `Dump T6 Generated Loader` run `34797635121` succeeded and produced artifact `t6-generated-loaders` (artifact id `10330098018`).
- The generated T6 `GfxWorld` loader establishes exact nested order: reflection-probe array -> per-probe `GfxImage` asset -> per-probe volume array -> lightmap array -> per-lightmap primary/secondary `GfxImage` assets -> vertex-data-0 -> vertex-data-1 -> indices. Runtime texture arrays use runtime blocks and do not consume normal serialized payload bytes.
- The generated T6 `GfxImage` loader establishes exact behavior:
  1. Asset pointer pushes `XFILE_BLOCK_TEMP`.
  2. FOLLOWING/INSERT image allocates a 4-byte-aligned 80-byte `GfxImage` raw body.
  3. `GfxImage` pushes `XFILE_BLOCK_VIRTUAL`.
  4. The image `name` XString is loaded first.
  5. Embedded `GfxTexture` is processed next; its `loadDef` pushes TEMP.
  6. FOLLOWING/INSERT `GfxImageLoadDef` is 4-byte aligned and loads the fixed header through `offsetof(data)`, then exactly `resourceSize` data bytes.
  7. `pixels` and `basemap` are not serialized through this path.
- This generated ordering is the behavioral authority; PS3 byte sizes/offsets still require PS3-safe verification where ABI alignment differs.

## Current Implementation State
- Whole-game source classifier exists.
- `GameDataManifest` exists with source-hash + converter-version resume semantics.
- `BO2FullGameConverter` converts validated FastFiles to decoded zones and deliberately leaves unimplemented typed stages pending rather than falsely marking raw/indexed content converted.
- `FullGameValidationReport` prevents release unless Campaign, Multiplayer and Zombies pass startup/render/collision/weapon/audio validation with no fallbacks/placeholders/conversion failures and an unsigned IPA is built.
- `T6ZoneStreamCursor` contains logical-block alignment semantics for T6 block ids: TEMP=0, runtime=1/2, delayed=3/4, normal VIRTUAL/PHYSICAL/STREAMER=5/6/7.
- `T6GfxWorldStreamWalker` now handles verified fog, sunLight body, cells, and PS3 reflection-probe raw layout. Its remaining immediate blocker is nested inline `GfxImage` traversal.

## Next Concrete Actions
1. Add a failing regression for a draw reflection probe whose `reflectionImage` is FOLLOWING and whose inline image has a FOLLOWING name/loadDef payload.
2. Implement a reusable PS3 T6 `GfxImage` stream walker using generated loader block/order semantics, not guessed serialized offsets.
3. Reuse that walker for GfxWorld reflection probes and lightmap primary/secondary image pointers.
4. Continue traversal until vd0/vd1/index FOLLOWING payloads are reached exactly on real Hijacked bytes.
5. Validate index bounds against 109,415 vertices and 232,677 indices, then emit real Hijacked world geometry without heuristic surface scanning.
6. Replace `T6GfxSurfaceMeshExtractor` fallback discovery with the exact GfxWorld/DPVS surface path and add real-zone regression verification.
7. Extend the typed asset dispatcher across images/materials/models/animations/audio/weapons/entities/scripts/collision/UI for every BO2 FastFile and associated IPAK/SABS/SABL input, preserving per-asset resume checkpoints.
8. Embed only converted GameData in the app bundle/build input; do not copy the raw PS3 source tree into app data or publish game assets in the repository.
9. Build the unsigned IPA and run representative Campaign, Multiplayer and Zombies runtime validation. Only `FullGameValidationReport.isPlayableRelease == true` qualifies as completion.

## User Input Required
None right now. The populated Drive dump and representative local FastFiles are available.

## Resume Rule
On any interruption/new session: read this file first, verify the `bo2-full-conversion` branch head and newest CI/helper runs, then continue from `Next Concrete Actions`. Do not restart from Hijacked discovery, basic FastFile decoding, or the old Zombies-only scanner.
