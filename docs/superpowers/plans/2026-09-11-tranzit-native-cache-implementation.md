# Tranzit Native Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace repeated Tranzit PS3 runtime scanning with a deterministic, versioned native cache that converts geometry, UVs, materials, and textures once, validates staging output, atomically promotes it, and renders from cache on subsequent launches.

**Architecture:** Keep the BO2 source folder external and read-only. Build a staged importer under Application Support that fingerprints source files, decodes T6 assets, writes `world.meshbin`, `materials.json`, `textures/`, and `manifest.json`, validates the staging cache, then atomically replaces the active cache. Gameplay loads the active native cache first and only invokes the importer when the source fingerprint or cache schema changes.

**Tech Stack:** Swift 5, SwiftUI, SceneKit, Foundation, XcodeGen, XCTest, existing T6 PS3 FastFile decoder, existing zlib bridge.

**Spec:** `docs/superpowers/specs/2026-09-11-tranzit-native-cache-design.md`

## Global Constraints

- Keep the original BO2/PS3 folder in place; do not copy the source folder into app storage.
- Store converted cache data inside the app under Application Support.
- Automatically rebuild cache entries when source files change.
- Preserve and continue using the last known-good cache if a rebuild fails.
- Convert geometry, UVs, materials, and textures rather than stopping at a flat untextured mesh.
- Prefer deterministic XAsset-based conversion over repeated broad runtime heuristic scans.
- Texture failures must not invalidate otherwise-valid geometry.
- The renderer must not invoke the PS3 decoder once a valid native cache exists.
- iOS deployment target remains 17.0.
- Raw BO2 payload files (`*.ff`, `*.ipak`, `*.sabs`, `*.sabl`, `EBOOT.BIN`) must never be committed or bundled in the IPA.

---

## File Structure

### Create

- `Sources/ZombiesIOS/Cache/TranzitCacheManifest.swift` — Codable schema for cache version, source fingerprints, counts, warnings, and validation state.
- `Sources/ZombiesIOS/Cache/TranzitCachePaths.swift` — Application Support paths for `active/`, `staging/`, textures, mesh, materials, and manifest.
- `Sources/ZombiesIOS/Cache/TranzitCacheManager.swift` — source fingerprinting, cache validity checks, staging lifecycle, atomic promotion, and last-known-good retention.
- `Sources/ZombiesIOS/Cache/TranzitCachedWorld.swift` — in-memory native world model used by renderer.
- `Sources/ZombiesIOS/Cache/TranzitMeshBinary.swift` — deterministic binary writer/reader for vertices, normals, UVs, indices, submeshes, bounds.
- `Sources/ZombiesIOS/Import/T6AssetResolver.swift` — deterministic XAsset table walker exposing typed asset records, especially GfxWorld, Material, and GfxImage.
- `Sources/ZombiesIOS/Import/T6WorldConverter.swift` — converts resolved GfxWorld/surfaces into native mesh/submesh buffers with UVs/material IDs.
- `Sources/ZombiesIOS/Import/T6MaterialConverter.swift` — converts T6 Material records into reduced native material records.
- `Sources/ZombiesIOS/Import/T6TextureConverter.swift` — converts supported PS3 GfxImage payloads into iOS-readable cached images and records failures per asset.
- `Sources/ZombiesIOS/Import/TranzitNativeImporter.swift` — orchestrates decode, asset resolution, geometry/material/texture conversion, staging write, validation, promotion.
- `Sources/ZombiesIOS/Import/TranzitCacheValidator.swift` — validates file structure, counts, ranges, materials, texture metadata, and manifest consistency.
- `Tests/ZombiesIOSTests/TranzitCacheTests.swift` — fingerprinting, invalidation, promotion, last-known-good behavior.
- `Tests/ZombiesIOSTests/TranzitMeshBinaryTests.swift` — deterministic binary round-trip and range validation.
- `Tests/ZombiesIOSTests/T6WorldConverterTests.swift` — synthetic big-endian surface/vertex/index/UV fixture conversion.
- `Tests/ZombiesIOSTests/T6MaterialTextureTests.swift` — material mapping and texture fallback behavior.

### Modify

