# BO2 Quake iOS Clean Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a clean native iOS BO2 runtime that converts one complete user-owned PS3 dump into a deterministic native `GameData` tree, embeds that tree in a private self-contained IPA, and runs locally without a PS3 emulator or separate source-data folder.

**Architecture:** The public repository is code-only. A host-side converter discovers and converts the whole dump into versioned runtime packages; a Swift/Metal + Quake-derived C runtime consumes only those packages; a private packager embeds validated `GameData` into `BO2Quake.app` and creates the final unsigned IPA. Public CI uses synthetic fixtures only; retail-content validation is private/local.

**Tech Stack:** Swift 5, C99, Metal/MetalKit, XcodeGen, Python 3 conversion tooling/tests, GitHub Actions, AVFoundation/CoreAudio, GPLv2 Quake III-derived runtime attribution.

**Spec:** `docs/superpowers/specs/2026-09-13-bo2-quake-clean-rebuild-design.md`

## Global Constraints

- Deployment target remains iOS 17.0 or newer.
- Public GitHub content is code-only: no BO2 retail or converted retail assets.
- The converter accepts the complete BO2 PS3 dump root; no manual per-file conversion.
- Converted assets live under one versioned `GameData` tree and use deterministic hashes/manifests.
- The final user-specific IPA embeds `GameData` inside `Payload/BO2Quake.app/GameData/`.
- Production gameplay does not read PS3 FastFiles/IPAK/SABS directly.
- Production gameplay does not use SceneKit.
- Runtime world/model/entity coordinates share one documented BO2-to-iOS transform.
- Runtime indices are 32-bit or wider where required; no preview-era 65k vertex limit.
- Conversion failures and unsupported semantics are explicit completion blockers; never silently dropped.
- Development IPAs are never called the complete game.
- Final completion requires full-content private validation and launch without the original source dump.

---

### Task 1: Create clean project skeleton and code-only boundary

**Files:**
- Create: `Clean/BO2Quake/project.yml`
- Create: `Clean/BO2Quake/Sources/App/BO2QuakeApp.swift`
- Create: `Clean/BO2Quake/Sources/App/RootView.swift`
- Create: `Clean/BO2Quake/Engine/Quake3/README.md`
- Create: `Clean/BO2Quake/Engine/Quake3/COPYING.txt`
- Create: `Clean/BO2Quake/Tools/tests/test_clean_project_boundary.py`
- Create: `Clean/BO2Quake/Tools/content_audit.py`

**Interfaces:**
- Produces the clean XcodeGen app target, Metal dependency, C-engine source boundary, and public-content audit used by all later tasks.

- [ ] **Step 1: Write failing boundary test** requiring `BO2QuakeApp`, `MetalKit.framework`, `Engine/Quake3`, no `SceneKit.framework`, and a content-audit denylist for `.ff`, `.ipak`, `.sabs`, `.xpak`, retail signatures, and `GameData/` in public artifacts.
- [ ] **Step 2: Run** `python3 -m unittest Clean.BO2Quake.Tools.tests.test_clean_project_boundary -v` and verify failure because the clean project does not exist.
- [ ] **Step 3: Implement the minimal clean XcodeGen project and audit tool**. The app initially renders a code-only startup screen; no legacy Zombies-IOS production views are imported.
- [ ] **Step 4: Run boundary test and audit** against `Clean/BO2Quake`.
- [ ] **Step 5: Commit** `feat: create clean BO2 Quake iOS project`.

### Task 2: Full-dump discovery, hashing, resumable conversion ledger

**Files:**
- Create: `Clean/BO2Quake/Converter/bo2convert/__init__.py`
- Create: `Clean/BO2Quake/Converter/bo2convert/discovery.py`
- Create: `Clean/BO2Quake/Converter/bo2convert/ledger.py`
- Create: `Clean/BO2Quake/Converter/bo2convert/manifest.py`
- Create: `Clean/BO2Quake/Converter/bo2convert/cli.py`
- Create: `Clean/BO2Quake/Tools/tests/test_full_dump_discovery.py`

**Interfaces:**
- `discover_dump(root: Path) -> SourceInventory`
- `ConversionLedger.open(path)`, `is_current(source_hash, converter_version)`, `record_success(...)`, `record_failure(...)`
- CLI: `python3 -m bo2convert.cli --source <dump-root> --output <GameData-root>`

