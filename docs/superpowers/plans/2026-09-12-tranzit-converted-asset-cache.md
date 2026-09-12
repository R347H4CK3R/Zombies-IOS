# Tranzit Converted Asset Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a one-time BO2 Tranzit import/conversion pipeline that stores validated iOS-readable assets in `Application Support/ConvertedTranzit` and makes gameplay load those converted assets instead of decoding `zm_transit.ff` at runtime.

**Architecture:** Preserve the existing external BO2 folder as the source of truth, but move PS3 decoding into an import-only pipeline. The pipeline writes a versioned native package transactionally, validates it, then promotes it as the active package. Runtime gameplay first checks the converted package and renders native mesh/material/texture/collision/weapon assets directly; if the package is absent or invalid, gameplay routes to conversion instead of entering a black scene.

**Tech Stack:** Swift, SwiftUI, SceneKit, Foundation `Data`/`FileManager`, existing T6 PS3 decoder/GfxWorld extractor, XCTest or source-level regression tests already used by the repo, GitHub Actions iPhone 17 Simulator validation.

**Spec:** `docs/superpowers/specs/2026-09-12-tranzit-converted-asset-cache-design.md`

## Global Constraints

- Original BO2 dump remains external and untouched.
- No proprietary BO2 assets are committed to GitHub or bundled in the distributed IPA.
- Converted assets are created locally from the user's own dump and stored in the app sandbox.
- Generated content root is exactly `Application Support/ConvertedTranzit`.
- Conversion must be restartable and resumable.
- Runtime gameplay must not depend on PS3 fastfile parsing when a valid converted package exists.
- A failed or interrupted conversion must preserve the last known-good package.
- Phase one includes one recognizable Tranzit area, visible world geometry, visible textures/materials, collision, and one weapon model.
- CI may use only redistributable synthetic fixtures; real BO2 content must never be committed or uploaded as public CI evidence.

---

## File Structure

### New files

- `Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitManifest.swift` — Codable manifest model and package-version contract.
- `Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitPaths.swift` — canonical Application Support, staging, active-package, and diagnostics paths.
- `Sources/ZombiesIOS/ConvertedAssets/ConvertedMeshFormat.swift` — native mesh header, encoder, decoder, and integrity checks.
- `Sources/ZombiesIOS/ConvertedAssets/ConvertedPackageValidator.swift` — validates manifest and required files before runtime use.
- `Sources/ZombiesIOS/ConvertedAssets/ConvertedPackageStore.swift` — staging/promotion and last-known-good package semantics.
- `Sources/ZombiesIOS/ConvertedAssets/ConvertedSourceFingerprint.swift` — source identity/versioning from external dump metadata.
- `Sources/ZombiesIOS/ConvertedAssets/ConvertedWorldImporter.swift` — import-time world decode and native mesh conversion.
- `Sources/ZombiesIOS/ConvertedAssets/ConvertedMaterialImporter.swift` — phase-one material/texture conversion contract and fallback diagnostics.
- `Sources/ZombiesIOS/ConvertedAssets/ConvertedCollisionImporter.swift` — collision mesh conversion and bounds validation.
- `Sources/ZombiesIOS/ConvertedAssets/ConvertedWeaponImporter.swift` — one weapon mesh/material conversion.
- `Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitImporter.swift` — orchestrates staged conversion and manifest creation.
- `Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitLoader.swift` — runtime native package loader.
- `Sources/ZombiesIOS/Views/ConvertedTranzitImportView.swift` — blocking conversion UI and progress/error state.
- `Sources/ZombiesIOS/Views/ConvertedTranzitSceneView.swift` — SceneKit view that renders converted native assets.
- `Sources/ZombiesIOS/Support/CIConvertedPackageFixture.swift` — redistributable synthetic converted package fixture for CI.
- `Tools/tests/test_converted_asset_architecture.py` — source-level regression tests for package paths/runtime bypass/CI fixture.

### Existing files to modify