- `project.yml` — add the XCTest target.
- `Sources/ZombiesIOS/Services/T6ZoneAssetProbe.swift` — expose reusable typed XAsset table metadata instead of only aggregate counts.
- `Sources/ZombiesIOS/Services/T6GfxSurfaceMeshExtractor.swift` — keep as diagnostic/development fallback only; remove it from normal gameplay selection.
- `Sources/ZombiesIOS/Services/TranzitRuntimeLoader.swift` — include source modification times/fingerprints needed by cache manager without copying source files.
- `Sources/ZombiesIOS/Views/TranzitTouchGameplayView.swift` — replace direct PS3 decode/scan loop with cache-first load/import state machine and concrete progress diagnostics.
- `Sources/ZombiesIOS/Views/NativeFPSSceneView.swift` — accept `TranzitCachedWorld?`, render submeshes with per-material textures, and build simplified collision geometry.
- `.github/workflows/ios-build.yml` — run unit tests before packaging and verify raw BO2 payloads remain absent.

---

### Task 1: Add XCTest Target and Cache Data Models

**Files:**
- Modify: `project.yml`
- Create: `Sources/ZombiesIOS/Cache/TranzitCacheManifest.swift`
- Create: `Sources/ZombiesIOS/Cache/TranzitCachedWorld.swift`
- Create: `Tests/ZombiesIOSTests/TranzitCacheTests.swift`

**Interfaces:**
- Produces: `TranzitSourceFingerprint`, `TranzitCacheManifest`, `TranzitCachedWorld`, `TranzitCachedMaterial`, `TranzitCachedSubmesh`.
- Later tasks depend on exact Codable/Equatable model names above.

- [ ] **Step 1: Add a test target to `project.yml`.**

Add:

```yaml
  ZombiesIOSTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - Tests/ZombiesIOSTests
    dependencies:
      - target: ZombiesIOS
```

- [ ] **Step 2: Write failing model tests.**

Create `Tests/ZombiesIOSTests/TranzitCacheTests.swift` with tests that JSON-encode/decode a `TranzitCacheManifest` and compare equality.

Required manifest initializer fields:

```swift
TranzitCacheManifest(
    schemaVersion: 1,
    sourceFingerprints: [TranzitSourceFingerprint(relativePath: "zone/zm_transit.ff", byteCount: 100, modifiedAt: Date(timeIntervalSince1970: 10))],
    surfaceCount: 12,
    vertexCount: 120,
    triangleCount: 80,
    materialCount: 4,
    textureTotal: 6,
    textureSucceeded: 5,
    textureFailed: 1,
    warnings: ["missing normal"],
    validationState: .valid
)
```

- [ ] **Step 3: Run the new test and verify failure.**

Run:

```bash
xcodegen generate
xcodebuild test -project ZombiesIOS.xcodeproj -scheme ZombiesIOS -destination 'platform=iOS Simulator,name=iPhone 16 Plus'
```

Expected: compile failure because cache model types do not yet exist.

- [ ] **Step 4: Implement the cache models.**

`TranzitCacheManifest.swift` must define:

```swift
struct TranzitSourceFingerprint: Codable, Equatable, Hashable {
    let relativePath: String
    let byteCount: Int64
    let modifiedAt: Date
}

enum TranzitCacheValidationState: String, Codable {
    case staging
    case valid
    case invalid
}

struct TranzitCacheManifest: Codable, Equatable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let sourceFingerprints: [TranzitSourceFingerprint]
    let surfaceCount: Int
    let vertexCount: Int
    let triangleCount: Int
    let materialCount: Int
    let textureTotal: Int
    let textureSucceeded: Int
    let textureFailed: Int
    let warnings: [String]
    let validationState: TranzitCacheValidationState
}
```

`TranzitCachedWorld.swift` must define:

```swift
struct TranzitCachedMaterial: Codable, Equatable {
    let id: Int
    let name: String
    let diffuseTexture: String?
    let normalTexture: String?
    let specularTexture: String?
    let alphaCutout: Bool
}

struct TranzitCachedSubmesh: Codable, Equatable {
    let firstIndex: Int
    let indexCount: Int
    let materialID: Int
}

struct TranzitCachedWorld: Equatable {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let uvs: [SIMD2<Float>]
    let indices: [UInt32]
    let submeshes: [TranzitCachedSubmesh]
    let materials: [TranzitCachedMaterial]
}
```

- [ ] **Step 5: Re-run tests and commit.**

Expected: manifest round-trip passes.

Commit message:

```text
feat: add Tranzit native cache models
```

---

### Task 2: Cache Paths, Fingerprints, and Last-Known-Good Promotion

