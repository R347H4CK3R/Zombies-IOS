# Tranzit Runtime Assets Design

## Goal

Make Zombies-IOS render a recognizable, playable Tranzit scene on iPhone using the user's own Call of Duty: Black Ops II PS3 dump as the authoritative source for world geometry, textures/materials, models, weapon assets, and other required runtime content. The reference screenshot defines the visual target only; the implementation must use actual decoded game assets rather than generated or substitute scenery.

The app must no longer treat successful asset counting, FastFile decoding, or process launch as sufficient proof of success. A build is considered ready only after automated validation demonstrates that the Tranzit gameplay scene renders real decoded content instead of a black frame.

## Scope

This design covers the first complete rendering path from a user-selected PS3 dump to a locally cached Tranzit runtime scene and an automated simulator render gate. It establishes the architecture needed for later gameplay work without attempting to recreate every BO2 system at once.

The implementation order is:

1. Selectively import only the files needed by Tranzit from the user's dump into a user-local runtime cache.
2. Decode the relevant T6 FastFiles and supporting containers from that cache.
3. Reconstruct GfxWorld geometry and material bindings.
4. Decode PS3 texture data into GPU-usable textures.
5. Instantiate world surfaces and static XModels/props.
6. Render a first-person weapon from the real asset set.
7. Apply basic BO2-like lighting/fog sufficient to make the imported scene readable and visually coherent.
8. Add a deterministic automated Tranzit render test that fails when the scene remains black or contains no imported geometry/materials.
9. Package an IPA only after the automated render gate passes.

Zombie AI, full scripting, round logic, bus behavior, complete animation systems, complete audio, and all map areas are explicitly outside this first rendering milestone unless required to prove the imported asset pipeline.

## User-local asset policy

The distributed repository and IPA must not contain copied BO2 game assets.

The user selects their own compatible PS3 dump through the iOS Files/document-picker flow. From that source, the application may create a **selective local dependency cache** containing only files required for the current playable Tranzit runtime. This cache exists only inside the user's app container and is never committed, uploaded to GitHub, attached to releases, or included in an IPA.

The importer must not mirror the entire selected game folder. It must copy only dependencies identified by the Tranzit import manifest. At minimum, the expected candidates include:

- `zm_transit.ff`
- `common_zm.ff` when referenced by the map's asset graph
- related Tranzit/shared FastFiles needed for world, material, image, XModel, weapon, animation, or script references
- referenced image/material containers when required by the selected PS3 build
- only the audio banks required by the runtime milestone when audio is later enabled

The app should store copied source files separately from decoded/converted runtime artifacts so either layer can be invalidated independently.

`docs/CONTENT_POLICY.md` must be revised to permit this narrow user-local selective cache while continuing to forbid bulk-copying, bundling, exporting, or redistributing proprietary assets.

## Architecture

### 1. Tranzit dependency manifest

Introduce a manifest model that describes exactly which source files the local Tranzit runtime needs.

Responsibilities:

- identify required files by normalized relative path and role
- store file size, hash, and source modification metadata for cache validation
- distinguish required, optional, and deferred dependencies
- record which decoded/runtime artifacts depend on each source file
- support future incremental additions without rescanning/copying the entire dump

The first implementation may seed known Tranzit container names and then refine the manifest from decoded references. Unknown or unresolved dependencies must be reported explicitly rather than silently ignored.

### 2. Selective import cache

Add a cache manager dedicated to user-local copied source content. It must:

- copy only manifest-selected files
- preserve relative paths under a dedicated Tranzit source-cache root
- use atomic replacement for individual files
- compare source metadata/hash before copying again
- skip unchanged files
- remove stale files no longer present in the current manifest
- expose progress and failure information to the UI
- never package cached content into build artifacts

The source-cache layer is separate from decoded expressive runtime caches. Clearing decoded artifacts must not force the source files to be recopied when their hashes still match.

### 3. T6 decode pipeline

Retain `T6PS3PayloadDecoder` as the FastFile decompression/decoding entry point, but move Tranzit loading away from speculative scanning of several candidate files on every launch.

The new pipeline should consume the imported manifest in deterministic order:

1. load the Tranzit primary zone
2. load required shared Zombies zones
3. build an asset-reference table
4. resolve GfxWorld, material, image, XModel, and weapon references by stable asset identity
5. emit typed decoded assets rather than only candidate counts/heuristic probes

Heuristic probing may remain as a diagnostic fallback but must not be considered a successful production decode path.

### 4. GfxWorld reconstruction