- `Sources/ZombiesIOS/ContentView.swift` — route remembered BO2 folder into conversion flow when package is missing/stale.
- `Sources/ZombiesIOS/Views/TranzitTouchGameplayView.swift` — remove raw PS3 decode/render responsibility from gameplay path and host converted runtime instead.
- `Sources/ZombiesIOS/Views/NativeFPSSceneView.swift` — keep current raw mesh renderer isolated from the new converted renderer; do not silently fall back to raw PS3 runtime.
- `Sources/ZombiesIOS/Services/ExternalGameFolderStore.swift` — expose the remembered external folder URL needed by importer without copying the source folder.
- `.github/workflows/ios-build.yml` — add architecture tests and switch simulator visual gate to converted-package fixture mode.
- `.github/build-trigger.txt` — trigger the final validation build only after implementation is complete.

---

### Task 1: Manifest, Paths, and Source Fingerprint

**Files:**
- Create: `Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitManifest.swift`
- Create: `Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitPaths.swift`
- Create: `Sources/ZombiesIOS/ConvertedAssets/ConvertedSourceFingerprint.swift`
- Test: `Tools/tests/test_converted_asset_architecture.py`

**Interfaces:**
- Produces: `ConvertedTranzitManifest`, `ConvertedTranzitPaths`, `ConvertedSourceFingerprint.make(for:) -> ConvertedSourceFingerprint`
- Consumed by: package validator/store/importer/runtime loader.

- [ ] **Step 1: Write the failing source-architecture test**

Add assertions that the new files exist and contain the package version, `Application Support/ConvertedTranzit`, a `complete` manifest field, and a source fingerprint type based on file name/size/modification metadata.

```python
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ConvertedAssetArchitectureTests(unittest.TestCase):
    def test_manifest_and_paths_contract_exist(self):
        manifest = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitManifest.swift").read_text()
        paths = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitPaths.swift").read_text()
        fingerprint = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedSourceFingerprint.swift").read_text()
        self.assertIn("packageFormatVersion", manifest)
        self.assertIn("complete", manifest)
        self.assertIn("ConvertedTranzit", paths)
        self.assertIn("applicationSupportDirectory", paths)
        self.assertIn("modificationDate", fingerprint)
        self.assertIn("fileSize", fingerprint)
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
python3 -m unittest Tools.tests.test_converted_asset_architecture -v
```

Expected: FAIL because the converted-asset files do not exist yet.

- [ ] **Step 3: Implement the manifest contract**

`ConvertedTranzitManifest` must be `Codable` and include exact phase-one fields:

```swift
struct ConvertedTranzitManifest: Codable {
    static let packageFormatVersion = 1
    let formatVersion: Int
    let sourceFingerprint: ConvertedSourceFingerprint
    let sourceAreaName: String
    let createdAt: Date
    let converterBuild: String
    let worldMeshPath: String
    let collisionMeshPath: String
    let materialManifestPath: String
    let weaponMeshPath: String
    let convertedTextureCount: Int
    let vertexCount: Int
    let indexCount: Int
    let worldBoundsMin: SIMD3<Float>
    let worldBoundsMax: SIMD3<Float>
    let complete: Bool
    let stageDiagnostics: [String: String]
}
```

Because `SIMD3<Float>` is not automatically suitable for every Codable deployment target, encode bounds using a small Codable vector type if required, e.g. `ConvertedFloat3 { x,y,z }`, but keep one canonical type consistently across all later tasks.

- [ ] **Step 4: Implement canonical package paths**

`ConvertedTranzitPaths` must resolve:

```text
Application Support/ConvertedTranzit/
Application Support/ConvertedTranzit.staging/
Application Support/ConvertedTranzit/diagnostics/import-report.json
```

Use `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!` and never write converted content into the signed app bundle.

- [ ] **Step 5: Implement source fingerprinting**

Fingerprint only the minimum source resources selected for conversion. For each file, include lowercased relative path, file size, and modification timestamp; sort records before hashing/serializing so the result is deterministic.

