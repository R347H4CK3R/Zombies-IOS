# Tranzit Runtime Assets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Zombies-IOS selectively cache only the Tranzit dependencies from the user's BO2 PS3 dump, decode those real assets into a structured textured render package, render a recognizable Tranzit scene on iPhone, and refuse IPA certification when the gameplay viewport is black or fallback-only.

**Architecture:** Split the work into five focused layers: a manifest-driven source cache, typed T6 asset decoding, renderer-facing world/material/model packages, gameplay state orchestration, and CI/render certification. Proprietary BO2 content remains user-local at runtime; the repository, tests, and public CI use only synthetic fixtures. The native gameplay renderer consumes `T6RenderableWorld` instead of a single heuristic mesh, and exposes validation metrics that are used by both the UI and automated screenshot gates.

**Tech Stack:** Swift 5, SwiftUI, SceneKit/Metal-backed native rendering already used by `NativeFPSSceneView`, XcodeGen, XCTest, Python 3 for screenshot analysis in CI, GitHub Actions, existing T6 zlib/Salsa20 decode bridge.

**Spec:** `docs/superpowers/specs/2026-09-12-tranzit-runtime-assets-design.md`

## Global Constraints

- iOS deployment target remains 17.0.
- Target device family remains iPhone only.
- BO2/PS3 assets must never be committed, bundled into the IPA, uploaded to GitHub artifacts, or included in releases.
- The app may copy only manifest-selected Tranzit dependencies into its own user-local source cache; it must never mirror the full game dump.
- `SourceCache` and `RuntimeCache` remain separate and independently invalidatable.
- The final Tranzit ready state requires real world geometry plus at least one non-fallback material/texture.
- `T6GfxBoundsFallbackExtractor` is diagnostic-only and must not satisfy visual certification.
- A black frame, zero drawable surfaces, or fallback-only materials must fail certification.
- Synthetic fixtures are required for repository tests; real-asset certification is local/private only.
- The first milestone prioritizes Tranzit starting-area world, materials/textures, static props, one first-person weapon, touch HUD, and render validation; full zombie AI/round scripting is out of scope.

---

## File Structure

### New files

- `Sources/ZombiesIOS/Models/TranzitDependencyManifest.swift` — source dependency roles, hashes, required/optional status, runtime artifact dependency metadata.
- `Sources/ZombiesIOS/Services/TranzitDependencyResolver.swift` — builds deterministic dependency manifests from a selected dump and decoded references.
- `Sources/ZombiesIOS/Services/TranzitSourceCache.swift` — incremental selective copy, stale cleanup, hash verification, cache root management.
- `Sources/ZombiesIOS/Models/T6TypedAssets.swift` — typed asset identities and decoded GfxWorld/material/image/XModel/weapon structures.
- `Sources/ZombiesIOS/Models/T6RenderableWorld.swift` — renderer-facing surfaces, materials, textures, props, weapon, camera, lighting, validation diagnostics.
- `Sources/ZombiesIOS/Services/T6AssetTableDecoder.swift` — deterministic typed asset table decode from T6 payloads.
- `Sources/ZombiesIOS/Services/T6PS3TextureDecoder.swift` — image metadata parsing and supported PS3 texture conversion.
- `Sources/ZombiesIOS/Services/T6RenderableWorldBuilder.swift` — resolves typed decoded assets into `T6RenderableWorld`.
- `Sources/ZombiesIOS/Services/RenderValidation.swift` — renderer metrics model and frame acceptance rules.
- `Tests/ZombiesIOSTests/TranzitDependencyManifestTests.swift`
- `Tests/ZombiesIOSTests/TranzitSourceCacheTests.swift`
- `Tests/ZombiesIOSTests/T6AssetTableDecoderTests.swift`
- `Tests/ZombiesIOSTests/T6PS3TextureDecoderTests.swift`
- `Tests/ZombiesIOSTests/T6RenderableWorldBuilderTests.swift`
- `Tests/ZombiesIOSTests/RenderValidationTests.swift`
- `Tools/render_gate.py` — redistribution-safe screenshot black-frame/fallback gate.
- `Tools/tests/test_render_gate.py`

