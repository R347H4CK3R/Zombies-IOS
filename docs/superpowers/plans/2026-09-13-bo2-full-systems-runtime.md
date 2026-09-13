# BO2 Full Systems Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the native BO2 Quake iOS runtime from the validated Hijacked FPS core into a complete data-driven BO2 runtime stack covering full world geometry, materials/textures, static/dynamic models, audio, weapons/animation/damage, entities/triggers/scripts, AI, and game-mode state while continuing to consume only user-owned local PS3 data.

**Architecture:** Keep the existing user-local T6 FastFile/IPAK/SABS decoding boundary and Quake-derived C simulation core. Preserve native T6 coordinates and promote all runtime mesh references to 32-bit IDs/indices. Add focused decoders that convert retail data into versioned `BO2RuntimePackage` records stored under `runtime-expressive-cache`; the Metal host consumes only those normalized records. Gameplay systems are data-driven and must not embed retail BO2 assets in the repository or IPA.

**Tech Stack:** Swift 5, C99, Metal/MetalKit, XcodeGen, iOS 17+, Python unittest, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-13-bo2-quake3-ios-runtime-design.md`

## Global Constraints

- Deployment target remains iOS 17.0.
- User-owned BO2 files are read in place and never bulk-copied into the app container.
- No retail BO2 payload may be committed or bundled in CI/release artifacts.
- Converted expressive data must remain under `runtime-expressive-cache`.
- Production BO2 gameplay must not depend on SceneKit.
- Every subsystem must have a failing test first and pass the iPhone 17 simulator/device CI gate before merge.

---

### Task 8: Full 32-bit Hijacked world geometry

**Files:**
- Modify: `Sources/ZombiesIOS/Services/T6MeshPreviewExtractor.swift`
- Modify: `Sources/ZombiesIOS/Services/T6GfxSurfaceMeshExtractor.swift`
- Modify: `Sources/ZombiesIOS/Services/BO2RuntimePackage/BO2RuntimePackageWriter.swift`
- Modify: `Tools/tests/test_bo2_quake_primary_runtime.py`

**Interfaces:**
- `T6RuntimeMesh.indices` becomes `[UInt32]`.
- `T6GfxSurfaceMeshExtractor` may still parse PS3 source indices as `UInt16`, but remaps each accepted surface into 32-bit runtime indices without a 65,535-vertex ceiling.

- [ ] Add a failing contract test requiring `[UInt32]`, forbidding `maxOutputVertices = 65_000`, and requiring the production extractor to append `UInt32` indices.
- [ ] Run `python3 -m unittest Tools.tests.test_bo2_quake_primary_runtime -v` and verify RED.
- [ ] Promote `T6RuntimeMesh.indices` and production extraction to `UInt32`; retain source `be16` reads because the T6 index buffer itself is 16-bit.
- [ ] Run the full Python/native test suite and Xcode compile.
- [ ] Commit `feat: preserve full 32-bit BO2 world geometry`.

### Task 9: Surface ranges, UV channels, and material IDs

**Files:**
- Modify: `Sources/ZombiesIOS/Services/T6MeshPreviewExtractor.swift`
- Modify: `Sources/ZombiesIOS/Services/T6GfxSurfaceMeshExtractor.swift`
- Modify: `Sources/ZombiesIOS/Services/BO2RuntimePackage/BO2RuntimePackage.swift`
- Modify: `Sources/ZombiesIOS/Services/BO2RuntimePackage/BO2RuntimePackageWriter.swift`
- Create: `Tools/tests/test_bo2_material_geometry_contract.py`

**Interfaces:**
- Produce `BO2RuntimeSurface(firstIndex:indexCount:materialSlot:)` records.
- Produce per-vertex UV0 and optional lightmap UV fields in runtime vertices.
- Preserve one surface record per accepted T6 `GfxSurface`.

- [ ] Add failing tests for surface ranges, UV storage, and non-flattened material slots.
- [ ] Validate the packed T6 world-vertex stream offsets against authoritative T6 structure/reference data before coding.
- [ ] Decode UV channels from the correct stream/format and emit runtime surfaces.
- [ ] Verify range coverage equals runtime index count and no surface overlaps.
- [ ] Commit `feat: preserve BO2 world surfaces and UVs`.

### Task 10: Material/GfxImage/IPAK texture binding

**Files:**
- Modify: `Sources/ZombiesIOS/Services/T6IPAKArchive.swift`
- Create: `Sources/ZombiesIOS/Services/T6MaterialCatalog.swift`
- Create: `Sources/ZombiesIOS/Services/T6TextureTranscoder.swift`
- Modify: `Sources/ZombiesIOS/Services/BO2MapRuntimeLoader.swift`
- Modify: `Sources/ZombiesIOS/Views/QuakeGameplayView.swift`
- Create: `Tools/tests/test_bo2_texture_pipeline_contract.py`

**Interfaces:**
- Resolve T6 material/image metadata to IPAK keys.
- Decode/transcode supported BO2 texture payloads into iOS/Metal-consumable cached textures.
- Bind runtime surfaces to Metal textures with a deterministic fallback material only for genuinely unsupported material features.

- [ ] Add failing material/image/IPAK binding tests using synthetic metadata and LZO vectors.
- [ ] Implement catalog parsing and key resolution.
- [ ] Implement bounded texture transcode/cache under expressive runtime cache.
- [ ] Add Metal texture table and per-surface draws.
- [ ] Validate CI fixture textured draw plus retail-free artifact audit.
- [ ] Commit `feat: render BO2 materials and IPAK textures`.

### Task 11: XModel and static/dynamic world models

**Files:**
- Create: `Sources/ZombiesIOS/Services/T6XModelDecoder.swift`
- Create: `Sources/ZombiesIOS/Services/BO2RuntimePackage/BO2RuntimeModel.swift`
- Modify: `BO2RuntimePackage.swift`
- Modify: `BO2MapRuntimeLoader.swift`
- Modify: `QuakeGameplayView.swift`
- Create: `Tools/tests/test_bo2_xmodel_contract.py`

**Interfaces:**
- Decode model LOD geometry, materials, local bounds, placement transform, and collision proxy.
- Package model instances separately from world BSP/surface geometry.

- [ ] Add failing synthetic XModel/placement tests.
- [ ] Decode one rigid LOD and expand to all supported rigid/skinned surfaces.
- [ ] Resolve model materials through Task 10 catalog.
- [ ] Render instanced static models and feed collision proxies to native runtime.
- [ ] Commit `feat: add BO2 XModel world instances`.

### Task 12: SABS/SoundBank audio

**Files:**
- Create: `Sources/ZombiesIOS/Services/T6SABSAudioBank.swift`
- Create: `Sources/ZombiesIOS/Audio/BO2AudioEngine.swift`
- Modify: `BO2MapRuntimeLoader.swift`
- Create: `Tools/tests/test_bo2_audio_contract.py`

**Interfaces:**
- Index `mpl_hijacked.all.sabs` without copying the source bank.
- Resolve decoded sound aliases/events to bounded cached PCM/CAF assets and play them via native iOS audio.

- [ ] Add failing bank-index and alias-resolution tests with synthetic headers.
- [ ] Implement safe SABS index reader and codec dispatch.
- [ ] Add local cache and AVAudioEngine playback.
- [ ] Wire weapon, reload, impact, ambient, and entity-event hooks.
- [ ] Commit `feat: add BO2 SABS audio runtime`.

### Task 13: Weapon definitions, animation, damage, inventory

**Files:**
- Create: `Sources/ZombiesIOS/Services/T6WeaponDefDecoder.swift`
- Create: `Engine/Quake3/zq3_combat.h`
- Create: `Engine/Quake3/zq3_combat.c`
- Modify: `zq3_runtime.h/.c`
- Modify: `QuakeRuntimeController.swift`
- Modify: `QuakeGameplayView.swift`
- Create: `Tools/tests/test_bo2_combat_contract.py`

**Interfaces:**
- Runtime weapon records include fire mode, RPM, magazine, reserve, reload timings, damage/range, ADS FOV, recoil/spread, model/animation/sound refs.
- Native combat state owns inventory, firing, reload, hitscan/projectile events, damage and death events.

- [ ] Add failing deterministic combat tests.
- [ ] Decode weapon records from user-local FastFile data.
- [ ] Replace hard-coded weapon values with runtime records.
- [ ] Add animation-state timeline and first-person weapon transform hooks.
- [ ] Add damageable entity interface and hit events.
- [ ] Commit `feat: add data-driven BO2 combat system`.

### Task 14: Map triggers, script entities, objectives, and game-state VM

**Files:**
- Create: `Sources/ZombiesIOS/Services/T6TriggerDecoder.swift`
- Create: `Engine/Quake3/zq3_gameplay_vm.h`
- Create: `Engine/Quake3/zq3_gameplay_vm.c`
- Modify: `BO2EntityParser.swift`
- Modify: `BO2RuntimePackage.swift`
- Create: `Tools/tests/test_bo2_gameplay_vm_contract.py`

**Interfaces:**
- Convert MapTriggers/entity spawnvars into normalized trigger volumes/actions.
- Execute an explicit supported gameplay-opcode/state-machine layer; unsupported retail script bytecode is reported, never silently fabricated.

- [ ] Add failing trigger enter/leave/use/objective tests.
- [ ] Decode trigger geometry and entity links.
- [ ] Implement deterministic gameplay event/state VM.
- [ ] Map supported multiplayer/Hijacked objectives and interaction entities into VM events.
- [ ] Commit `feat: add BO2 triggers and gameplay state VM`.

### Task 15: AI navigation and game modes

**Files:**
- Create: `Engine/Quake3/zq3_ai.h`
- Create: `Engine/Quake3/zq3_ai.c`
- Create: `Sources/ZombiesIOS/Services/T6PathNodeDecoder.swift`
- Create: `Sources/ZombiesIOS/Services/BO2GameModeCatalog.swift`
- Create: `Tools/tests/test_bo2_ai_modes_contract.py`

**Interfaces:**
- Decode T6 path nodes into runtime navigation graph.
- Native AI owns perception, path requests, movement steering, combat decisions and state.
- Game-mode catalog configures spawn/team/score/round/objective rules from decoded/user-local data.

- [ ] Add failing graph/path/AI state tests.
- [ ] Decode path nodes and links.
- [ ] Implement A* pathing plus basic BO2-style combat state machine.
- [ ] Implement DM/TDM score/spawn loop first, then round/objective and Zombies round/spawn state on the same VM/event primitives.
- [ ] Commit `feat: add BO2 AI navigation and game modes`.

### Task 16: Full-system CI, validation, merge, and IPA publication

**Files:**
- Modify: `.github/workflows/ios-build.yml`
- Modify: `Tools/tests/*`
- Modify: `README.md`

**Interfaces:**
- CI remains retail-free, using synthetic fixture packages to exercise each subsystem.
- Real user-owned Hijacked validation occurs on-device through the same package interfaces.

- [ ] Run all Python and native C tests.
- [ ] Build and launch on fresh iPhone 17 simulator; require Metal diagnostics and deterministic movement/combat/material/model/audio fixture events.
- [ ] Build unsigned device IPA and audit its contents for retail data.
- [ ] Merge only after all gates pass.
- [ ] Verify `latest-build` contains the implementation commit and unsigned IPA.
- [ ] Commit `ci: validate complete BO2 runtime systems`.