`T6GfxSurfaceMeshExtractor` currently produces a `T6RuntimeMesh`; the new world path must preserve surface/material boundaries instead of collapsing the scene into an untextured mesh.

The renderer-facing world representation needs:

- vertex positions
- normals/tangents when available
- UV coordinates
- index buffers
- surface ranges
- material identity per surface
- lightmap/secondary UV metadata when available
- world bounds
- source asset identity for diagnostics

A valid world decode must contain at least one renderable surface with nonzero triangles and a resolvable material reference.

`T6GfxBoundsFallbackExtractor` remains diagnostic recovery only. A bounds-recovery mesh must not satisfy the final visual acceptance gate.

### 5. Materials and PS3 textures

Introduce typed material/image decoding instead of treating textures as opaque payload bytes.

The texture path must:

- resolve material-to-image references from the decoded T6 asset graph
- identify PS3 image format, dimensions, mip layout, and swizzle/tiling rules
- convert supported image formats to a GPU-uploadable representation
- preserve alpha where required
- cache decoded texture products by source hash + decode-version key
- substitute an obvious diagnostic material only when an individual texture is unsupported

The final Tranzit render gate must fail if every world surface uses only diagnostic/fallback materials.

### 6. Static XModels and props

Add a typed XModel decode/render path for static map props required to make the starting area recognizable.

The first milestone should prioritize models referenced directly by the starting Tranzit area and avoid decoding the entire asset library unnecessarily. Each model must retain mesh sections and material references so textures can be bound correctly.

### 7. First-person weapon

The gameplay view should render an actual decoded BO2 weapon model when the required asset is present. The weapon system for this milestone only needs:

- model loading
- material binding
- first-person transform
- ADS transform
- basic recoil/fire transform feedback
- reload animation hook or simple placeholder motion if full animation decoding is not yet available

The weapon must come from the user's dump. A generated geometric gun or decorative screenshot is not an acceptable substitute for the final gate.

### 8. Native renderer integration

`NativeFPSSceneView` should receive a structured `T6RenderableWorld` rather than a single optional raw mesh.

The render package should include:

- world surfaces
- loaded textures/materials
- static props
- optional first-person weapon
- spawn/camera transform
- lighting/fog parameters
- diagnostics describing unresolved assets

The renderer must expose a small validation state back to SwiftUI, including:

- submitted triangle count
- number of surfaces drawn
- number of non-fallback materials bound
- number of textures resident
- rendered prop/model count
- whether a valid camera/spawn was applied

This state will be used by both on-device diagnostics and automated simulator validation.

## Gameplay view changes

`TranzitTouchGameplayView` must stop equating a decoded `T6RuntimeMesh` with a ready Tranzit world.

Its runtime state should progress through explicit phases such as:

- validating selected dump
- preparing selective cache
- copying changed dependencies
- decoding zones
- resolving assets
- building world surfaces
- decoding textures
- creating renderer package
- Tranzit ready
- failure with a concrete unresolved dependency or decode reason

The current green diagnostic banner can remain during development, but a successful status requires a real render package with geometry and non-fallback materials.

The existing move/look/ADS/fire/reload/jump touch controls remain in place.

## Cache layout

Use distinct directories under the app container so provenance and invalidation are explicit:

```text
Application Support/ZombiesIOS/
  SourceCache/
    Tranzit/
      manifest.json
      <selected source files preserving relative paths>
  RuntimeCache/
    Tranzit/
      world/
      materials/
      textures/
      models/
      weapons/
      index.json
```

`SourceCache` contains copied user-supplied source files. `RuntimeCache` contains decoded/converted user-local expressive derivatives. Neither directory may be copied into the app bundle or release artifact.

## Cache invalidation

Each manifest entry must include a content hash. Runtime artifacts must include:

- source content hash
- decoder version
- artifact schema version

A runtime artifact is reusable only when all three values match. Decoder changes therefore invalidate only affected artifacts, while unchanged source files remain in `SourceCache`.

## Error handling

Failures must surface a concrete phase and reason. Examples include:

- source bookmark unavailable
- required file missing
- copy failed
- source file changed while copying
- unsupported FastFile variant
- asset table parse failed
- GfxWorld not found
- world surfaces found but no valid material references
- texture format unsupported
- renderer received zero drawable surfaces

The app must not convert these states into a generic "data ready" message.

When only an optional asset fails, the runtime may continue with an explicit diagnostic fallback. Required world geometry/material failures must block the ready state.

## Automated simulator validation

The existing workflow's launch-only smoke test is insufficient.

Add a deterministic simulator test mode that can start directly in a Tranzit render fixture state without manual tapping. Because proprietary BO2 assets cannot be checked into GitHub, CI must separate two validation layers:

### Redistribution-safe CI gate

Runs on normal GitHub-hosted CI using synthetic fixtures and verifies:

- selective-cache logic
- manifest construction/invalidation
- decoder interfaces
- material/surface plumbing
- render-state instrumentation
- screenshot image-analysis logic
- rejection of an intentionally black scene
- rejection of a scene containing only fallback/diagnostic materials

### Real-asset validation gate

Runs only in an environment where a legitimate user-provided BO2 test dump has been made available locally and is not persisted as a repository artifact.

It must:

1. prepare/import the minimal Tranzit dependency set
2. launch the app directly into Tranzit
3. wait for the renderer-ready state with a bounded timeout
4. capture a simulator screenshot
5. query/assert renderer validation metrics
6. fail if no world surfaces are drawn
7. fail if no real material/texture is bound
8. fail if the gameplay viewport is effectively black
9. preserve only redistribution-safe diagnostics; do not upload screenshots containing proprietary rendered content to public CI artifacts by default

The IPA packaging/release job must depend on this real-asset render gate when that gate is being used to certify a user-ready build.

## Visual acceptance criteria

For the first user-ready Tranzit IPA, all of the following must be true:

- the gameplay viewport is not black
- actual decoded Tranzit world geometry is visible
- at least one real decoded BO2 material/texture is correctly bound to world geometry
- the scene uses the user's imported assets, not generated scenery
- camera orientation/spawn produces a readable starting-area view
- touch HUD and move/look controls remain usable
- renderer metrics confirm nonzero surfaces and triangles submitted
- the workflow's screenshot/metrics gate passes

The visual reference supplied by the user is a quality/composition target only. Pixel matching is not required, and generated imitation imagery must not be used to satisfy the gate.

## Performance targets

Initial correctness is more important than aggressive optimization, but the architecture must avoid re-decoding the whole map every launch.

Targets for the first stable milestone on iPhone 16 Plus-class hardware:

- unchanged source files are not recopied
- cached textures/models/world products are reused across launches
- runtime decoding is incremental and dependency-based
- memory ownership allows decoded FastFile buffers to be released once persistent render artifacts are built
- renderer should aim for 30 FPS or better in the starting-area milestone before broader map expansion

These are runtime engineering targets, not acceptance claims until measured.

## Testing strategy

Unit tests should cover:

- manifest normalization and dependency classification
- source-cache hash comparison and incremental copy behavior
- stale-cache cleanup
- runtime artifact version invalidation
- GfxWorld surface/material association
- texture metadata parsing for supported synthetic PS3-format fixtures
- renderer validation metrics
- black-frame image-analysis rejection
- fallback-only render rejection

Integration tests should cover:

- synthetic FastFile-like decoded asset graph -> renderable world package
- world surfaces + material/image references -> renderer submission
- cache reuse between two launches

Real-asset simulator testing is the final certification path and must remain local/private unless redistribution rights are documented.

## Files expected to change

Existing files likely to be modified:

- `Sources/ZombiesIOS/Views/TranzitTouchGameplayView.swift`
- `Sources/ZombiesIOS/Views/NativeFPSSceneView.swift`
- `Sources/ZombiesIOS/Services/DirectFolderImporter.swift`
- `Sources/ZombiesIOS/Services/ExternalGameFolderStore.swift`
- `Sources/ZombiesIOS/Services/RuntimeCachePolicy.swift`
- `Sources/ZombiesIOS/Services/T6PS3PayloadDecoder.swift`
- `Sources/ZombiesIOS/Services/T6GfxSurfaceMeshExtractor.swift`
- `.github/workflows/ios-build.yml`
- `docs/CONTENT_POLICY.md`

New focused components are expected for dependency manifests, selective source caching, typed T6 assets, texture decode, render packages, and render validation rather than continuing to expand one monolithic file.

## Non-goals for this milestone

- bundling BO2 assets inside the IPA
- uploading BO2 assets to GitHub Actions artifacts or releases
- copying the full PS3 game dump into the app container
- synthesizing a fake Tranzit scene to make screenshots look correct
- full BO2 engine emulation
- perfect visual parity with the PS3 before the first real textured world milestone
- complete Zombies gameplay systems before the render pipeline is proven

## Completion definition

This design is complete when the app can selectively import the minimum Tranzit dependencies from the user's PS3 dump, reuse those files locally, decode the actual T6 world/material/image/model data into a structured render package, display a recognizable textured Tranzit scene through the native iOS renderer, and block IPA certification when automated validation detects a black or fallback-only frame.