### Existing files to modify

- `project.yml` — add the XCTest target and fixture resources.
- `Sources/ZombiesIOS/Services/DirectFolderImporter.swift` — route full-folder import behavior into manifest selection rather than bulk copying.
- `Sources/ZombiesIOS/Services/ExternalGameFolderStore.swift` — preserve source bookmark/reference and expose safe scoped access for cache preparation.
- `Sources/ZombiesIOS/Services/RuntimeCachePolicy.swift` — add explicit `SourceCache/Tranzit` and `RuntimeCache/Tranzit` roots and artifact version keys.
- `Sources/ZombiesIOS/Services/T6PS3PayloadDecoder.swift` — expose deterministic decoded zone products without forcing heuristic scanning.
- `Sources/ZombiesIOS/Services/T6GfxSurfaceMeshExtractor.swift` — preserve per-surface ranges, UVs, and material identities.
- `Sources/ZombiesIOS/Services/T6GfxBoundsFallbackExtractor.swift` — mark recovery output non-certifying.
- `Sources/ZombiesIOS/Services/TranzitRuntimeLoader.swift` — orchestrate source cache, typed decoding, world building, and cache reuse.
- `Sources/ZombiesIOS/Views/TranzitTouchGameplayView.swift` — explicit loading phases and `T6RenderableWorld` state.
- `Sources/ZombiesIOS/Views/NativeFPSSceneView.swift` — consume `T6RenderableWorld`, bind textures/materials, draw props/weapon, emit validation metrics.
- `Sources/ZombiesIOS/ContentView.swift` — expose deterministic simulator test mode entry point.
- `docs/CONTENT_POLICY.md` — permit narrow user-local selective source cache while preserving redistribution restrictions.
- `.github/workflows/ios-build.yml` — add test target, screenshot gate, and conditional real-asset certification dependency before IPA packaging.

---

### Task 1: Add XCTest target and selective-cache manifest model

**Files:**
- Modify: `project.yml`
- Create: `Sources/ZombiesIOS/Models/TranzitDependencyManifest.swift`
- Create: `Tests/ZombiesIOSTests/TranzitDependencyManifestTests.swift`

**Interfaces:**
- Produces: `TranzitDependencyManifest`, `TranzitDependency`, `TranzitDependencyRole`, `TranzitDependencyRequirement`.
- `TranzitDependency.normalizedRelativePath` is the canonical key consumed by later cache and decoder tasks.

- [ ] **Step 1: Add an XCTest target to `project.yml`**

Add:

```yaml
  ZombiesIOSTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - Tests/ZombiesIOSTests
    dependencies:
      - target: ZombiesIOS
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.r347h4ck3r.zombiesios.tests
```

- [ ] **Step 2: Write failing manifest normalization tests**

Create tests that assert `PS3_GAME/USRDIR/zone/all/../all/zm_transit.ff` normalizes to a stable relative path, duplicate entries collapse by normalized path, and required entries outrank optional duplicates.

```swift
func testManifestNormalizesAndDeduplicatesPaths() throws {
    let entries = [
        TranzitDependency(relativePath: "PS3_GAME/USRDIR/zone/all/zm_transit.ff", role: .zone, requirement: .required, byteCount: 10, sha256: "a", modifiedAt: nil),
        TranzitDependency(relativePath: "PS3_GAME/USRDIR/zone/all/./zm_transit.ff", role: .zone, requirement: .optional, byteCount: 10, sha256: "a", modifiedAt: nil)
    ]
    let manifest = TranzitDependencyManifest(entries: entries)
    XCTAssertEqual(manifest.entries.count, 1)
    XCTAssertEqual(manifest.entries[0].requirement, .required)
    XCTAssertEqual(manifest.entries[0].normalizedRelativePath, "PS3_GAME/USRDIR/zone/all/zm_transit.ff")
}
```