- [ ] **Step 1: Write synthetic-tree tests** covering recursive `.ff`, `.ipak`, `.sabs`, executable/support files, duplicate names, hashing, and unchanged-file resume.
- [ ] **Step 2: Run tests and verify RED**.
- [ ] **Step 3: Implement recursive discovery using SHA-256 streaming hashes**, deterministic relative paths, and manifest ordering.
- [ ] **Step 4: Implement resumable ledger** in `conversion-state.json`; failures remain explicit and do not mark files complete.
- [ ] **Step 5: Run tests** including interrupted/resumed conversion simulation.
- [ ] **Step 6: Commit** `feat: add full BO2 dump discovery and resume ledger`.

### Task 3: Versioned native GameData schemas and validator

**Files:**
- Create: `Clean/BO2Quake/SharedSchemas/gamedata.schema.json`
- Create: `Clean/BO2Quake/Converter/bo2convert/runtime_format.py`
- Create: `Clean/BO2Quake/Sources/Runtime/GameDataManifest.swift`
- Create: `Clean/BO2Quake/Sources/Runtime/GameDataLoader.swift`
- Create: `Clean/BO2Quake/Tools/tests/test_gamedata_format.py`

**Interfaces:**
- Produces `GameData/manifest.json` plus package families `worlds`, `materials`, `textures`, `models`, `animations`, `audio`, `weapons`, `entities`, `scripts`, `gamemodes`, `ui`.
- Every asset record has `id`, `kind`, `version`, `sourceHash`, `dependencies`, `payloads`, and validation state.

- [ ] **Step 1: Write failing format tests** for deterministic JSON, explicit versions, dependency graph, missing-payload rejection, and completion matrix.
- [ ] **Step 2: Run and verify RED**.
- [ ] **Step 3: Implement schema writer/reader and Swift loader** with bounds and hash validation.
- [ ] **Step 4: Generate a synthetic `GameData` fixture** and verify Python + Swift-facing contract fields agree.
- [ ] **Step 5: Commit** `feat: define versioned BO2 GameData format`.

### Task 4: Port verified T6 FastFile/XAsset/IPAK decoding into clean converter

**Files:**
- Create: `Clean/BO2Quake/Converter/bo2convert/t6/fastfile.py`
- Create: `Clean/BO2Quake/Converter/bo2convert/t6/salsa20.py`
- Create: `Clean/BO2Quake/Converter/bo2convert/t6/xchunk.py`
- Create: `Clean/BO2Quake/Converter/bo2convert/t6/xasset.py`
- Create: `Clean/BO2Quake/Converter/bo2convert/t6/ipak.py`
- Create: `Clean/BO2Quake/Tools/tests/test_t6_container_decoders.py`

**Interfaces:**
- `decode_fastfile(path) -> DecodedZone`
- `parse_xassets(zone) -> list[XAssetRecord]`
- `IPAKArchive(path).index()` and `.decode_entry(key)`

- [ ] **Step 1: Build synthetic signed/XChunk/IPAK fixtures** encoding the known T6 framing rules without retail data.
- [ ] **Step 2: Verify RED** for missing clean decoders.
- [ ] **Step 3: Port the already-validated PS3 Salsa20/XChunk and corrected LZO1X state machine** into focused Python modules.
- [ ] **Step 4: Implement XAsset table enumeration** with supported/unsupported asset-class reporting.
- [ ] **Step 5: Run decoder tests and fuzz malformed bounds/lengths**.
- [ ] **Step 6: Commit** `feat: port verified T6 container decoding`.

### Task 5: Complete GfxWorld, collision, UV and material extraction

**Files:**
- Create: `Clean/BO2Quake/Converter/bo2convert/t6/gfxworld.py`
- Create: `Clean/BO2Quake/Converter/bo2convert/t6/collision.py`
- Create: `Clean/BO2Quake/Converter/bo2convert/t6/materials.py`
- Create: `Clean/BO2Quake/Converter/bo2convert/t6/images.py`
- Create: `Clean/BO2Quake/Sources/Renderer/WorldRenderer.swift`
- Create: `Clean/BO2Quake/Sources/Renderer/WorldShaders.metal`
- Create: `Clean/BO2Quake/Tools/tests/test_world_material_pipeline.py`

**Interfaces:**
- Produces full 32-bit-indexed world meshes, preserved surface ranges, UV0/lightmap UV, normals/tangents, material IDs, collision primitives, lightmap/reflection metadata.
- Resolves `Material -> texture defs -> GfxImage -> IPAK entry`.