**Files:**
- Create: `Sources/ZombiesIOS/Cache/TranzitCachePaths.swift`
- Create: `Sources/ZombiesIOS/Cache/TranzitCacheManager.swift`
- Modify: `Tests/ZombiesIOSTests/TranzitCacheTests.swift`

**Interfaces:**
- Consumes: `TranzitCacheManifest`, `TranzitSourceFingerprint`.
- Produces:

```swift
struct TranzitCachePaths
actor TranzitCacheManager {
    func sourceFingerprints(rootURL: URL, resources: [TranzitLoadedResource]) throws -> [TranzitSourceFingerprint]
    func loadValidManifest(for fingerprints: [TranzitSourceFingerprint]) throws -> TranzitCacheManifest?
    func prepareStaging() throws -> TranzitCachePaths
    func promoteStaging() throws
    func discardStaging()
}
```

- [ ] **Step 1: Write failing tests for path isolation, fingerprint changes, and promotion.**

Tests must use a temporary directory injected into `TranzitCacheManager(applicationSupportRoot:)` and assert:

```swift
XCTAssertTrue(paths.active.path.contains("TranzitCache/active"))
XCTAssertTrue(paths.staging.path.contains("TranzitCache/staging"))
```

Create a source file, fingerprint it, change its size or mtime, fingerprint again, and assert inequality.

Create an existing `active/marker.txt`, create `staging/new.txt`, call `promoteStaging()`, and assert `active/new.txt` exists and promotion never exposes a partially-copied directory.

- [ ] **Step 2: Run tests and verify failure.**

Expected: cache path/manager types missing.

- [ ] **Step 3: Implement Application Support layout.**

`TranzitCachePaths` must derive:

```text
<root>/TranzitCache/active
<root>/TranzitCache/staging
<root>/TranzitCache/active/world.meshbin
<root>/TranzitCache/active/materials.json
<root>/TranzitCache/active/textures
<root>/TranzitCache/active/manifest.json
```

The default root uses `FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)`.

- [ ] **Step 4: Implement deterministic fingerprinting and staging lifecycle.**

Sort fingerprints by lowercase `relativePath`. Read source attributes directly from `rootURL.appendingPathComponent(resource.relativePath)`; never copy source payloads into cache.

Promotion must:

1. Require staging validation before promotion.
2. Move current active to a temporary backup name.
3. Move staging to active.
4. Delete backup only after active exists.
5. Restore backup if the staging-to-active move fails.

- [ ] **Step 5: Run tests and commit.**

Commit message:

```text
feat: add staged Tranzit cache lifecycle
```

---

### Task 3: Deterministic Mesh Binary Reader/Writer

**Files:**
- Create: `Sources/ZombiesIOS/Cache/TranzitMeshBinary.swift`
- Create: `Tests/ZombiesIOSTests/TranzitMeshBinaryTests.swift`

**Interfaces:**
- Consumes: `TranzitCachedWorld` geometry fields and `TranzitCachedSubmesh`.
- Produces:

```swift
enum TranzitMeshBinary {
    static func write(world: TranzitCachedWorld, to url: URL) throws
    static func read(from url: URL, materials: [TranzitCachedMaterial]) throws -> TranzitCachedWorld
}
```

- [ ] **Step 1: Write failing round-trip and corrupt-range tests.**

Fixture must include at least four vertices, UVs, normals, six indices, and two submeshes. Assert exact round-trip equality.

Write a corrupt fixture where a submesh's `firstIndex + indexCount` exceeds the index array and assert `read` throws `TranzitMeshBinaryError.invalidSubmeshRange`.

- [ ] **Step 2: Run tests and verify failure.**

- [ ] **Step 3: Implement versioned little-endian cache format.**

Header fields, in order:

```text
magic: 8 bytes "TRNZMESH"
version: UInt32 = 1
vertexCount: UInt32
indexCount: UInt32
submeshCount: UInt32
```

Each vertex stores position `Float32x3`, normal `Float32x3`, UV `Float32x2`. Indices are `UInt32`. Each submesh stores `firstIndex UInt32`, `indexCount UInt32`, `materialID Int32`.

The cache format is native and independent of PS3 byte order.

- [ ] **Step 4: Add strict range and count validation.**

Reject files with wrong magic/version, impossible byte counts, indices >= vertex count, or invalid submesh ranges.

- [ ] **Step 5: Run tests and commit.**