- [ ] **Step 3: Generate the project and run the test to verify failure**

Run:

```bash
xcodegen generate
xcodebuild -project ZombiesIOS.xcodeproj -scheme ZombiesIOSTests -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

Expected: compile failure because manifest types do not yet exist.

- [ ] **Step 4: Implement the manifest types**

Use `Codable`, `Hashable`, and deterministic sorting. The initializer must normalize `.`/`..`, reject absolute traversal outside the selected root, collapse duplicates, and prefer `.required` over `.optional` over `.deferred`.

- [ ] **Step 5: Run the XCTest target and commit**

Expected: PASS.

```bash
git add project.yml Sources/ZombiesIOS/Models/TranzitDependencyManifest.swift Tests/ZombiesIOSTests/TranzitDependencyManifestTests.swift
git commit -m "feat: add Tranzit dependency manifest"
```

---

### Task 2: Implement manifest-driven selective source caching

**Files:**
- Create: `Sources/ZombiesIOS/Services/TranzitSourceCache.swift`
- Create: `Sources/ZombiesIOS/Services/TranzitDependencyResolver.swift`
- Modify: `Sources/ZombiesIOS/Services/RuntimeCachePolicy.swift`
- Modify: `Sources/ZombiesIOS/Services/DirectFolderImporter.swift`
- Modify: `Sources/ZombiesIOS/Services/ExternalGameFolderStore.swift`
- Create: `Tests/ZombiesIOSTests/TranzitSourceCacheTests.swift`
- Modify: `docs/CONTENT_POLICY.md`

**Interfaces:**
- Consumes: `TranzitDependencyManifest` from Task 1.
- Produces: `TranzitSourceCache.prepare(manifest:sourceRoot:) async throws -> TranzitSourceCacheResult`.
- Produces: `TranzitDependencyResolver.initialManifest(sourceRoot:) async throws -> TranzitDependencyManifest`.

- [ ] **Step 1: Write failing incremental-copy tests**

Use temporary directories and tiny synthetic files. Cover: first copy, unchanged skip, changed source recopy, stale cache removal, required missing failure, optional missing diagnostic.

```swift
func testPrepareCopiesOnlyManifestEntriesAndReusesUnchangedFiles() async throws {
    // create source/a.ff and source/b.ff; manifest only names a.ff
    // call prepare twice
    // assert only a.ff exists in cache and second result reports copied == 0, reused == 1
}
```

- [ ] **Step 2: Run the specific test and confirm failure**

Expected: compile failure because `TranzitSourceCache` does not exist.

- [ ] **Step 3: Extend `RuntimeCachePolicy` with deterministic cache roots**

Add functions returning:

```swift
static func tranzitSourceCacheRoot(fileManager: FileManager = .default) throws -> URL
static func tranzitRuntimeCacheRoot(fileManager: FileManager = .default) throws -> URL
```

They must resolve beneath `Application Support/ZombiesIOS/SourceCache/Tranzit` and `Application Support/ZombiesIOS/RuntimeCache/Tranzit` respectively.

- [ ] **Step 4: Implement `TranzitSourceCache`**

Requirements:

```swift
struct TranzitSourceCacheResult {
    let copied: [TranzitDependency]
    let reused: [TranzitDependency]
    let removedRelativePaths: [String]
    let missingOptional: [TranzitDependency]
}
```

Copy each selected file to a temporary sibling, verify byte count and SHA-256, then atomically replace destination. Do not enumerate/copy unrelated source files.

- [ ] **Step 5: Implement initial dependency resolution**

Seed known Tranzit candidates in deterministic order beginning with `zm_transit.ff`, then shared Zombies zones such as `common_zm.ff` when present. Record absent optional candidates without failing. Later tasks will enrich the manifest from decoded references.

- [ ] **Step 6: Remove bulk-copy behavior from `DirectFolderImporter`**

Keep the folder-picker/import entry point but route it to manifest preparation. Any method that recursively copies the selected root must be deleted or made unreachable from production flow.

- [ ] **Step 7: Keep `ExternalGameFolderStore` as source bookmark authority**

Expose scoped access as a closure or async helper so the source cache can copy selected files while the security-scoped URL is active.

- [ ] **Step 8: Revise `docs/CONTENT_POLICY.md`**

Change the blanket prohibition on app-container copying to explicitly allow only manifest-selected user-local runtime source copies under `SourceCache`, while retaining the ban on mirroring the full dump and on redistribution/export.

- [ ] **Step 9: Run tests and commit**

```bash
xcodebuild -project ZombiesIOS.xcodeproj -scheme ZombiesIOSTests -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
git add Sources/ZombiesIOS/Services docs/CONTENT_POLICY.md Tests/ZombiesIOSTests/TranzitSourceCacheTests.swift
git commit -m "feat: add selective Tranzit source cache"
```

---

### Task 3: Add typed T6 asset table decoding

**Files:**
- Create: `Sources/ZombiesIOS/Models/T6TypedAssets.swift`
- Create: `Sources/ZombiesIOS/Services/T6AssetTableDecoder.swift`
- Modify: `Sources/ZombiesIOS/Services/T6PS3PayloadDecoder.swift`
- Modify: `Sources/ZombiesIOS/Services/T6ZoneAssetProbe.swift`
- Create: `Tests/ZombiesIOSTests/T6AssetTableDecoderTests.swift`

**Interfaces:**
- Produces: `T6AssetID`, `T6AssetRecord`, `T6DecodedZone`, `T6GfxWorldAsset`, `T6MaterialAsset`, `T6ImageAsset`, `T6XModelAsset`, `T6WeaponAsset`.
- Produces: `T6AssetTableDecoder.decode(zoneName:payload:) throws -> T6DecodedZone`.

- [ ] **Step 1: Write a synthetic decoded-zone fixture test**

Build a byte fixture with a small deterministic asset table containing one world, one material, one image, and one model reference. Assert stable IDs and reference resolution.

- [ ] **Step 2: Run and confirm failure**

Expected: compile failure because typed decoder does not exist.

- [ ] **Step 3: Define typed asset identities and records**

Use a stable combination of zone name, asset type, and decoded asset index/offset. Asset identity must not depend on in-memory pointer addresses.

- [ ] **Step 4: Implement deterministic table parsing**

Move production success away from `candidateAssetCount` heuristics. Unsupported/unknown asset types should be retained as `.unknown(typeID:rawRange:)` rather than silently dropped.

- [ ] **Step 5: Update `T6PS3PayloadDecoder` to expose decoded payload plus zone metadata**

Do not break existing callers yet; add a typed decoding entry point that later loader code can migrate to.

- [ ] **Step 6: Keep `T6ZoneAssetProbe` diagnostic-only**

Document and enforce that probe counts can appear in diagnostics but cannot make a zone certifiably ready.

- [ ] **Step 7: Run tests and commit**

```bash
git add Sources/ZombiesIOS/Models/T6TypedAssets.swift Sources/ZombiesIOS/Services/T6AssetTableDecoder.swift Sources/ZombiesIOS/Services/T6PS3PayloadDecoder.swift Sources/ZombiesIOS/Services/T6ZoneAssetProbe.swift Tests/ZombiesIOSTests/T6AssetTableDecoderTests.swift
git commit -m "feat: decode typed T6 asset tables"
```

---

### Task 4: Preserve GfxWorld surfaces, UVs, and material bindings

**Files:**
- Modify: `Sources/ZombiesIOS/Services/T6GfxSurfaceMeshExtractor.swift`
- Modify: `Sources/ZombiesIOS/Services/T6GfxBoundsFallbackExtractor.swift`
- Create: `Tests/ZombiesIOSTests/T6RenderableWorldBuilderTests.swift`

**Interfaces:**
- Produces: `T6WorldSurface` values containing vertex/index ranges, UVs, normals where available, and `materialID`.
- `T6GfxBoundsFallbackExtractor` output must expose `isDiagnosticRecovery == true`.

- [ ] **Step 1: Write a failing synthetic surface/material association test**

Construct two surfaces in a fixture with distinct material IDs and UV ranges. Assert both survive extraction independently and index ranges do not overlap incorrectly.

- [ ] **Step 2: Run the test and confirm current extractor cannot satisfy it**

Expected: failure because current output collapses the world to one mesh without certifiable material boundaries.

- [ ] **Step 3: Refactor extractor output**

Preserve existing low-level byte-order parsing, but emit surface records with:

```swift
struct T6WorldSurface {
    let vertices: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let uvs: [SIMD2<Float>]
    let indices: [UInt32]
    let materialID: T6AssetID?
    let sourceSurfaceIndex: Int
}
```

- [ ] **Step 4: Mark bounds fallback non-certifying**

Any world built from bounds recovery alone must report `usesDiagnosticGeometry = true`.

- [ ] **Step 5: Run tests and commit**

```bash
git add Sources/ZombiesIOS/Services/T6GfxSurfaceMeshExtractor.swift Sources/ZombiesIOS/Services/T6GfxBoundsFallbackExtractor.swift Tests/ZombiesIOSTests/T6RenderableWorldBuilderTests.swift
git commit -m "feat: preserve T6 world surface materials"
```

---

### Task 5: Decode PS3 texture metadata and build material products

**Files:**
- Create: `Sources/ZombiesIOS/Services/T6PS3TextureDecoder.swift`
- Create: `Tests/ZombiesIOSTests/T6PS3TextureDecoderTests.swift`
- Create: `Sources/ZombiesIOS/Models/T6RenderableWorld.swift`

**Interfaces:**
- Produces: `T6DecodedTexture`, `T6RenderableMaterial`, `T6TextureFormat`.
- Produces: `T6PS3TextureDecoder.decode(image:payload:) throws -> T6DecodedTexture`.

- [ ] **Step 1: Write metadata tests for supported synthetic texture headers**

Cover at least RGBA8-like linear data and one swizzled/block-compressed fixture format already observable in the target PS3 asset metadata. Tests must verify width, height, mip count, alpha presence, and byte-range validation.

- [ ] **Step 2: Add malformed-range tests**

Ensure out-of-range image payloads throw a typed error instead of reading beyond the decoded buffer.

- [ ] **Step 3: Implement texture metadata parsing and conversion**

Keep the first implementation intentionally narrow: support only formats needed for the first Tranzit milestone. Unsupported formats must return an explicit `unsupportedFormat` error used by the world builder to attach a diagnostic material.

- [ ] **Step 4: Add renderer-facing material types**

`T6RenderableMaterial` must include base-color texture, alpha mode, fallback flag, and stable material ID.

- [ ] **Step 5: Run tests and commit**

```bash
git add Sources/ZombiesIOS/Services/T6PS3TextureDecoder.swift Sources/ZombiesIOS/Models/T6RenderableWorld.swift Tests/ZombiesIOSTests/T6PS3TextureDecoderTests.swift
git commit -m "feat: decode T6 PS3 textures"
```

---

### Task 6: Build a certifiable render package with props and weapon hooks

**Files:**
- Create: `Sources/ZombiesIOS/Services/T6RenderableWorldBuilder.swift`
- Modify: `Sources/ZombiesIOS/Services/TranzitRuntimeLoader.swift`
- Create/extend: `Tests/ZombiesIOSTests/T6RenderableWorldBuilderTests.swift`

**Interfaces:**
- Consumes: `T6DecodedZone`, world surfaces, decoded textures/materials.
- Produces: `T6RenderableWorldBuilder.build(zones:cacheRoot:) async throws -> T6RenderableWorld`.
- `T6RenderableWorld.validationSeed` contains counts used by renderer validation.

- [ ] **Step 1: Write failing integration test for synthetic world -> render package**

Fixture contains two world surfaces, one real material/texture, one unsupported material, one static model, and one weapon. Assert:

```swift
XCTAssertEqual(world.surfaces.count, 2)
XCTAssertEqual(world.materials.filter { !$0.isFallback }.count, 1)
XCTAssertEqual(world.props.count, 1)
XCTAssertNotNil(world.firstPersonWeapon)
XCTAssertFalse(world.usesDiagnosticGeometryOnly)
```

- [ ] **Step 2: Implement dependency resolution across decoded zones**

Primary Tranzit zone wins for world asset selection; shared zones resolve referenced materials/images/models/weapons by stable asset ID/name. Unresolved required world/material references throw typed errors.

- [ ] **Step 3: Add runtime artifact version keys**

Use source SHA-256 + decoder version + schema version. Store only user-local derived artifacts beneath `RuntimeCache/Tranzit`; never write them into the bundle.

- [ ] **Step 4: Migrate `TranzitRuntimeLoader` to deterministic cache/decode/build flow**

Replace repeated candidate scanning with:

```text
bookmark access -> manifest -> source cache -> decode ordered zones -> typed asset table -> render package -> ready
```

Only retain heuristics for diagnostics when typed decode fails.

- [ ] **Step 5: Enrich manifest from decoded references**

When decoded asset references reveal an additional source container, update the manifest, prepare only that dependency, and resume. Put a bounded iteration limit on dependency expansion to prevent loops.

- [ ] **Step 6: Run tests and commit**

```bash
git add Sources/ZombiesIOS/Services/T6RenderableWorldBuilder.swift Sources/ZombiesIOS/Services/TranzitRuntimeLoader.swift Tests/ZombiesIOSTests/T6RenderableWorldBuilderTests.swift
git commit -m "feat: build Tranzit render packages"
```

---

### Task 7: Render the real world, materials, props, and first-person weapon

**Files:**
- Modify: `Sources/ZombiesIOS/Views/NativeFPSSceneView.swift`
- Create: `Sources/ZombiesIOS/Services/RenderValidation.swift`
- Create: `Tests/ZombiesIOSTests/RenderValidationTests.swift`

**Interfaces:**
- `NativeFPSSceneView` consumes `T6RenderableWorld?` instead of `T6RuntimeMesh?`.
- Produces: `RenderValidationMetrics` through a binding/callback.

- [ ] **Step 1: Write validation rule tests**

```swift
func testBlackOrFallbackOnlySceneIsNotReady() {
    XCTAssertFalse(RenderValidation.accepts(.init(submittedTriangles: 1000, drawnSurfaces: 3, nonFallbackMaterials: 0, residentTextures: 0, renderedProps: 0, validCamera: true, blackPixelRatio: 0.95)))
}
```

Also assert acceptance requires nonzero surfaces, triangles, at least one real material/texture, valid camera, and black-pixel ratio below threshold.

- [ ] **Step 2: Replace single-mesh SceneKit construction with per-surface nodes**

For each `T6WorldSurface`, create geometry sources for position/normal/UV and bind the correct `T6RenderableMaterial`. Do not silently paint all surfaces with one neutral material.

- [ ] **Step 3: Add static prop nodes**

Instantiate only models present in `world.props`; preserve each model section's material binding.

- [ ] **Step 4: Add first-person weapon node**

Attach weapon to the camera with hip/ADS transforms. Use existing fire/reload pulses for basic transform feedback without inventing substitute weapon geometry.

- [ ] **Step 5: Add minimal lighting/fog from render package**

Use authored parameters from `T6RenderableWorld` or conservative project-authored defaults only for lighting environment; these defaults must not substitute for missing world geometry/materials.

- [ ] **Step 6: Emit render metrics every time the scene package changes**

Metrics must count submitted triangles, surfaces, real materials, resident textures, props, and camera validity.

- [ ] **Step 7: Run tests, build simulator app, commit**

```bash
xcodebuild -project ZombiesIOS.xcodeproj -scheme ZombiesIOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
git add Sources/ZombiesIOS/Views/NativeFPSSceneView.swift Sources/ZombiesIOS/Services/RenderValidation.swift Tests/ZombiesIOSTests/RenderValidationTests.swift
git commit -m "feat: render textured Tranzit world"
```

---

### Task 8: Replace ambiguous gameplay status with explicit runtime phases

**Files:**
- Modify: `Sources/ZombiesIOS/Views/TranzitTouchGameplayView.swift`
- Modify: `Sources/ZombiesIOS/ContentView.swift`

**Interfaces:**
- Consumes: `T6RenderableWorld`, `RenderValidationMetrics`.
- Produces: `TranzitRuntimePhase` with concrete progress/failure states.

- [ ] **Step 1: Add `TranzitRuntimePhase`**

Use explicit cases:

```swift
enum TranzitRuntimePhase: Equatable {
    case validatingSource
    case preparingSourceCache
    case copyingDependencies(done: Int, total: Int)
    case decodingZones(done: Int, total: Int)
    case resolvingAssets
    case buildingWorld
    case decodingTextures(done: Int, total: Int)
    case creatingRenderPackage
    case waitingForFirstFrame
    case ready
    case failed(String)
}
```

- [ ] **Step 2: Remove `runtimeMesh` readiness semantics**

The view should hold `@State private var renderableWorld: T6RenderableWorld?` and `@State private var renderMetrics = RenderValidationMetrics.zero`.

- [ ] **Step 3: Gate `.ready` on render validation**

Do not show `TRANZIT READY` until `RenderValidation.accepts(renderMetrics)` is true.

- [ ] **Step 4: Keep the touch HUD functional during/after migration**

Move/look/ADS/fire/reload/jump behavior remains unchanged.

- [ ] **Step 5: Add deterministic simulator test mode**

Recognize process arguments such as `--tranzit-render-test` and a synthetic fixture mode so CI can launch directly into a test scene without tapping through navigation.

- [ ] **Step 6: Build and commit**

```bash
git add Sources/ZombiesIOS/Views/TranzitTouchGameplayView.swift Sources/ZombiesIOS/ContentView.swift
git commit -m "feat: gate Tranzit ready state on rendered content"
```

---

### Task 9: Add screenshot black-frame/fallback gate

**Files:**
- Create: `Tools/render_gate.py`
- Create: `Tools/tests/test_render_gate.py`
- Modify: `.github/workflows/ios-build.yml`

**Interfaces:**
- Produces CLI: `python3 Tools/render_gate.py <screenshot.png> <metrics.json>`.
- Exit 0 means certifiable synthetic render; nonzero means black/empty/fallback-only.

- [ ] **Step 1: Write failing Python tests**

Create generated PNG fixtures in the test itself. Cover all-black, 98% black, varied non-black image, and valid image with metrics showing fallback-only materials.

- [ ] **Step 2: Implement `render_gate.py` without external image dependencies**

Use Python standard library plus macOS-provided tools if necessary; prefer reading PNG through a tiny deterministic parser only if practical. If Pillow is added, install it explicitly in CI and pin the version.

Rules:

```text
fail if drawnSurfaces == 0
fail if submittedTriangles == 0
fail if nonFallbackMaterials == 0
fail if residentTextures == 0
fail if validCamera == false
fail if blackPixelRatio >= 0.90
```

- [ ] **Step 3: Update simulator workflow**

After launching `--tranzit-render-test` with synthetic fixtures, capture screenshot and metrics JSON, run the gate, and fail before packaging on rejection.

- [ ] **Step 4: Stop uploading gameplay screenshots by default**

Keep only redistribution-safe synthetic screenshots in public CI. Real-asset screenshots must not be uploaded by default.

- [ ] **Step 5: Run Python and simulator tests, commit**

```bash
python3 -m unittest Tools.tests.test_render_gate -v
xcodebuild -project ZombiesIOS.xcodeproj -scheme ZombiesIOSTests -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
git add Tools/render_gate.py Tools/tests/test_render_gate.py .github/workflows/ios-build.yml
git commit -m "test: reject black Tranzit renders"
```

---

### Task 10: Add private real-asset certification path and package IPA only after it passes

**Files:**
- Modify: `.github/workflows/ios-build.yml`
- Modify: `README.md`
- Modify: `docs/IMPLEMENTATION_VERIFIED.md`

**Interfaces:**
- CI/public path proves redistribution-safe plumbing only.
- Private/local certification path consumes a legitimate local BO2 dump location and produces only pass/fail metrics plus the IPA; proprietary screenshots/assets are not persisted publicly.

- [ ] **Step 1: Add a real-asset certification mode that is opt-in**

Use a workflow input or local script contract such as `BO2_TEST_DUMP_PATH`. If absent, public CI runs synthetic validation but must label the IPA as not real-asset-certified.

- [ ] **Step 2: Run the app directly into Tranzit against the local test dump**

The flow must prepare the selective source cache, wait for `.ready` with a bounded timeout, capture metrics, and run `render_gate.py` against the private screenshot.

- [ ] **Step 3: Make final packaging depend on certification when producing a user-ready IPA**

A release called “validated” must not be created unless the real-asset gate passes. Development/synthetic-only builds must be named distinctly so they cannot be mistaken for completed gameplay builds.

- [ ] **Step 4: Verify built app content audit still rejects proprietary content**

Run `Tools/content_audit.py` against both repository and final `.app`. The new source/runtime cache directories must not exist inside the built bundle.

- [ ] **Step 5: Update docs with exact status language**

Document these states:

```text
synthetic-ci-passed
real-assets-rendered
user-ready-ipa
```

Only `user-ready-ipa` may be presented as completed Tranzit gameplay.

- [ ] **Step 6: Run the complete verification suite**

```bash
python3 -m unittest Tools.tests.test_content_audit Tools.tests.test_render_gate -v
xcodegen generate
xcodebuild -project ZombiesIOS.xcodeproj -scheme ZombiesIOSTests -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
xcodebuild -project ZombiesIOS.xcodeproj -scheme ZombiesIOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
python3 Tools/content_audit.py . --allowlist Tools/content_allowlist.txt
```

For the private real-asset environment, additionally run the Tranzit certification launch and verify `render_gate.py` exits 0.

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/ios-build.yml README.md docs/IMPLEMENTATION_VERIFIED.md
git commit -m "ci: require Tranzit render certification"
```

