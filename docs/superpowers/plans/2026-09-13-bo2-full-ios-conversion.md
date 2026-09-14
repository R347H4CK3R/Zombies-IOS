# BO2 Full iOS Conversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generalize the existing Zombies-first iOS project into a full BO2 PS3-dump conversion/runtime path and produce an unsigned IPA whose release gate requires playable Campaign, Multiplayer, and Zombies validation.

**Architecture:** Preserve external security-scoped access to the user's BO2 dump, finish deterministic T6 decoding/stream relocation, convert assets into a versioned local GameData cache, and load them through one native Swift/Metal runtime with mode-specific launch descriptors. Public CI remains asset-clean and validates with synthetic fixtures; device validation uses the user's local dump.

**Tech Stack:** Swift 5, SwiftUI, Metal/iOS native frameworks, C zlib bridge, XcodeGen, GitHub Actions, Python tooling for dump-side conversion/diagnostics.

**Spec:** `docs/superpowers/specs/2026-09-13-bo2-full-ios-conversion-design.md`

## Global Constraints
- iOS deployment target remains 17.0 or newer.
- Full BO2 dump remains external/user-local; do not commit or publish copyrighted archives or extracted expressive assets.
- No full-folder copy into app-private storage.
- Hijacked is a regression fixture, not a scope limit.
- Completion means built unsigned IPA plus playable Campaign, Multiplayer, and Zombies device validation; indexing alone is not completion.

---

### Task 1: Full-game source classification

**Files:**
- Modify: `Sources/ZombiesIOS/Services/PS3DumpScanner.swift`
- Create: `Sources/ZombiesIOS/Models/BO2ContentCatalog.swift`
- Modify: `Sources/ZombiesIOS/Models/ScanReport.swift`

**Interfaces:**
- Produces: `BO2ContentCatalog`, `BO2ContentMode`, and mode-aware file classification consumed by conversion and UI.

- [ ] Add tests/fixtures for `sp_*`, `mp_*`, `zm_*`, common/global, localization, FastFiles, IPAKs, audio banks, scripts, and supporting archives.
- [ ] Run scanner classification tests and verify Zombies-only assumptions fail.
- [ ] Implement `BO2ContentMode { campaign, multiplayer, zombies, common }` and deterministic classification.
- [ ] Run tests and verify all mode classifications pass.
- [ ] Commit `feat: classify full BO2 content catalog`.

### Task 2: Unified resumable conversion manifest

**Files:**
- Create: `Sources/ZombiesIOS/Models/GameDataManifest.swift`
- Create: `Sources/ZombiesIOS/Services/GameDataStore.swift`
- Modify: `Sources/ZombiesIOS/Services/RuntimeCachePolicy.swift`

**Interfaces:**
- Produces: versioned `GameDataManifest`, per-source hash/version records, atomic write/resume/invalidation APIs.

- [ ] Add tests for resume, stale converter version, source hash changes, interrupted writes, and no-copy source semantics.
- [ ] Implement manifest schema and atomic `.part` replacement.
- [ ] Verify interrupted conversion resumes without reprocessing valid records.
- [ ] Commit `feat: add resumable GameData manifest`.

### Task 3: Deterministic T6 stream relocation

**Files:**
- Modify: `Sources/ZombiesIOS/Services/T6PS3PayloadDecoder.swift`
- Create: `Sources/ZombiesIOS/Services/T6ZoneStreamCursor.swift`
- Modify: `Sources/ZombiesIOS/Services/T6ZoneAssetProbe.swift`
- Modify: `Sources/ZombiesIOS/Services/T6GfxSurfaceMeshExtractor.swift`

**Interfaces:**
- Produces: cursor-based `resolveInlinePayload(stream:alignment:length:)` for serialized `0xFFFFFFFF` pointers and typed asset payload slices.

- [ ] Add synthetic multi-stream fixtures covering alignment, nested inline pointers, overflow, truncated stream, and `0xFFFFFFFF` relocation.
- [ ] Verify current guessed/fallback offsets fail the relocation fixture.
- [ ] Implement stream cursor state and bounds-checked relocation.
- [ ] Route GfxWorld/GfxWorldDraw vertex/index extraction through the cursor.
- [ ] Verify Hijacked metadata counts can be resolved without guessed offsets.
- [ ] Commit `feat: resolve T6 inline zone streams`.

### Task 4: Typed T6 asset table decoding

**Files:**
- Create: `Sources/ZombiesIOS/Models/T6Asset.swift`
- Create: `Sources/ZombiesIOS/Services/T6AssetTableDecoder.swift`
- Modify: `Sources/ZombiesIOS/Services/T6FastFileInspector.swift`

**Interfaces:**
- Produces: typed records for world, images, materials, models, animations, sound, weapon defs, rawfiles/scripts, collision, entities, and mode metadata.

- [ ] Add sanitized asset-table fixtures for each supported class plus unknown-type preservation.
- [ ] Implement bounds-checked table parsing and pointer resolution.
- [ ] Verify unknown records remain indexed without corrupting stream state.
- [ ] Commit `feat: decode typed T6 asset tables`.

### Task 5: World geometry, materials, textures, and static models

**Files:**
- Modify: `Sources/ZombiesIOS/Services/T6GfxSurfaceMeshExtractor.swift`
- Modify: `Sources/ZombiesIOS/Services/T6MeshPreviewExtractor.swift`
- Create: `Sources/ZombiesIOS/Services/T6MaterialDecoder.swift`
- Create: `Sources/ZombiesIOS/Services/T6ImageDecoder.swift`
- Create: `Sources/ZombiesIOS/Services/T6StaticModelDecoder.swift`