Commit message:

```text
feat: add deterministic Tranzit mesh cache format
```

---

### Task 4: Expose Typed T6 XAsset Records

**Files:**
- Modify: `Sources/ZombiesIOS/Services/T6ZoneAssetProbe.swift`
- Create: `Sources/ZombiesIOS/Import/T6AssetResolver.swift`
- Add tests to: `Tests/ZombiesIOSTests/T6WorldConverterTests.swift`

**Interfaces:**
- Produces:

```swift
enum T6AssetType: Int, Sendable {
    case material = 6
    case gfxImage = 8
    case gfxWorld = 17
}

struct T6AssetRecord: Sendable, Equatable {
    let type: T6AssetType
    let tableOffset: Int
    let rawPointer: UInt32
}

struct T6ResolvedAssetIndex: Sendable {
    let records: [T6AssetRecord]
    func first(_ type: T6AssetType) -> T6AssetRecord?
    func all(_ type: T6AssetType) -> [T6AssetRecord]
}

enum T6AssetResolver {
    static func resolveIndex(in payload: Data) -> T6ResolvedAssetIndex?
}
```

- [ ] **Step 1: Write a failing synthetic big-endian XAsset table test.**

Construct entries as 8-byte `[typeBE, pointerBE]` records and assert resolver returns one GfxWorld, two Materials, and two GfxImages in stable table order.

- [ ] **Step 2: Run test and verify failure.**

- [ ] **Step 3: Refactor `T6ZoneAssetProbe` to expose table offset/count parsing without duplicating scan logic.**

Keep existing report fields and behavior intact for compatibility.

- [ ] **Step 4: Implement `T6AssetResolver`.**

Use the same declared-index/direct-table discovery logic as the probe. Reject unknown type IDs for typed output but do not fail the whole index because unrelated asset types exist.

- [ ] **Step 5: Run tests and commit.**

Commit message:

```text
feat: expose deterministic T6 XAsset index
```

---

### Task 5: Convert GfxWorld Geometry, UVs, and Material IDs

**Files:**
- Create: `Sources/ZombiesIOS/Import/T6WorldConverter.swift`
- Modify: `Sources/ZombiesIOS/Services/T6GfxSurfaceMeshExtractor.swift`
- Create/modify: `Tests/ZombiesIOSTests/T6WorldConverterTests.swift`

**Interfaces:**
- Consumes: decoded payload `Data`, `T6ResolvedAssetIndex`.
- Produces:

```swift
struct T6WorldConversionResult {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let uvs: [SIMD2<Float>]
    let indices: [UInt32]
    let submeshes: [TranzitCachedSubmesh]
    let warnings: [String]
}

enum T6WorldConverter {
    static func convert(payload: Data, assets: T6ResolvedAssetIndex) throws -> T6WorldConversionResult
}
```

- [ ] **Step 1: Write a synthetic PS3 big-endian world fixture.**

The fixture must contain:

- at least two surfaces,
- a packed vertex stream with 36-byte stride,
- valid positions,
- packed/explicit UV values chosen so expected values are deterministic,
- an index stream,
- different material IDs per surface.

Assert conversion yields nonzero surfaces, exact positions/UVs, valid indices, and two distinct submesh material IDs.

- [ ] **Step 2: Run test and verify failure.**

- [ ] **Step 3: Extract reusable low-level parsing helpers from `T6GfxSurfaceMeshExtractor`.**

Keep the old extractor callable, but mark it as diagnostic fallback in comments and stop coupling new conversion to its heuristic `findBestSurfaceRun` entry point when the GfxWorld asset record gives a deterministic route.

- [ ] **Step 4: Implement GfxWorld conversion.**

Required checks:

```swift
guard firstVertex >= 0,
      vertexCount >= 3,
      baseIndex >= 0,
      triCount >= 1 else { skip surface }
```

Every output index must satisfy `index < positions.count`. Corrupt surfaces are skipped with warnings rather than corrupting valid submeshes.

- [ ] **Step 5: Decode normals and UVs.**

Normalize normals before writing cache. UV decode must preserve finite values and reject NaN/Inf. If one surface lacks usable UVs, emit zero UVs for that surface and record a warning rather than aborting the world.

- [ ] **Step 6: Run tests and commit.**

Commit message:

```text
feat: convert T6 GfxWorld to native submeshes
```

---

### Task 6: Convert Materials and Textures with Safe Fallbacks

