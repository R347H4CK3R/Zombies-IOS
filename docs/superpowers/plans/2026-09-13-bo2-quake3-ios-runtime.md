# BO2 Quake III iOS Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the production Hijacked gameplay path with a native Quake III-derived iOS runtime that consumes user-local converted BO2 PS3 data and is built/published as an unsigned IPA by GitHub Actions.

**Architecture:** Preserve the existing T6 FastFile/Salsa20/GfxWorld decoding layer. Add a versioned `BO2RuntimePackage` boundary, a C runtime facade under `Engine/Quake3`, and a SwiftUI/Metal host that sends touch input to the C runtime. CI uses only synthetic redistributable geometry while the real Hijacked package is generated on-device from the user's own dump.

**Tech Stack:** Swift 5, C99, Metal/MetalKit, XcodeGen, iOS 17+, Python unittest for source/format validation, GitHub Actions, GPLv2 Quake III source attribution.

**Spec:** `docs/superpowers/specs/2026-09-13-bo2-quake3-ios-runtime-design.md`

## Global Constraints

- Deployment target remains iOS 17.0.
- The BO2 source folder is read in place through security-scoped access and is never bulk-copied into app storage.
- Retail `.ff`, `.ipak`, `.sabs`, textures, models, audio, maps, and other expressive BO2 payloads must never be committed or bundled in release artifacts.
- Converted expressive data is user-local and belongs only under `runtime-expressive-cache`.
- Preserve the existing T6 PS3 FastFile decrypt/decompress path and real `GfxSurface` extraction code.
- Production Hijacked rendering must not depend on SceneKit after the runtime migration gate is enabled.
- GitHub Actions must still produce `ZombiesIOS-unsigned.ipa` and update the public `latest-build` release.

---

### Task 1: Add deterministic BO2 runtime package model

**Files:**
- Create: `Sources/ZombiesIOS/Services/BO2RuntimePackage/BO2RuntimePackage.swift`
- Create: `Sources/ZombiesIOS/Services/BO2RuntimePackage/BO2RuntimePackageWriter.swift`
- Create: `Tools/tests/test_bo2_runtime_package_contract.py`

**Interfaces:**
- Consumes: `T6RuntimeMesh` from `T6MeshPreviewExtractor.swift`.
- Produces: `BO2RuntimePackage`, `BO2RuntimeVertex`, `BO2RuntimeSpawn`, and `BO2RuntimePackageWriter.write(mesh:entities:sourceName:) -> URL`.

- [ ] **Step 1: Write the failing contract test**

```python
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class RuntimePackageContractTests(unittest.TestCase):
    def test_package_is_versioned_and_uses_32_bit_indices(self):
        text = (ROOT / "Sources/ZombiesIOS/Services/BO2RuntimePackage/BO2RuntimePackage.swift").read_text()
        self.assertIn('static let formatVersion: UInt32 = 1', text)
        self.assertIn('let indices: [UInt32]', text)
        self.assertIn('let spawns: [BO2RuntimeSpawn]', text)

    def test_writer_targets_expressive_cache(self):
        text = (ROOT / "Sources/ZombiesIOS/Services/BO2RuntimePackage/BO2RuntimePackageWriter.swift").read_text()
        self.assertIn('RuntimeCachePolicy.expressiveDirectory()', text)
        self.assertNotIn('Bundle.main', text)
```

- [ ] **Step 2: Run the test and verify it fails because the files do not exist**

Run: `python3 -m unittest Tools.tests.test_bo2_runtime_package_contract -v`

- [ ] **Step 3: Implement the Codable package and writer**

Use a versioned JSON metadata header plus binary vertex/index files in a directory named `bo2world-v1-<source-hash>`. Convert the current `UInt16` mesh indices to `UInt32` on write. Use one documented coordinate system for package data and reject empty geometry.

- [ ] **Step 4: Run the package test and content audit**