---

## Final Verification Checklist

- [ ] `xcodegen generate` succeeds.
- [ ] All `ZombiesIOSTests` pass.
- [ ] `Tools.tests.test_content_audit` passes.
- [ ] `Tools.tests.test_render_gate` passes.
- [ ] Simulator synthetic Tranzit fixture is accepted only when it contains non-black textured geometry.
- [ ] Intentionally black simulator fixture is rejected.
- [ ] Fallback-only material fixture is rejected.
- [ ] Source cache copies only manifest-selected files and reuses unchanged copies.
- [ ] Repository and built app audits contain no proprietary BO2 assets.
- [ ] Real-asset private run renders nonzero Tranzit world surfaces with at least one actual decoded BO2 texture/material.
- [ ] Real-asset private screenshot is not effectively black.
- [ ] First-person weapon comes from the user's decoded asset set when the required weapon asset is available.
- [ ] Existing touch controls remain responsive.
- [ ] IPA/release is labeled user-ready only after the real-asset gate passes.

## Self-Review

- **Spec coverage:** selective source cache, cache invalidation, typed decoding, GfxWorld material boundaries, texture decoding, props/weapon hooks, explicit runtime phases, renderer metrics, black/fallback rejection, redistribution-safe CI, and private real-asset certification are all assigned to concrete tasks.
- **Placeholder scan:** no TODO/TBD placeholders are used; unsupported texture formats intentionally fail with typed diagnostics rather than unspecified future work.
- **Type consistency:** later tasks consume `TranzitDependencyManifest`, `T6DecodedZone`, `T6RenderableWorld`, and `RenderValidationMetrics` using the exact names introduced earlier.