**Files:**
- Create: `Sources/ZombiesIOS/Import/T6MaterialConverter.swift`
- Create: `Sources/ZombiesIOS/Import/T6TextureConverter.swift`
- Create: `Tests/ZombiesIOSTests/T6MaterialTextureTests.swift`

**Interfaces:**
- Produces:

```swift
struct T6MaterialConversionResult {
    let materials: [TranzitCachedMaterial]
    let warnings: [String]
}

struct T6TextureConversionReport {
    let total: Int
    let succeeded: Int
    let failed: Int
    let warnings: [String]
}

enum T6MaterialConverter {
    static func convert(payload: Data, assets: T6ResolvedAssetIndex) -> T6MaterialConversionResult
}

enum T6TextureConverter {
    static func convert(payload: Data, assets: T6ResolvedAssetIndex, destination: URL) throws -> T6TextureConversionReport
}
```

- [ ] **Step 1: Write failing material mapping tests.**

Synthetic fixture must resolve one material with diffuse/normal/specular references and one material whose diffuse image is missing. Assert the missing image produces a nil texture reference and warning, not a fatal error.

- [ ] **Step 2: Write failing BC1/BC3 texture fixture tests.**

Use tiny 4x4 compressed blocks with known pixels. Assert converter writes an image file that UIKit can load and whose dimensions are exactly 4x4.

- [ ] **Step 3: Implement reduced native material mapping.**

Support stable IDs, names, diffuse/base color, normal, specular, and alpha-cutout. Unsupported shader state maps to defaults and warnings.

- [ ] **Step 4: Implement texture conversion.**

Prioritize formats actually seen in Tranzit. Required initial decoder paths:

```text
BC1/DXT1
BC2/DXT3
BC3/DXT5
uncompressed RGBA8/BGRA8 where detected
```

Handle PS3 big-endian block/pixel ordering explicitly. Write deterministic filenames based on asset table offset or resolved asset identity, e.g. `image_00001234.png` for the transitional implementation.

- [ ] **Step 5: Ensure failure isolation.**

A single failed image increments `failed` and appends a warning. It must not throw unless the destination directory itself is unusable.

- [ ] **Step 6: Run tests and commit.**

Commit message:

```text
feat: convert T6 materials and textures
```

---

### Task 7: Staging Validator and Atomic Promotion Gate

**Files:**
- Create: `Sources/ZombiesIOS/Import/TranzitCacheValidator.swift`
- Modify: `Sources/ZombiesIOS/Cache/TranzitCacheManager.swift`
- Modify: `Tests/ZombiesIOSTests/TranzitCacheTests.swift`
- Modify: `Tests/ZombiesIOSTests/TranzitMeshBinaryTests.swift`

**Interfaces:**
- Produces:

```swift
struct TranzitCacheValidationReport {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
}

enum TranzitCacheValidator {
    static func validate(paths: TranzitCachePaths) -> TranzitCacheValidationReport
}
```

- [ ] **Step 1: Write failing validator tests.**

Cover:

- valid cache,
- missing mesh file,
- bad mesh index,
- submesh material ID not present in `materials.json`,
- manifest count mismatch,
- missing texture referenced by a material.

Missing diffuse texture is a warning/fallback condition, not a fatal geometry failure. Structural mesh/material corruption is fatal.

- [ ] **Step 2: Run tests and verify failure.**

- [ ] **Step 3: Implement validator.**

Read the manifest, materials, and mesh using production readers. Verify manifest schema equals `TranzitCacheManifest.currentSchemaVersion`.

- [ ] **Step 4: Gate promotion on validator success.**

Change `promoteStaging()` so it validates staging internally and throws a typed error when invalid. The current active cache remains untouched on failure.

- [ ] **Step 5: Run tests and commit.**

Commit message:

```text
feat: validate Tranzit cache before promotion
```

---

### Task 8: Import Orchestrator with Automatic Rebuild

**Files:**
- Create: `Sources/ZombiesIOS/Import/TranzitNativeImporter.swift`
- Modify: `Sources/ZombiesIOS/Services/TranzitRuntimeLoader.swift`
- Add tests to: `Tests/ZombiesIOSTests/TranzitCacheTests.swift`

**Interfaces:**
- Produces:

```swift
enum TranzitImportStage: String, Sendable {
    case sourceCheck
    case decodingFastFile
    case resolvingXAssets
    case convertingWorld
    case convertingMaterials
    case convertingTextures
    case validatingCache
    case cacheReady
}

struct TranzitImportProgress: Sendable {
    let stage: TranzitImportStage
    let detail: String
}

actor TranzitNativeImporter {
    func loadOrRebuild(
        rootURL: URL,
        resources: [TranzitLoadedResource],
        progress: @Sendable (TranzitImportProgress) -> Void
    ) async throws -> TranzitCachedWorld
}
```

- [ ] **Step 1: Write failing cache-hit and cache-miss tests.**

A cache hit with unchanged fingerprints must load without invoking an injected decoder spy. A changed source mtime must invoke rebuild.

- [ ] **Step 2: Write failing rebuild-failure retention test.**

Start with valid active cache, inject a converter that throws, call `loadOrRebuild`, and assert the old active cache still exists and can be loaded.

- [ ] **Step 3: Implement orchestration in strict stage order.**

Pipeline:

```text
fingerprint -> cache hit check -> decode candidate FastFile -> XAsset index -> world -> materials -> textures -> write mesh/materials/manifest -> validate -> promote -> load active
```

Prefer `zm_transit.ff` as authoritative full-map source when present. Preserve the existing T6 decoder for FastFile decompression only; do not route normal success through `T6MeshPreviewExtractor`.

- [ ] **Step 4: Write staging manifest with real counts.**

Set `validationState = .staging`, run validator, then write `.valid` before promotion.

- [ ] **Step 5: Run tests and commit.**

Commit message:

```text
feat: add automatic Tranzit native importer
```

---

### Task 9: Cache-First Gameplay State Machine and Diagnostics

**Files:**
- Modify: `Sources/ZombiesIOS/Views/TranzitTouchGameplayView.swift`

**Interfaces:**
- Consumes: `TranzitNativeImporter.loadOrRebuild`.
- Produces: `@State private var cachedWorld: TranzitCachedWorld?` and concrete import-stage UI.

- [ ] **Step 1: Add a UI-state test seam.**

Extract formatting into a pure helper:

```swift
static func cacheStatus(manifest: TranzitCacheManifest) -> String
```

Expected format:

```text
GFXWORLD 1384S 62491V 103882T 417M 356/389 TEX
```

Write a unit test against exact output.

- [ ] **Step 2: Remove normal-path runtime payload scanning from `decodeT6Payload()`.**

Replace the direct loop over candidate FastFiles and calls to `T6GfxSurfaceMeshExtractor` / `T6MeshPreviewExtractor` with one importer call.

- [ ] **Step 3: Wire progress stage messages.**

Map stages exactly:

```text
SOURCE CHECK
DECODING FASTFILE
RESOLVING XASSETS
CONVERTING WORLD
CONVERTING MATERIALS
CONVERTING TEXTURES
VALIDATING CACHE
CACHE READY
```

On rebuild failure with an existing active cache, display `REBUILD FAILED / USING PREVIOUS CACHE` and keep gameplay running.

- [ ] **Step 4: Preserve source-folder behavior.**

Continue reading source resources in place through `rootURL`; do not add any copy-to-Documents/Application Support operation for original BO2 data.

- [ ] **Step 5: Run tests and commit.**

Commit message:

```text
feat: load Tranzit gameplay from native cache
```

---

### Task 10: Render Native Submeshes with Per-Material Textures

**Files:**
- Modify: `Sources/ZombiesIOS/Views/NativeFPSSceneView.swift`

**Interfaces:**
- Replace `let runtimeMesh: T6RuntimeMesh?` with `let cachedWorld: TranzitCachedWorld?`.
- Renderer consumes cached positions/normals/UVs/indices/submeshes/materials only.

- [ ] **Step 1: Write a renderer geometry construction helper test.**

Extract a pure helper that validates and partitions index ranges:

```swift
static func validatedSubmeshes(world: TranzitCachedWorld) -> [TranzitCachedSubmesh]
```

Test rejects out-of-range submeshes and keeps valid neighbors.

- [ ] **Step 2: Build SceneKit geometry sources for position, normal, and UV.**

Use `SCNGeometrySource` for all three channels. Build one `SCNGeometryElement` per cached submesh.

- [ ] **Step 3: Create one `SCNMaterial` per cached material.**

Load cached image files from active cache paths. Bind diffuse, normal, and specular contents where present. Missing diffuse uses a conspicuous fallback material but does not remove the submesh.