**Interfaces:**
- Produces: real world vertex/index buffers, draw ranges, material/image bindings, static-model instances, and diagnostic fallback flags.

- [ ] Add fixtures validating vertex/index count, triangle bounds, material indices, UVs, normals, and instance transforms.
- [ ] Reject release-validation output if fallback bounds geometry is used.
- [ ] Implement real surface/static-model extraction and material/image binding.
- [ ] Verify Hijacked fixture reports expected world counts and non-fallback mesh output.
- [ ] Commit `feat: convert real T6 world rendering data`.

### Task 6: Collision, models, animation, weapons, entities, scripts, and audio

**Files:**
- Create: `Sources/ZombiesIOS/Services/T6CollisionDecoder.swift`
- Create: `Sources/ZombiesIOS/Services/T6ModelDecoder.swift`
- Create: `Sources/ZombiesIOS/Services/T6AnimationDecoder.swift`
- Create: `Sources/ZombiesIOS/Services/T6WeaponDecoder.swift`
- Create: `Sources/ZombiesIOS/Services/T6EntityDecoder.swift`
- Create: `Sources/ZombiesIOS/Services/T6RawfileScriptDecoder.swift`
- Create: `Sources/ZombiesIOS/Services/T6AudioDecoder.swift`

**Interfaces:**
- Produces: runtime collision meshes, model/skeleton/animation data, weapon definitions, entity graphs, script/rawfile payloads, and native-playable audio records.

- [ ] Add one synthetic fixture and one sanitized metadata fixture per subsystem.
- [ ] Implement strict parsers with explicit unsupported-field diagnostics.
- [ ] Store converted records through `GameDataStore`.
- [ ] Commit `feat: convert gameplay and audio asset classes`.

### Task 7: Unified mode/zone dependency loader

**Files:**
- Create: `Sources/ZombiesIOS/Models/BO2LaunchDescriptor.swift`
- Create: `Sources/ZombiesIOS/Services/BO2ZoneDependencyResolver.swift`
- Create: `Sources/ZombiesIOS/Services/BO2RuntimeLoader.swift`
- Modify: `Sources/ZombiesIOS/Services/TranzitRuntimeLoader.swift`

**Interfaces:**
- Consumes: `GameDataManifest` and typed assets.
- Produces: launchable Campaign, Multiplayer, and Zombies runtime scenes with common/global dependencies.

- [ ] Add dependency fixtures for one SP, one MP, and one ZM launch descriptor.
- [ ] Implement common/global + mode + map dependency resolution.
- [ ] Remove Tranzit-only assumptions from the main launch path while retaining compatibility adapter.
- [ ] Commit `feat: load BO2 zones across all game modes`.

### Task 8: Native runtime integration and controls

**Files:**
- Modify: `Sources/ZombiesIOS/ContentView.swift`
- Modify/create runtime view/renderer files under `Sources/ZombiesIOS/Views` and `Sources/ZombiesIOS/Services` following existing patterns.

**Interfaces:**
- Produces: map selector, conversion progress, runtime renderer, camera/player controls, collision, weapon input, audio, and diagnostic overlay.

- [ ] Add CI runtime fixture asserting startup reaches a rendered scene with non-zero real mesh draw calls.
- [ ] Integrate loader with Metal renderer and touch controls.
- [ ] Wire collision, weapon fire, entities/scripts sufficient for mode startup, and audio playback.
- [ ] Verify fallback-only render path fails release validation.
- [ ] Commit `feat: run converted BO2 GameData natively`.

### Task 9: Full-game conversion orchestration

**Files:**
- Create: `Sources/ZombiesIOS/Services/BO2FullGameConverter.swift`
- Modify: `Sources/ZombiesIOS/Services/ExternalGameFolderStore.swift`
- Modify: `Sources/ZombiesIOS/Services/DirectFolderImporter.swift`

**Interfaces:**
- Produces: resumable whole-dump conversion with progress per zone/asset class and persistent security-scoped folder bookmark.

- [ ] Add interruption/resume and partial-failure tests.
- [ ] Implement staged full-dump conversion without copying the source tree.
- [ ] Expose progress and actionable failure records.
- [ ] Commit `feat: orchestrate full BO2 conversion`.

### Task 10: CI, simulator validation, and unsigned IPA

**Files:**
- Modify: `.github/workflows/ios-build.yml`
- Create/modify: synthetic CI fixtures under `Sources/ZombiesIOS/Support`.
- Modify: `README.md` release criteria.

**Interfaces:**
- Produces: unsigned IPA artifact plus machine-readable validation report.

- [ ] Add build steps for XcodeGen, simulator smoke test, synthetic conversion fixture, and release-validation assertions.
- [ ] Ensure public artifacts contain no BO2 source or converted expressive assets.
- [ ] Build archive and package `Payload/*.app` as unsigned IPA.
- [ ] Verify artifact contains app/runtime code only and validation report passes.
- [ ] Commit `ci: build and validate full BO2 runtime IPA`.

### Task 11: Device-side full-game release gate

**Files:**
- Create: `docs/FULL_GAME_VALIDATION.md`
- Create: runtime validation report exporter in `Sources/ZombiesIOS/Services`.

**Interfaces:**
- Produces: device report recording conversion coverage and representative SP/MP/ZM playability checks.

- [ ] Run conversion against the user's complete local dump.
- [ ] Validate at least one Campaign map, Hijacked or another Multiplayer map, and one Zombies map with real geometry/materials, movement/collision, weapon fire, audio, and successful mode startup.
- [ ] Verify converter coverage has no required asset class left as placeholder-only.
- [ ] Only after these checks pass, mark the IPA playable/full-game-ready.
- [ ] Commit `test: add full-game device release gate`.
