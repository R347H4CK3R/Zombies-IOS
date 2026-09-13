# BO2 Quake III iOS Runtime Design

## Goal

Build a public native iOS application that uses a Quake III-derived runtime as the gameplay/rendering foundation and consumes converted Call of Duty: Black Ops II PS3 assets, beginning with Hijacked. The app must launch directly as an iOS app in LiveContainer and must not rely on a PS3 emulator.

## Scope

The first complete milestone is a native iOS build that:

- launches from the existing `R347H4CK3R/Zombies-IOS` app target;
- starts a Quake III-derived runtime instead of the current SceneKit gameplay path;
- consumes converted Hijacked data produced from the user's BO2 PS3 dump;
- renders Hijacked world geometry;
- loads collision and permits first-person movement through the world;
- loads BO2 map entities and multiplayer spawn points;
- exposes touch movement/look/jump/fire controls;
- builds an unsigned device IPA in GitHub Actions;
- validates the app in an iPhone Simulator job;
- publishes the unsigned IPA as both an Actions artifact and the `latest-build` public GitHub release asset.

This milestone does not claim full BO2 parity. Weapons, materials, textures, animation, audio, multiplayer rules, and Zombies systems are subsequent runtime layers built on the same architecture.

## Existing Code to Preserve

The repository already contains a substantial BO2/T6 conversion front end under `Sources/ZombiesIOS/Services`, including:

- `T6PS3PayloadDecoder.swift`
- `T6Salsa20.swift`
- `T6FastFileInspector.swift`
- `T6ZoneAssetProbe.swift`
- `T6GfxSurfaceMeshExtractor.swift`
- `T6GfxBoundsFallbackExtractor.swift`
- `T6MeshPreviewExtractor.swift`
- PS3 dump scanning, folder access, and runtime-cache utilities.

These remain the authoritative asset-decoding layer. The runtime migration occurs after decoded T6 data exists; the project must not discard the already-working PS3 fastfile/IPAK work.

## Runtime Architecture

### 1. T6 Asset Conversion Layer

The existing Swift T6 decoders remain responsible for reading the user's BO2 dump and extracting runtime-neutral data.

For Hijacked, conversion produces a deterministic runtime package containing:

- world vertex stream;
- index stream;
- surface table;
- material identifiers;
- entity lump;
- spawn points;
- collision representation;
- static-model placements where available;
- metadata describing source hashes, counts, coordinate conversion, and format version.

The package must be versioned so the runtime can reject incompatible cached conversions.

### 2. Quake III-Derived Core

Use a GPL-compatible Quake III-derived engine core because Quake III's renderer and BSP model support triangle-soup world surfaces, which map better to BO2 `GfxWorld` data than Quake 1 brush-only assumptions.

The Quake-derived source must live in a clearly isolated subtree such as `Engine/Quake3/`, with license attribution retained. No original commercial BO2 executable or PS3 binary is bundled or executed.

The engine layer exposes a small C interface to Swift/Objective-C:

- initialize runtime;
- load a converted Hijacked package;
- resize/render a frame;
- submit touch/controller input;
- update simulation;
- query runtime state/errors;
- shut down.

The engine is compiled into the iOS app target directly. It is not loaded as an emulator, JIT guest, or external app.

### 3. iOS Runtime Bridge

A new native bridge replaces SceneKit as the authoritative gameplay renderer.

Responsibilities:

- create the rendering surface;
- translate UIKit/SwiftUI touch controls into Quake-style user commands;
- manage app lifecycle and frame timing;
- route converted asset package paths to the C engine;
- report runtime errors to SwiftUI;
- preserve current external-folder access behavior where possible.

The existing SceneKit path can remain temporarily behind a diagnostic/fallback build flag during migration, but the production Hijacked path must use the Quake-derived runtime.

### 4. Hijacked Import Format

The converter must not require a traditional brush reconstruction pass. BO2 `GfxWorld` surfaces are treated as triangle geometry and translated into the runtime's internal world representation.

The converter must preserve:

- surface triangle ranges;
- material identity per surface;
- BO2 coordinates converted consistently to the runtime coordinate system;
- entity key/value pairs;
- spawn origins and angles;
- collision/world bounds;
- source provenance and checksums.

Where the Quake III BSP format is useful, generated triangle surfaces may be emitted as BSP-compatible draw surfaces. Where BSP compilation would lose information or create unnecessary complexity, the engine may load a custom `bo2world` package directly into Quake III renderer/collision structures. The preferred implementation is whichever preserves real BO2 geometry with less transformation.

## Copyright and Redistribution Boundary

The public repository must not contain the user's original BO2 `.ff`, `.ipak`, `.sabs`, extracted retail textures, audio, models, or other copyrighted retail content.

The repository may contain:

- original conversion/runtime source code;
- Quake III-derived GPL source with required notices;
- tests using synthetic fixtures;
- format specifications;
- generated metadata that contains no copyrighted binary asset payloads.

At runtime, the user supplies their own BO2 game dump. Converted retail assets stay outside source control and are generated locally or cached by the app.

## Repository Layout