- [ ] **Step 4: Replace full-detail physics with simplified collision.**

At minimum, use a decimated subset or one collision element built from every Nth triangle rather than duplicating the full render mesh. Keep the safety floor hidden only when a valid cached world is present.

- [ ] **Step 5: Verify no renderer code calls T6 PS3 decoders.**

Search:

```bash
grep -R "T6PS3PayloadDecoder\|T6GfxSurfaceMeshExtractor\|T6MeshPreviewExtractor" Sources/ZombiesIOS/Views
```

Expected: no matches in normal gameplay renderer/view code.

- [ ] **Step 6: Run tests and commit.**

Commit message:

```text
feat: render cached Tranzit materials and textures
```

---

### Task 11: Build Workflow Verification and IPA Packaging

**Files:**
- Modify: `.github/workflows/ios-build.yml`

**Interfaces:**
- CI must test before package and retain existing unsigned IPA artifact/release behavior.

- [ ] **Step 1: Add unit-test step before archive/package.**

Run XcodeGen, then:

```bash
xcodebuild test \
  -project ZombiesIOS.xcodeproj \
  -scheme ZombiesIOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Plus' \
  CODE_SIGNING_ALLOWED=NO
```

If the runner lacks that exact simulator, select an installed iPhone simulator dynamically with `xcrun simctl list devices available` rather than silently skipping tests.

- [ ] **Step 2: Keep raw-payload exclusion check.**

CI must fail if any committed file matches:

```text
*.ff
*.ipak
*.sabs
*.sabl
EBOOT.BIN
```

- [ ] **Step 3: Add source checks for cache/import components.**

Verify required files exist and that `TranzitTouchGameplayView.swift` references `TranzitNativeImporter`.

- [ ] **Step 4: Run/trigger GitHub Actions and inspect failures.**

Do not declare success from compilation alone. Require unit tests, app build, IPA packaging, and artifact publication to complete.

- [ ] **Step 5: Commit workflow changes.**

Commit message:

```text
ci: test native Tranzit cache before IPA build
```

---

### Task 12: End-to-End Verification Against Real Tranzit Data

**Files:**
- No committed BO2 asset files.
- May modify importer/parser source only in response to observed real-data failures.

**Interfaces:**
- Success output must expose real counts and cache reuse behavior.

- [ ] **Step 1: First-launch import verification on device.**

With the selected BO2 folder available, confirm progress advances through all importer stages and ends at `CACHE READY`.

Required nonzero diagnostics:

```text
surfaces > 0
vertices > 0
triangles > 0
materials > 0
textureSucceeded > 0
```

- [ ] **Step 2: Verify recognizable textured Tranzit geometry.**

Confirm world geometry is not the fallback arena and that multiple submeshes display distinct textures/materials.

- [ ] **Step 3: Verify second-launch cache hit.**

Relaunch without modifying source files. Confirm no deep FastFile decode/world scan runs and startup uses active cache directly.

- [ ] **Step 4: Verify automatic invalidation.**

Change a relevant source file mtime/size in a controlled test copy, relaunch, and confirm a staged rebuild begins automatically.

- [ ] **Step 5: Verify last-known-good behavior.**

Force a rebuild failure after an active cache exists. Confirm previous cache remains playable and UI reports `REBUILD FAILED / USING PREVIOUS CACHE`.

- [ ] **Step 6: Final CI/IPA verification.**

Require a green GitHub Actions run and confirm the produced `.ipa` artifact is downloadable and nonzero in size.

- [ ] **Step 7: Final commit only if real-data fixes were needed.**

Use a specific message describing the parser/converter fix; do not use generic “final fixes”.

---

## Plan Self-Review

- **Spec coverage:** cache location, external source retention, automatic invalidation, last-known-good behavior, deterministic XAsset resolution, geometry/UV/material/texture conversion, staging validation, atomic promotion, cache-only renderer startup, diagnostics, collision simplification, and CI are all assigned to explicit tasks.
- **Placeholder scan:** no TBD/TODO/“implement later” steps remain.
- **Type consistency:** the plan consistently uses `TranzitCacheManifest`, `TranzitCachedWorld`, `TranzitCachedMaterial`, `TranzitCachedSubmesh`, `T6ResolvedAssetIndex`, `T6WorldConversionResult`, and `TranzitNativeImporter.loadOrRebuild` across tasks.