- [ ] **Step 6: Run the test and verify GREEN**

Run the same unittest command. Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/ZombiesIOS/ConvertedAssets Tools/tests/test_converted_asset_architecture.py
git commit -m "feat: add converted Tranzit package contract"
```

---

### Task 2: Native Mesh Format With Integrity Validation

**Files:**
- Create: `Sources/ZombiesIOS/ConvertedAssets/ConvertedMeshFormat.swift`
- Extend: `Tools/tests/test_converted_asset_architecture.py`

**Interfaces:**
- Produces: `ConvertedMesh`, `ConvertedMeshFormat.encode(_:) throws -> Data`, `ConvertedMeshFormat.decode(_:) throws -> ConvertedMesh`, `ConvertedMeshFormat.validate(_:) throws`
- Consumes: positions `[SIMD3<Float>]`, indices `[UInt32]`, bounds, material groups.

- [ ] **Step 1: Add failing architecture assertions**

Require the source to define a fixed magic, format version, little-endian write/read helpers, vertex count, index count, bounds, and index validation.

- [ ] **Step 2: Run test and verify RED**

Expected: FAIL because `ConvertedMeshFormat.swift` is missing.

- [ ] **Step 3: Implement the v1 format**

Use this exact logical header contract:

```swift
struct ConvertedMeshHeader {
    let magic: UInt32          // e.g. 0x5A4D5348 = "ZMSH"
    let formatVersion: UInt16  // 1
    let vertexStride: UInt16   // 12 for position-only v1
    let vertexCount: UInt32
    let indexCount: UInt32
    let indexWidth: UInt16     // 4 for UInt32
    let materialGroupCount: UInt16
    let boundsMin: SIMD3<Float>
    let boundsMax: SIMD3<Float>
}
```

Payload ordering: header, packed Float32 XYZ positions, UInt32 indices, material-group records. All integer fields are little-endian. Validate every index is `< vertexCount`, all vertices are finite, triangle count is non-zero, and bounds are finite/non-degenerate.

- [ ] **Step 4: Add a Swift-side round-trip self-check entry point**

Expose a small deterministic fixture function in the source that can be exercised by the later CI fixture path without proprietary data.

- [ ] **Step 5: Run tests and verify GREEN**

- [ ] **Step 6: Commit**

```bash
git add Sources/ZombiesIOS/ConvertedAssets/ConvertedMeshFormat.swift Tools/tests/test_converted_asset_architecture.py
git commit -m "feat: add native converted mesh format"
```

---

### Task 3: Transactional Package Store and Validator

**Files:**
- Create: `Sources/ZombiesIOS/ConvertedAssets/ConvertedPackageValidator.swift`
- Create: `Sources/ZombiesIOS/ConvertedAssets/ConvertedPackageStore.swift`
- Extend: `Tools/tests/test_converted_asset_architecture.py`

**Interfaces:**
- Produces: `ConvertedPackageValidator.validate(at:) throws -> ConvertedTranzitManifest`
- Produces: `ConvertedPackageStore.beginStaging() throws -> URL`, `promoteStaging() throws`, `activeManifest() -> ConvertedTranzitManifest?`

- [ ] **Step 1: Add failing tests**

Assert the validator rejects `complete == false`, unsupported manifest versions, missing world/collision/material/weapon files, and that promotion uses a staging directory plus atomic replacement semantics.

- [ ] **Step 2: Verify RED**

- [ ] **Step 3: Implement package validation**

Validation order:

1. Read `manifest.json`.
2. Require `formatVersion == ConvertedTranzitManifest.packageFormatVersion`.
3. Require `complete == true`.
4. Resolve all relative paths inside the active package root; reject path traversal.
5. Require world mesh, collision mesh, material manifest, weapon mesh files to exist.
6. Decode and validate world/collision meshes.
7. Require collision bounds to overlap world bounds.
8. Require material manifest to decode.
9. Return manifest only if every required check passes.

- [ ] **Step 4: Implement transactional promotion**

Conversion writes only to `ConvertedTranzit.staging`. On successful validation, rename the current active package to a temporary backup, move staging to active, then delete the backup. If promotion fails, restore the backup. Never delete the active package before the replacement has validated.

- [ ] **Step 5: Verify GREEN and commit**

```bash
git add Sources/ZombiesIOS/ConvertedAssets/ConvertedPackageValidator.swift Sources/ZombiesIOS/ConvertedAssets/ConvertedPackageStore.swift Tools/tests/test_converted_asset_architecture.py
git commit -m "feat: add transactional converted package store"
```

---

### Task 4: Import-Time World Geometry Conversion

**Files:**
- Create: `Sources/ZombiesIOS/ConvertedAssets/ConvertedWorldImporter.swift`
- Modify only as needed: `Sources/ZombiesIOS/Services/T6GfxSurfaceMeshExtractor.swift`
- Modify only as needed: `Sources/ZombiesIOS/Services/T6PS3PayloadDecoder.swift` or the existing decoder file containing `T6PS3PayloadDecoder`
- Extend: `Tools/tests/test_converted_asset_architecture.py`

**Interfaces:**
- Produces: `ConvertedWorldImporter.convert(rootURL:resources:stagingURL:progress:) async throws -> ConvertedWorldResult`
- `ConvertedWorldResult` contains mesh path, counts, bounds, source file name, and extraction diagnostics.

- [ ] **Step 1: Add failing test**

Require `ConvertedWorldImporter` to call the existing PS3 decoder and `T6GfxSurfaceMeshExtractor` but write a native `.mesh` output into staging rather than returning a SceneKit node.

- [ ] **Step 2: Verify RED**

- [ ] **Step 3: Implement importer behavior**

Use the existing candidate ordering logic from `TranzitTouchGameplayView`: prefer `zm_transit.ff`, then the area fastfile, then other zombie/common fastfiles. Decode only during import. Select the best real GfxWorld mesh, encode it using `ConvertedMeshFormat`, and validate the encoded file by decoding it back before returning success.

Do not create a fake arena. If no valid world mesh can be reconstructed, throw a typed conversion error naming the source stage and candidate file.

- [ ] **Step 4: Preserve diagnostics**

Record selected file, decoded bytes/chunks, vertex/index counts, bounds, vertex/index source offsets, byte-order descriptor, and whether bounds fallback was used.

- [ ] **Step 5: Verify GREEN and commit**

```bash
git add Sources/ZombiesIOS/ConvertedAssets/ConvertedWorldImporter.swift Sources/ZombiesIOS/Services Tools/tests/test_converted_asset_architecture.py
git commit -m "feat: convert Tranzit world geometry at import time"
```

---

### Task 5: Material and Texture Conversion Contract

**Files:**
- Create: `Sources/ZombiesIOS/ConvertedAssets/ConvertedMaterialImporter.swift`
- Create: `Sources/ZombiesIOS/ConvertedAssets/ConvertedMaterialManifest.swift`
- Extend: `Tools/tests/test_converted_asset_architecture.py`

**Interfaces:**
- Produces: `ConvertedMaterialManifest`, `ConvertedMaterialImporter.convert(...) async throws -> ConvertedMaterialResult`
- Consumes: material identifiers/ranges from world conversion and decoded source payload/assets.

- [ ] **Step 1: Add failing tests**

Require a material manifest type, texture output directory under `textures/`, per-material fallback diagnostics, and no public/static proprietary source asset files.

- [ ] **Step 2: Verify RED**

- [ ] **Step 3: Implement the manifest**

Minimum model:

```swift
struct ConvertedMaterialRecord: Codable {
    let id: Int
    let name: String
    let diffuseTexturePath: String?
    let fallbackReason: String?
    let doubleSided: Bool
}