Run: `python3 -m unittest Tools.tests.test_bo2_runtime_package_contract Tools.tests.test_content_audit -v`

- [ ] **Step 5: Commit**

`git commit -m "feat: add BO2 runtime package format"`

### Task 2: Add Hijacked discovery and conversion path

**Files:**
- Create: `Sources/ZombiesIOS/Models/BO2MapTarget.swift`
- Create: `Sources/ZombiesIOS/Services/BO2MapRuntimeLoader.swift`
- Modify: `Sources/ZombiesIOS/Services/PS3DumpScanner.swift`
- Modify: `Sources/ZombiesIOS/ContentView.swift`
- Create: `Tools/tests/test_hijacked_runtime_contract.py`

**Interfaces:**
- Consumes: scanner `ScanReport`, `T6PS3PayloadDecoder`, `T6GfxSurfaceMeshExtractor`, package writer.
- Produces: `BO2MapRuntimeSession` for `mp_hijacked.ff` and later maps.

- [ ] **Step 1: Write a source-contract test requiring `mp_hijacked.ff`, `mp_hijacked.ipak`, and `mpl_hijacked.all.sabs` discovery without adding them to the repository**.
- [ ] **Step 2: Extend scanning so recognized multiplayer map resources are retained alongside the existing Zombies manifest without weakening the retail-content audit**.
- [ ] **Step 3: Implement `BO2MapRuntimeLoader` to select Hijacked, decode the signed PS3 FastFile, extract the real `GfxWorld` mesh, and write the user-local runtime package**.
- [ ] **Step 4: Add a Hijacked entry in `ContentView` when the three source files exist**.
- [ ] **Step 5: Run contract and existing T6 layout tests**.
- [ ] **Step 6: Commit** with `feat: add Hijacked runtime conversion path`.

### Task 3: Add Quake III-derived runtime facade

**Files:**
- Create: `Engine/Quake3/COPYING.txt`
- Create: `Engine/Quake3/README.md`
- Create: `Engine/Quake3/zq3_runtime.h`
- Create: `Engine/Quake3/zq3_runtime.c`
- Modify: `Sources/ZombiesIOS/Support/T6InflateBridge.h`
- Modify: `project.yml`
- Create: `Tools/tests/test_quake3_runtime_contract.py`

**Interfaces:**
- Produces C functions `zq3_init`, `zq3_load_world`, `zq3_set_input`, `zq3_step`, `zq3_get_player_state`, and `zq3_shutdown`.
- Uses Quake III GPL conventions for user-command movement/vector math and retains GPL notices/source access in the public repository.

- [ ] **Step 1: Add a failing contract test requiring the six C facade functions, GPL attribution, and Metal dependency in `project.yml`**.
- [ ] **Step 2: Add the full GPLv2 license and attribution document identifying the upstream id Software Quake III source release**.
- [ ] **Step 3: Implement the C runtime state, Quake-style movement command structure, fixed-step integration, gravity/jump, and triangle-world collision API boundary**.
- [ ] **Step 4: Expose the C header through the existing bridging header and add `MetalKit.framework` to XcodeGen dependencies**.
- [ ] **Step 5: Run the contract tests and source audit**.
- [ ] **Step 6: Commit** with `feat: add Quake III runtime facade`.

### Task 4: Replace production SceneKit host with Metal/Quake host

**Files:**
- Create: `Sources/ZombiesIOS/EngineBridge/QuakeRuntimeController.swift`
- Create: `Sources/ZombiesIOS/Views/QuakeGameplayView.swift`
- Modify: `Sources/ZombiesIOS/Views/TranzitTouchGameplayView.swift`
- Modify: `Sources/ZombiesIOS/Views/CIGameplayValidationEntryView.swift`
- Modify: `Sources/ZombiesIOS/Support/CIRenderDiagnostics.swift`
- Create: `Tools/tests/test_quake_gameplay_source_boundary.py`