Planned additions:

- `Engine/Quake3/` — Quake III-derived C/C++ engine source and retained license notices.
- `Sources/ZombiesIOS/EngineBridge/` — Swift/Objective-C/C bridge into the engine.
- `Sources/ZombiesIOS/Services/BO2RuntimePackage/` — deterministic runtime-package writer/reader.
- `Sources/ZombiesIOS/Views/QuakeGameplayView.swift` — native engine surface and touch-input host.
- `Tools/bo2_runtime_package/` — host-side validation/conversion helpers that do not contain retail assets.
- `Tools/tests/` — unit tests for package headers, coordinate conversion, entities, geometry counts, and redistribution audit.
- `docs/` — architecture, licensing, and user-owned-asset workflow documentation.

Existing T6 extraction files remain in place unless a focused refactor is required for shared package APIs.

## Data Flow

1. User grants access to their BO2 game folder.
2. Existing T6 decoder reads `mp_hijacked.ff` and associated assets from the user's dump.
3. Decoder reconstructs `GfxWorld`, entity data, and related asset references.
4. Runtime-package writer normalizes and stores the required data in app cache without copying the original game folder.
5. Quake runtime loads the converted package.
6. Renderer displays world geometry.
7. Collision system loads world collision representation.
8. Entity adapter creates spawn points and runtime entities.
9. SwiftUI touch controls submit movement/look/fire input to the engine.
10. The engine runs the game loop and renders directly in the native iOS app.

## Coordinate and Geometry Rules

- Preserve one documented BO2-to-engine axis/handedness transform across vertices, entity origins, angles, collision, and model placements.
- Preserve triangle winding after coordinate conversion.
- Keep geometry in 32-bit indices internally when needed; only downcast where a validated engine path requires it.
- Do not invent geometry when extraction fails.
- Conversion failure must be surfaced as a concrete error containing the failed stage and source asset.

## Touch Input

Reuse the current touch UI concepts while changing the sink from SceneKit camera/player state to engine user commands.

Minimum controls:

- left virtual stick: movement;
- right drag: view yaw/pitch;
- fire;
- aim;
- jump;
- reload.

Input must work at 60 Hz or the engine's current frame cadence without requiring hardware keyboard/controller input.

## Build and CI

Continue using XcodeGen and the existing GitHub Actions workflow.

CI must:

1. run redistribution-content audit;
2. run T6 structure/converter unit tests;
3. run runtime-package tests;
4. generate the Xcode project;
5. compile the Quake-derived engine for iOS Simulator;
6. build and launch the simulator app;
7. run a deterministic synthetic/redistributable runtime fixture so CI never requires retail BO2 data;
8. capture runtime diagnostics and screenshots;
9. build an unsigned `iphoneos` app;
10. package `ZombiesIOS-unsigned.ipa`;
11. upload the IPA as an Actions artifact;
12. create or replace the asset on the public `latest-build` GitHub release.

A successful CI build proves the native runtime and app integration compile/run; real Hijacked correctness is additionally validated against the user's locally converted assets and must not be falsely inferred from the synthetic fixture.

## Error Handling

Runtime and conversion errors use explicit stages such as:

- fastfile decrypt/decompress;
- zone parsing;
- GfxWorld extraction;
- vertex/index validation;
- entity conversion;
- collision conversion;
- runtime-package validation;
- engine initialization;
- renderer initialization;
- world load.

The UI presents a short error while a detailed diagnostic file is retained for debugging.

## Testing Strategy

- Unit tests for BO2/T6 byte-order and structure parsing.
- Unit tests for runtime-package serialization/deserialization.
- Unit tests for entity conversion and spawn mapping.
- Geometry tests using synthetic triangle surfaces with known bounds/winding.
- Engine bridge smoke tests.
- iPhone Simulator launch/render validation with redistributable synthetic data.
- Content-audit tests preventing retail BO2 payloads from entering the repository or built IPA.
- Real Hijacked validation performed against the user's supplied dump without committing those assets.

## Success Criteria for Milestone 1

Milestone 1 is complete when:

- the app no longer depends on SceneKit for the production Hijacked gameplay path;
- the Quake III-derived runtime initializes on iOS;
- a converted Hijacked package can be loaded;
- real Hijacked triangles are rendered;
- collision allows first-person traversal;
- BO2 entity/spawn data is loaded;
- touch movement/look/jump/fire reaches the engine;
- the iPhone Simulator validation job passes using a synthetic fixture;
- the unsigned device IPA builds successfully;
- GitHub exposes the IPA through both Actions artifacts and the public `latest-build` release;
- no retail BO2 asset payload is committed to the repository or bundled by CI.

## Follow-on Milestones

After Milestone 1, extend the same package/runtime interfaces in this order:

1. BO2 materials, UVs, and textures;
2. static XModels;
3. player weapon XModel and first working BO2 firearm;
4. audio from BO2 sound banks;
5. animation support;
6. multiplayer game-rule recreation;
7. Zombies AI, rounds, interactions, doors, perks, weapons, and scripting;
8. additional BO2 maps using the same converter.