- [ ] **Step 1: Write synthetic GfxSurface/GfxWorld tests** with >65,535 vertices and multiple material ranges.
- [ ] **Step 2: Verify RED**.
- [ ] **Step 3: Implement complete surface extraction** using `[UInt32]` runtime indices and no preview cap; preserve source surface-to-material mapping.
- [ ] **Step 4: Decode packed world vertex attributes** into explicit runtime vertex structs.
- [ ] **Step 5: Convert collision structures** into versioned world-collision payloads; render triangles are fallback diagnostics only, never production collision when collision data exists.
- [ ] **Step 6: Implement Material/GfxImage dependency resolution and texture payload conversion** with explicit unsupported-format failures.
- [ ] **Step 7: Implement Metal world rendering** for opaque, alpha-tested, blended and lightmapped surfaces represented by converted material data.
- [ ] **Step 8: Run tests and synthetic iPhone simulator render gate**.
- [ ] **Step 9: Commit** `feat: add complete BO2 world and material pipeline`.

### Task 6: XModels, static placements and skeletal animation

**Files:**
- Create: `Clean/BO2Quake/Converter/bo2convert/t6/xmodel.py`
- Create: `Clean/BO2Quake/Converter/bo2convert/t6/xanim.py`
- Create: `Clean/BO2Quake/Sources/Renderer/ModelRenderer.swift`
- Create: `Clean/BO2Quake/Sources/Animation/Skeleton.swift`
- Create: `Clean/BO2Quake/Sources/Animation/AnimationPlayer.swift`
- Create: `Clean/BO2Quake/Tools/tests/test_model_animation_pipeline.py`

**Interfaces:**
- Converts XModel LOD meshes, skeleton/bones, material slots, collision metadata and static-model placements.
- Converts XAnim tracks, frame rates, looping and notify events.

- [ ] **Step 1: Write synthetic model/skeleton/animation fixtures and RED tests** for bone hierarchy, weighted vertices, placement transform and animation interpolation.
- [ ] **Step 2: Implement XModel and placement conversion** into `models/`.
- [ ] **Step 3: Implement XAnim conversion** into `animations/` with notify events.
- [ ] **Step 4: Implement Metal skinning/model rendering** and CPU runtime animation state/blending.
- [ ] **Step 5: Verify synthetic animated model renders in simulator**.
- [ ] **Step 6: Commit** `feat: add BO2 models and skeletal animation`.

### Task 7: SABS/SndBank conversion and runtime audio

**Files:**
- Create: `Clean/BO2Quake/Converter/bo2convert/t6/sabs.py`
- Create: `Clean/BO2Quake/Converter/bo2convert/t6/sound_alias.py`
- Create: `Clean/BO2Quake/Sources/Audio/BO2AudioEngine.swift`
- Create: `Clean/BO2Quake/Tools/tests/test_audio_pipeline.py`

**Interfaces:**
- Converts discovered sound banks to iOS-playable audio payloads and deterministic alias metadata.
- Runtime: `play(alias:)`, `play3D(alias:position:)`, `startLoop(alias:key:)`, `stopLoop(key:)`.

- [ ] **Step 1: Write synthetic bank/alias tests** for offsets, codecs, loop metadata and positional alias resolution.
- [ ] **Step 2: Verify RED**.
- [ ] **Step 3: Implement SABS/SndBank parser and supported codec conversion**; unsupported codecs are conversion failures.
- [ ] **Step 4: Implement AVAudioEngine-based runtime mixer** with one-shot, loop, 3D and music buses.
- [ ] **Step 5: Run unit tests plus simulator audio lifecycle smoke test**.
- [ ] **Step 6: Commit** `feat: add BO2 sound bank runtime`.

### Task 8: Data-driven weapons, combat, viewmodels and effects

**Files:**
- Create: `Clean/BO2Quake/Converter/bo2convert/t6/weapons.py`
- Create: `Clean/BO2Quake/Sources/Gameplay/WeaponSystem.swift`
- Create: `Clean/BO2Quake/Sources/Gameplay/CombatSystem.swift`
- Create: `Clean/BO2Quake/Sources/Gameplay/ViewmodelSystem.swift`
- Create: `Clean/BO2Quake/Tools/tests/test_weapon_combat_pipeline.py`

**Interfaces:**
- Converts WeaponDef/WeaponVariantDef values: ammo, magazines, modes, cadence, ADS, recoil/spread, damage/range, projectile/trace behavior, attachments, model/animation/effect/audio references.

- [ ] **Step 1: Write RED tests** for semi/auto/burst cadence, reload, ADS, recoil/spread, damage falloff, weapon switching and dependency resolution.
- [ ] **Step 2: Implement weapon conversion** with no production hard-coded fallback values.
- [ ] **Step 3: Implement runtime weapon state machine and world trace/projectile combat**.
- [ ] **Step 4: Bind viewmodel XModel/XAnim and source notify timing** to firing/reload actions.
- [ ] **Step 5: Bind muzzle/impact/audio aliases from converted data**.
- [ ] **Step 6: Run combat tests and simulator gameplay smoke test**.
- [ ] **Step 7: Commit** `feat: add data-driven BO2 weapon combat`.