struct ConvertedMaterialManifest: Codable {
    let materials: [ConvertedMaterialRecord]
}
```

- [ ] **Step 4: Implement the phase-one texture path**

Resolve the diffuse/base-color texture for each material used by the converted world. Decode into a deterministic iOS-readable image file in staging. Use PNG as the first reliable format if no validated GPU-compressed converter exists yet; the runtime can later migrate to ASTC without changing manifest semantics.

A failed non-critical individual material may use a visible fallback material, but the manifest must record `fallbackReason`. Do not report full-fidelity success if any required surface is using fallback.

- [ ] **Step 5: Verify generated texture files before manifest write**

Each texture path must exist, be decodable by `UIImage(contentsOfFile:)` or the project’s platform image loader, and have non-zero dimensions.

- [ ] **Step 6: Verify GREEN and commit**

```bash
git add Sources/ZombiesIOS/ConvertedAssets/ConvertedMaterialImporter.swift Sources/ZombiesIOS/ConvertedAssets/ConvertedMaterialManifest.swift Tools/tests/test_converted_asset_architecture.py
git commit -m "feat: add converted material and texture pipeline"
```

---

### Task 6: Collision Conversion

**Files:**
- Create: `Sources/ZombiesIOS/ConvertedAssets/ConvertedCollisionImporter.swift`
- Extend: `Tools/tests/test_converted_asset_architecture.py`

**Interfaces:**
- Produces: `ConvertedCollisionImporter.convert(world:stagingURL:) throws -> ConvertedCollisionResult`

- [ ] **Step 1: Add failing tests**

Require the collision importer to create `world/collision.mesh`, validate it with `ConvertedMeshFormat`, and explicitly check collision/world bounds overlap.

- [ ] **Step 2: Verify RED**

- [ ] **Step 3: Implement minimal phase-one collision**

Use validated converted world geometry as collision input initially if a dedicated source collision stream is not yet available. Downsample only if necessary for memory/performance, but preserve walkable world coverage and record triangle reduction in diagnostics.

- [ ] **Step 4: Validate bounds overlap and triangle count**

Reject collision if there are zero useful triangles or no spatial overlap with the world mesh.

- [ ] **Step 5: Verify GREEN and commit**

```bash
git add Sources/ZombiesIOS/ConvertedAssets/ConvertedCollisionImporter.swift Tools/tests/test_converted_asset_architecture.py
git commit -m "feat: add converted collision asset"
```

---

### Task 7: One Weapon Conversion

**Files:**
- Create: `Sources/ZombiesIOS/ConvertedAssets/ConvertedWeaponImporter.swift`
- Extend: `Tools/tests/test_converted_asset_architecture.py`

**Interfaces:**
- Produces: `ConvertedWeaponImporter.convert(...) async throws -> ConvertedWeaponResult`
- Output files: `weapons/primary.mesh`, `weapons/primary.material.json`

- [ ] **Step 1: Add failing tests**

Require one native weapon mesh and material manifest path, plus explicit transform metadata for first-person placement.

- [ ] **Step 2: Verify RED**

- [ ] **Step 3: Implement one deterministic weapon selection**

Pick one weapon known to be present in the selected Tranzit source set. Resolve its model/material references, convert its geometry through `ConvertedMeshFormat`, and write a small Codable transform record containing position, Euler rotation, and scale.

- [ ] **Step 4: Validate weapon mesh and material outputs**

No placeholder box/cylinder is allowed as a success path. If the weapon cannot be resolved, fail phase-one conversion with a clear weapon-stage error.

- [ ] **Step 5: Verify GREEN and commit**

```bash
git add Sources/ZombiesIOS/ConvertedAssets/ConvertedWeaponImporter.swift Tools/tests/test_converted_asset_architecture.py
git commit -m "feat: convert first Tranzit weapon asset"
```

---

### Task 8: Conversion Orchestrator, Resume State, and Import Report

**Files:**
- Create: `Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitImporter.swift`
- Create: `Sources/ZombiesIOS/ConvertedAssets/ConvertedImportReport.swift`
- Extend: `Tools/tests/test_converted_asset_architecture.py`

**Interfaces:**
- Produces: `ConvertedTranzitImporter.run(rootURL:resources:progress:) async throws -> ConvertedTranzitManifest`
- Progress stages: scanning, decodingWorld, convertingGeometry, convertingTextures, buildingCollision, convertingWeapon, validating, ready.

- [ ] **Step 1: Add failing tests**

Require the orchestrator to stage outputs, persist stage state, write `diagnostics/import-report.json`, and write `manifest.json` last with `complete = true` only after all required outputs validate.

- [ ] **Step 2: Verify RED**

- [ ] **Step 3: Implement resumable stage markers**

Store an internal staging state file containing source fingerprint and completed stage names. On restart, reuse only stage outputs whose source fingerprint matches and whose files validate; otherwise rerun that stage.

- [ ] **Step 4: Implement orchestration order**

Exact order:

1. validate source access
2. compute fingerprint
3. begin/reuse staging
4. convert world
5. convert materials/textures
6. build collision
7. convert weapon
8. write import report
9. write candidate manifest with `complete = true`
10. validate staging as a complete package
11. promote staging atomically
12. return active manifest

- [ ] **Step 5: Verify GREEN and commit**

```bash
git add Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitImporter.swift Sources/ZombiesIOS/ConvertedAssets/ConvertedImportReport.swift Tools/tests/test_converted_asset_architecture.py
git commit -m "feat: orchestrate resumable Tranzit conversion"
```

---

### Task 9: Runtime Native Package Loader

**Files:**
- Create: `Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitLoader.swift`
- Create: `Sources/ZombiesIOS/ConvertedAssets/ConvertedRuntimePackage.swift`
- Extend: `Tools/tests/test_converted_asset_architecture.py`

**Interfaces:**
- Produces: `ConvertedTranzitLoader.loadActivePackage() throws -> ConvertedRuntimePackage`
- `ConvertedRuntimePackage` contains decoded world mesh, collision mesh, materials/textures, weapon mesh/transform, and manifest.

- [ ] **Step 1: Add failing test**

Require the loader to read only `Application Support/ConvertedTranzit` and not call `T6PS3PayloadDecoder`, `T6GfxSurfaceMeshExtractor`, or open `zm_transit.ff`.

- [ ] **Step 2: Verify RED**

- [ ] **Step 3: Implement package loading**

Call `ConvertedPackageValidator.validate(at:)`, decode native mesh files, resolve texture/material paths inside the package root, and return immutable runtime data structures.

- [ ] **Step 4: Verify GREEN and commit**

```bash
git add Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitLoader.swift Sources/ZombiesIOS/ConvertedAssets/ConvertedRuntimePackage.swift Tools/tests/test_converted_asset_architecture.py
git commit -m "feat: load converted Tranzit package at runtime"
```

---

### Task 10: Converted Scene Renderer

**Files:**
- Create: `Sources/ZombiesIOS/Views/ConvertedTranzitSceneView.swift`
- Modify: `Sources/ZombiesIOS/Views/NativeFPSSceneView.swift` only to keep raw-runtime code isolated; do not route converted assets through the old PS3 decoder.
- Extend: `Tools/tests/test_converted_asset_architecture.py`

**Interfaces:**
- Consumes: `ConvertedRuntimePackage`
- Produces: SwiftUI/SceneKit view for world, material textures, collision, camera/player, and first-person weapon.

- [ ] **Step 1: Add failing test**

Require `ConvertedTranzitSceneView` to consume `ConvertedRuntimePackage`, create textured SceneKit geometry, create collision separately, and attach the converted weapon under the camera.

- [ ] **Step 2: Verify RED**

- [ ] **Step 3: Implement world rendering**

Create `SCNGeometrySource` from native positions and `SCNGeometryElement` from native indices/material groups. Assign materials from `ConvertedMaterialManifest`. Missing texture for a material must render an explicit visible diagnostic fallback, never black/invisible material.

- [ ] **Step 4: Implement collision**

Create physics from the converted collision mesh, not the raw render mesh decoder path. Keep world collision node separate from visual nodes.

- [ ] **Step 5: Attach converted weapon**

Build weapon geometry from the converted mesh/material files and apply the persisted first-person transform under the camera node.

- [ ] **Step 6: Verify GREEN and commit**

```bash
git add Sources/ZombiesIOS/Views/ConvertedTranzitSceneView.swift Sources/ZombiesIOS/Views/NativeFPSSceneView.swift Tools/tests/test_converted_asset_architecture.py
git commit -m "feat: render converted Tranzit package"
```

---

### Task 11: Import UI and Production Routing

**Files:**
- Create: `Sources/ZombiesIOS/Views/ConvertedTranzitImportView.swift`
- Modify: `Sources/ZombiesIOS/ContentView.swift`
- Modify: `Sources/ZombiesIOS/Views/TranzitTouchGameplayView.swift`
- Modify if needed: `Sources/ZombiesIOS/Services/ExternalGameFolderStore.swift`
- Extend: `Tools/tests/test_converted_asset_architecture.py`

**Interfaces:**
- Production route: remembered external BO2 folder -> valid converted package -> converted gameplay; otherwise -> import view.

- [ ] **Step 1: Add failing tests**

Assert that `TranzitTouchGameplayView` no longer calls `decodeT6Payload`, `T6PS3PayloadDecoder`, or `T6GfxSurfaceMeshExtractor` in its gameplay body/path. Assert that `ContentView` or the Tranzit navigation route checks converted package validity before entering gameplay.

- [ ] **Step 2: Verify RED**

- [ ] **Step 3: Implement blocking conversion UI**

Display stage text and progress. On failure, display the exact failing conversion stage and keep the last good package untouched. On success, transition to converted gameplay.

- [ ] **Step 4: Replace production runtime decode path**

`TranzitTouchGameplayView` should receive/load `ConvertedRuntimePackage` and render `ConvertedTranzitSceneView`. Remove or isolate the old `validateStream`/`decodeT6Payload` runtime path so it cannot run during normal gameplay with a valid package.

- [ ] **Step 5: Handle stale source fingerprint**

When the remembered source folder fingerprint differs from the active manifest, route to reconversion before gameplay.

- [ ] **Step 6: Verify GREEN and commit**

```bash
git add Sources/ZombiesIOS/Views/ConvertedTranzitImportView.swift Sources/ZombiesIOS/Views/TranzitTouchGameplayView.swift Sources/ZombiesIOS/ContentView.swift Sources/ZombiesIOS/Services/ExternalGameFolderStore.swift Tools/tests/test_converted_asset_architecture.py
git commit -m "feat: route production gameplay through converted assets"
```

---

### Task 12: CI Converted-Package Fixture and iPhone 17 Visual Gate

**Files:**
- Create: `Sources/ZombiesIOS/Support/CIConvertedPackageFixture.swift`
- Modify: `Sources/ZombiesIOS/Support/CIValidationMode.swift`
- Modify: `Sources/ZombiesIOS/Views/CIGameplayValidationEntryView.swift`
- Modify: `.github/workflows/ios-build.yml`
- Extend: `Tools/tests/test_converted_asset_architecture.py`

**Interfaces:**
- CI mode builds a synthetic converted package through the same native package format and runtime loader used by production.

- [ ] **Step 1: Add failing tests**

Require CI fixture source to create a converted package/manifest and require CI validation view to load `ConvertedTranzitLoader` or a package produced by `CIConvertedPackageFixture`, not inject `CIRuntimeMeshFixture` directly into `NativeFPSSceneView`.

- [ ] **Step 2: Verify RED**

- [ ] **Step 3: Implement synthetic converted package fixture**

Generate redistributable room geometry, a simple generated texture, collision mesh, material manifest, and synthetic weapon mesh into a temporary/Application Support converted package using the same encoder and manifest contract as production.

- [ ] **Step 4: Switch CI validation entry point**

Launch converted runtime renderer through the loader. Keep diagnostics for vertex/index counts, package version, active package path class, scene nodes, camera, and frame heartbeat.

- [ ] **Step 5: Update GitHub Actions gate**

Add:

```bash
python3 -m unittest Tools.tests.test_converted_asset_architecture -v
```

Keep exact iPhone 17 simulator selection. Visual screenshots must come from the converted-package renderer. The existing visual validator remains, but release packaging must occur only if converted-package fixture validation passes.

- [ ] **Step 6: Verify GREEN and commit**

```bash
git add Sources/ZombiesIOS/Support Sources/ZombiesIOS/Views/CIGameplayValidationEntryView.swift .github/workflows/ios-build.yml Tools/tests/test_converted_asset_architecture.py
git commit -m "test: validate converted package rendering on iPhone 17"
```

---

### Task 13: Production Safety Gates and Build Trigger

**Files:**
- Modify: `.github/workflows/ios-build.yml`
- Modify: `.github/build-trigger.txt`
- Extend: `Tools/tests/test_converted_asset_architecture.py`

**Interfaces:**
- Final CI must reject regressions that reintroduce raw PS3 runtime rendering in production gameplay.

- [ ] **Step 1: Add source-boundary assertions**

Workflow/source tests must require:

```text
ConvertedTranzitImporter
ConvertedTranzitLoader
ConvertedTranzitSceneView
Application Support/ConvertedTranzit
```

and reject production gameplay references to:

```text
T6PS3PayloadDecoder()
T6GfxSurfaceMeshExtractor.extract
TRANZIT GFXWORLD DECODE
```

inside `TranzitTouchGameplayView.swift`.

- [ ] **Step 2: Run all source tests locally/in CI**

```bash
python3 -m unittest Tools.tests.test_content_audit -v
python3 -m unittest Tools.tests.test_t6_gfxsurface_layout -v
python3 -m unittest Tools.tests.test_converted_asset_architecture -v
python3 -m unittest Tools.tests.test_ci_visual_validate -v
```

Expected: all PASS.

- [ ] **Step 3: Trigger a full iPhone 17 build**

Append a unique line to `.github/build-trigger.txt`, e.g.:

```text
converted-tranzit-phase1 <timestamp>
```

- [ ] **Step 4: Verify workflow completion**

Required successful steps:

- architecture/unit tests
- source redistribution audit
- simulator build
- exact iPhone 17 converted-package visual validation
- unsigned device build
- compiled source-boundary verification
- built-app redistribution audit
- IPA packaging/upload

- [ ] **Step 5: Inspect CI evidence**

Download the CI validation artifact and confirm screenshots show visible textured geometry and the converted weapon fixture, not just a gray/wireframe raw mesh.

- [ ] **Step 6: Commit final trigger/gate update if needed**

```bash
git add .github/workflows/ios-build.yml .github/build-trigger.txt Tools/tests/test_converted_asset_architecture.py
git commit -m "build: gate IPA on converted Tranzit runtime"
```

---

## Final Verification Checklist

Before calling phase one complete, verify all of the following:

- [ ] `manifest.json` is written last and only with `complete = true` after all required outputs validate.
- [ ] Active package survives app relaunch.
- [ ] Source dump remains external and unchanged.
- [ ] No full BO2 folder copy occurs.
- [ ] No proprietary assets are committed to the repo or bundled in the IPA.
- [ ] Valid converted package bypasses all runtime `zm_transit.ff` decoding.
- [ ] Invalid/missing package routes to conversion UI, never a silent black gameplay scene.
- [ ] One real Tranzit area renders visible geometry and materials from converted assets.
- [ ] Collision is usable.
- [ ] One real weapon model is visible in first person.
- [ ] Import report identifies every fallback or failed required asset.
- [ ] Exact iPhone 17 simulator CI fixture renders the converted-package path successfully.
- [ ] Final unsigned IPA is produced only after all converted-path gates pass.