**Interfaces:**
- Consumes: `BO2RuntimePackage` and C `zq3_*` facade.
- Produces: a `MTKView`-backed `UIViewRepresentable` accepting move/look/fire/aim/jump/reload input.

- [ ] **Step 1: Add a failing test that forbids `NativeFPSSceneView` in the production Hijacked/CI Quake runtime path**.
- [ ] **Step 2: Implement `QuakeRuntimeController` lifecycle and 60 Hz input submission**.
- [ ] **Step 3: Implement a Metal triangle renderer backed by package vertices/indices while the C runtime owns simulation/player state**.
- [ ] **Step 4: Reuse the current SwiftUI touch HUD, routing controls to `QuakeGameplayView`**.
- [ ] **Step 5: Convert CI fixture geometry into a synthetic `BO2RuntimePackage` and emit diagnostics without SceneKit types**.
- [ ] **Step 6: Commit** with `feat: run gameplay through Quake Metal host`.

### Task 5: Collision, entities, and spawn mapping

**Files:**
- Create: `Sources/ZombiesIOS/Services/BO2RuntimePackage/BO2EntityParser.swift`
- Modify: `Engine/Quake3/zq3_runtime.c`
- Modify: `Sources/ZombiesIOS/Services/BO2MapRuntimeLoader.swift`
- Create: `Tools/tests/test_bo2_entity_mapping.py`

**Interfaces:**
- Produces normalized key/value entities and spawn origins/angles from BO2 MapEnts text.
- C runtime consumes collision triangles and initial spawn position.

- [ ] **Step 1: Add synthetic tests for `worldspawn`, `mp_dm_spawn`, and `mp_tdm_spawn` parsing**.
- [ ] **Step 2: Implement quoted-key/value parser without embedding retail entity data**.
- [ ] **Step 3: Add spawn extraction and BO2-to-runtime coordinate conversion**.
- [ ] **Step 4: Implement player capsule-vs-world triangle collision with floor/step handling in the runtime**.
- [ ] **Step 5: Run all Python tests** using `python3 -m unittest discover -s Tools/tests -v`.
- [ ] **Step 6: Commit** with `feat: add BO2 entities and world collision`.

### Task 6: Harden CI and public IPA publication

**Files:**
- Modify: `.github/workflows/ios-build.yml`
- Modify: `.github/build-trigger.txt`
- Modify: `README.md`

**Interfaces:**
- CI proves the native Quake runtime builds and renders synthetic geometry without requiring retail BO2 content.

- [ ] **Step 1: Add all new package/runtime contract tests to the workflow**.
- [ ] **Step 2: Replace SceneKit-specific source gates with Quake/Metal runtime gates**.
- [ ] **Step 3: Keep iPhone 17 Simulator launch/screenshot validation and require Quake runtime diagnostics**.
- [ ] **Step 4: Keep unsigned `iphoneos` build, IPA packaging, Actions artifact upload, and `latest-build` release upload**.
- [ ] **Step 5: Update README with the user-owned BO2 folder workflow and explicit Quake III GPL attribution/source link**.
- [ ] **Step 6: Change `.github/build-trigger.txt` to trigger the build**.
- [ ] **Step 7: Commit** with `ci: build and publish Quake BO2 iOS runtime`.

### Task 7: Verify build and repair failures

**Files:** Any files implicated by CI failure logs.

- [ ] **Step 1: Inspect the newest `Build iOS IPA` workflow run for the implementation commit**.
- [ ] **Step 2: If a test/compile/simulator step fails, retrieve the job log and identify the first actionable failure**.
- [ ] **Step 3: Patch the minimal root cause, trigger another build, and repeat until the workflow succeeds or an external service limitation prevents further execution**.
- [ ] **Step 4: Verify the successful run contains `ZombiesIOS-unsigned-IPA`**.
- [ ] **Step 5: Verify the public `latest-build` release points at the successful implementation commit and contains `ZombiesIOS-unsigned.ipa`**.