### Task 9: MapEnts, triggers and translated script/event runtime

**Files:**
- Create: `Clean/BO2Quake/Converter/bo2convert/t6/mapents.py`
- Create: `Clean/BO2Quake/Converter/bo2convert/t6/scripts.py`
- Create: `Clean/BO2Quake/Sources/Gameplay/EntityWorld.swift`
- Create: `Clean/BO2Quake/Sources/Gameplay/ScriptEventRuntime.swift`
- Create: `Clean/BO2Quake/Tools/tests/test_entity_script_runtime.py`

**Interfaces:**
- Converts typed entities, spawn points, objectives, trigger volumes, script-models and event bindings.
- Runtime event VM exposes deterministic operations for spawn/despawn, trigger enter/exit/use, timers, variables, door/barrier state, objective state and supported gameplay events.

- [ ] **Step 1: Write RED tests** for MapEnts parsing, typed values, trigger relationships and a synthetic script-event program.
- [ ] **Step 2: Implement entity conversion and dependency resolution**.
- [ ] **Step 3: Implement translated event runtime** for semantics required by converted content; unresolved source semantics remain manifest blockers.
- [ ] **Step 4: Integrate trigger/collision/use interactions with player and weapons**.
- [ ] **Step 5: Commit** `feat: add BO2 entity and script event runtime`.

### Task 10: Multiplayer rules and Zombies AI/gameplay systems

**Files:**
- Create: `Clean/BO2Quake/Sources/GameModes/MultiplayerRules.swift`
- Create: `Clean/BO2Quake/Sources/GameModes/ZombiesRules.swift`
- Create: `Clean/BO2Quake/Sources/AI/NavWorld.swift`
- Create: `Clean/BO2Quake/Sources/AI/ZombieAI.swift`
- Create: `Clean/BO2Quake/Converter/bo2convert/t6/gamemodes.py`
- Create: `Clean/BO2Quake/Tools/tests/test_gamemode_ai.py`

**Interfaces:**
- Multiplayer: teams, spawn selection, scoring, death/respawn, objective/match state for supported local modes.
- Zombies: spawn directors, navigation, targeting, health/damage, rounds, barriers/doors, points/economy, buys, mystery-box-style interactions, perks/power and map event bindings where converted source data supports them.

- [ ] **Step 1: Write deterministic RED simulation tests** for multiplayer spawn/score/respawn and Zombies round/AI/economy transitions.
- [ ] **Step 2: Implement nav representation and path queries** backed by converted collision/navigation inputs.
- [ ] **Step 3: Implement local multiplayer rules state machine**.
- [ ] **Step 4: Implement Zombies AI and round/economy/interactions** driven by converted entities/scripts.
- [ ] **Step 5: Reject maps/modes with unresolved required script semantics in completion matrix**.
- [ ] **Step 6: Commit** `feat: add BO2 multiplayer and Zombies systems`.

### Task 11: Native HUD, menus, touch controls and saves

**Files:**
- Create: `Clean/BO2Quake/Sources/UI/GameHUD.swift`
- Create: `Clean/BO2Quake/Sources/UI/TouchControls.swift`
- Create: `Clean/BO2Quake/Sources/UI/MainMenu.swift`
- Create: `Clean/BO2Quake/Sources/App/SettingsStore.swift`
- Create: `Clean/BO2Quake/Tools/tests/test_ui_runtime_contract.py`

**Interfaces:**
- Touch controls: move, look, fire, ADS, jump, crouch/prone, reload, switch, interact, grenade/equipment, pause.
- HUD reads live runtime state only.

- [ ] **Step 1: Write source/runtime RED tests** for required control actions and live HUD bindings.
- [ ] **Step 2: Implement responsive iPhone touch layout** with safe-area handling and no external controller dependency.
- [ ] **Step 3: Implement main menu/content browser from `GameData/manifest.json`**.
- [ ] **Step 4: Implement settings/save state** for controls, sensitivity, audio and local progress/state where supported.
- [ ] **Step 5: Validate on iPhone 17 simulator dimensions**.
- [ ] **Step 6: Commit** `feat: add BO2 native UI and touch controls`.

### Task 12: One-action complete-dump converter orchestration

**Files:**
- Modify: `Clean/BO2Quake/Converter/bo2convert/cli.py`
- Create: `Clean/BO2Quake/Converter/bo2convert/pipeline.py`
- Create: `Clean/BO2Quake/Converter/bo2convert/report.py`
- Create: `Clean/BO2Quake/Tools/tests/test_full_conversion_pipeline.py`

**Interfaces:**
- One action converts the entire dump and emits `GameData/manifest.json`, `conversion-report.json`, and `conversion-state.json`.

- [ ] **Step 1: Write synthetic end-to-end RED test** with map, material, texture, model, animation, audio, weapon, entity/script and mode fixtures.
- [ ] **Step 2: Implement ordered dependency pipeline** with concurrency only across independent assets.
- [ ] **Step 3: Implement explicit completion matrix**; unsupported or unresolved required assets block `complete=true`.
- [ ] **Step 4: Implement resume/retry preserving successful unchanged outputs**.
- [ ] **Step 5: Run the end-to-end synthetic conversion twice and assert byte-identical outputs**.
- [ ] **Step 6: Commit** `feat: orchestrate complete BO2 dump conversion`.

### Task 13: Private self-contained IPA packager

**Files:**
- Create: `Clean/BO2Quake/Packager/package_private_ipa.py`
- Create: `Clean/BO2Quake/Tools/tests/test_private_packager.py`

**Interfaces:**
- Inputs: unsigned code-only `.app` or base IPA, validated `GameData`, `conversion-report.json`.
- Output: unsigned user-specific IPA containing `Payload/BO2Quake.app/GameData/`.

- [ ] **Step 1: Write RED packager tests** using synthetic app and GameData fixtures.
- [ ] **Step 2: Implement refusal rules**: `complete` must be true, hashes must match, no missing dependencies/failures, app bundle must be code-only before insertion.
- [ ] **Step 3: Embed `GameData` and rebuild IPA deterministically** while preserving executable/app metadata.
- [ ] **Step 4: Reopen produced IPA in test and verify every GameData manifest payload is present and hash-valid**.
- [ ] **Step 5: Commit** `feat: package private self-contained BO2 IPA`.

### Task 14: Public CI, private validation contract and completion gate

**Files:**
- Create: `Clean/BO2Quake/.github/workflows/ios-build.yml`
- Create: `Clean/BO2Quake/Tools/validate_completion.py`
- Create: `Clean/BO2Quake/README.md`
- Create: `Clean/BO2Quake/Tools/tests/test_completion_gate.py`

**Interfaces:**
- Public CI builds code-only app with synthetic GameData and rejects retail content.
- Private validator consumes real `conversion-report.json`, runtime smoke results and packaged IPA inspection.

- [ ] **Step 1: Write RED completion-gate tests** requiring every subsystem class to be `complete`, no placeholders/fallbacks, all required maps/modes launch status `pass`, and packaged IPA independence from source dump.
- [ ] **Step 2: Implement public Actions workflow**: Python tests, C runtime tests, XcodeGen, simulator Metal/gameplay validation, unsigned device build, content audit, code-only base IPA artifact.
- [ ] **Step 3: Implement `validate_completion.py`** that refuses final status if any required class/map/mode is unresolved.
- [ ] **Step 4: Document one-action source workflow** without requiring per-file user work.
- [ ] **Step 5: Run public CI to green and verify code-only artifact contains no `GameData` retail payloads**.
- [ ] **Step 6: Commit** `ci: enforce BO2 complete-game validation gate`.

### Task 15: Real full-dump private conversion and final IPA verification

**Files:**
- Uses converter, packager and validator from Tasks 1-14; no retail outputs are committed.

**Interfaces:**
- Input: the user's complete BO2 PS3 dump.
- Output: private self-contained unsigned IPA only after completion gate succeeds.

- [ ] **Step 1: Run the one-action converter against the complete supplied dump** and retain outputs outside the public repository.
- [ ] **Step 2: Inspect `conversion-report.json`**; for every failure, fix the responsible decoder/runtime subsystem and rerun until required classes have zero blockers.
- [ ] **Step 3: Run private runtime smoke suite** across every required map/mode in scope, including rendering, collision, models, audio, weapon interaction, scripts and game rules.
- [ ] **Step 4: Build the clean unsigned device app and run simulator code/runtime validation**.
- [ ] **Step 5: Run private packager** to embed validated `GameData` into `BO2Quake.app`.
- [ ] **Step 6: Inspect final IPA**: hashes, manifest coverage, executable presence, GameData completeness, absence of source `.ff/.ipak/.sabs` when converted runtime payloads are the intended output.
- [ ] **Step 7: Run completion validator** and require `complete=true` with zero blockers.
- [ ] **Step 8: Only after Step 7 passes, deliver the final unsigned IPA as the complete game.**
