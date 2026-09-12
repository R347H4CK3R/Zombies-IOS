# CI Gameplay Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent ZombiesIOS from publishing an IPA unless an automated iPhone Simulator run reaches gameplay, renders visible geometry, stays alive, and produces inspectable validation evidence.

**Architecture:** Add an explicit CI-only launch mode that bypasses the BO2 folder picker and injects a small redistributable runtime mesh into the existing Tranzit gameplay path. Expose deterministic renderer diagnostics, capture gameplay screenshots in GitHub Actions, analyze the viewport for black-frame failure, collect logs/metadata, and make IPA packaging downstream of all validation gates.

**Tech Stack:** SwiftUI, SceneKit, XCTest/source assertions where practical, Python 3 + Pillow for screenshot analysis, GitHub Actions, `xcrun simctl`, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-12-ci-gameplay-validation-design.md`

## Global Constraints

- Do not embed or redistribute copyrighted BO2 assets.
- Production/device mode must continue to read the user's external BO2 folder in place.
- CI behavior must require an explicit launch argument or environment variable and must not be the default path.
- CI validation must fail closed on missing fixture, invalid geometry, timeout, crash, hang, missing diagnostics, missing screenshots, or black/blank gameplay output.
- IPA packaging must happen only after simulator gameplay validation succeeds.
- Validation artifacts must include screenshots, machine-readable diagnostics, simulator logs, and runtime metadata.

---

## File Structure

- Create `Sources/ZombiesIOS/Support/CIValidationMode.swift`: one responsibility—detect the explicit CI launch mode and define stable CI environment/argument names.
- Create `Sources/ZombiesIOS/Support/CIRuntimeMeshFixture.swift`: one responsibility—construct a small valid redistributable `T6RuntimeMesh` fixture with visible depth and non-degenerate triangles.
- Create `Sources/ZombiesIOS/Support/CIRenderDiagnostics.swift`: one responsibility—store and serialize renderer readiness/mesh/camera/frame diagnostics in CI mode.
- Modify `Sources/ZombiesIOS/ZombiesIOSApp.swift`: route to CI gameplay entry only when CI mode is enabled.
- Modify `Sources/ZombiesIOS/ContentView.swift`: preserve existing production import flow and expose a CI-only direct gameplay entry initializer/view path without touching bookmark behavior.
- Modify `Sources/ZombiesIOS/Views/TranzitTouchGameplayView.swift`: allow injected mesh/CI mode and skip BO2 decoding only in CI mode.
- Modify `Sources/ZombiesIOS/Views/NativeFPSSceneView.swift`: emit renderer diagnostics, frame heartbeat, camera/world bounds, and frustum visibility data.
- Create `Tools/ci_visual_validate.py`: inspect screenshots and diagnostics; fail on black/blank viewport, missing readiness, or stalled frames.
- Create `Tools/tests/test_ci_visual_validate.py`: unit-test thresholding and report validation.
- Modify `.github/workflows/ios-build.yml`: replace launch-only smoke test with CI gameplay validation, evidence upload, and packaging gate.

---

### Task 1: CI Mode Detection and Deterministic Mesh Fixture

**Files:**
- Create: `Sources/ZombiesIOS/Support/CIValidationMode.swift`
- Create: `Sources/ZombiesIOS/Support/CIRuntimeMeshFixture.swift`
- Modify: `Sources/ZombiesIOS/ZombiesIOSApp.swift`

**Interfaces:**
- Produces: `enum CIValidationMode { static var isEnabled: Bool }`
- Produces: `enum CIRuntimeMeshFixture { static func make() -> T6RuntimeMesh }`
- Consumes: existing `T6RuntimeMesh` initializer used by runtime extractors.

- [ ] **Step 1: Write source-level assertions for explicit CI activation**

Add a workflow/source validation check that fails unless `CIValidationMode` contains a stable explicit key such as `ZOMBIESIOS_CI_GAMEPLAY=1` or launch argument `--ci-gameplay-validation`, and fails if `isEnabled` defaults to `true`.

- [ ] **Step 2: Implement CI mode detection**

Create `CIValidationMode.swift` with logic equivalent to:

```swift
enum CIValidationMode {
    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ci-gameplay-validation") { return true }
        return ProcessInfo.processInfo.environment["ZOMBIESIOS_CI_GAMEPLAY"] == "1"
    }
}
```

No other launch path may enable this mode.

- [ ] **Step 3: Implement a valid redistributable mesh fixture**

Create `CIRuntimeMeshFixture.make()` returning a `T6RuntimeMesh` with at least 8 vertices and 12 triangles forming an obvious room/pyramid-like scene around the camera target. Requirements:

```swift
let vertices: [SIMD3<Float>] = [
    SIMD3(-8, 0, -8), SIMD3(8, 0, -8), SIMD3(8, 0, 8), SIMD3(-8, 0, 8),
    SIMD3(-4, 6, -4), SIMD3(4, 6, -4), SIMD3(4, 6, 4), SIMD3(-4, 6, 4)
]
```

Indices must only reference valid vertices, include floor/walls/roof-like depth, and contain no degenerate triangle. Set a diagnostic byte-order label such as `"CI-FIXTURE"`.

- [ ] **Step 4: Add fixture validity checks**

In the workflow, compile-time/source checks or a lightweight Swift check must ensure:

```text
vertices.count >= 8
indices.count >= 36
indices.count % 3 == 0
max(index) < vertices.count
triangle area > epsilon for every triangle
```

- [ ] **Step 5: Route app entry based on CI mode**

Modify `ZombiesIOSApp` so normal users still receive `ContentView()` and CI receives a dedicated CI gameplay entry view. Do not modify bookmark/import state in production mode.

- [ ] **Step 6: Build simulator target**

Run:

```bash
xcodegen generate
xcodebuild -project ZombiesIOS.xcodeproj -scheme ZombiesIOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/SimulatorDerivedData CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/ZombiesIOS/Support/CIValidationMode.swift Sources/ZombiesIOS/Support/CIRuntimeMeshFixture.swift Sources/ZombiesIOS/ZombiesIOSApp.swift .github/workflows/ios-build.yml
git commit -m "test: add deterministic CI gameplay mode"
```

---

### Task 2: CI Gameplay Injection Without BO2 Folder Access

**Files:**
- Modify: `Sources/ZombiesIOS/ContentView.swift`
- Modify: `Sources/ZombiesIOS/Views/TranzitTouchGameplayView.swift`

**Interfaces:**
- Consumes: `CIValidationMode.isEnabled`
- Consumes: `CIRuntimeMeshFixture.make() -> T6RuntimeMesh`
- Produces: a CI-only gameplay entry that never opens `fileImporter`, bookmarks, or PS3 file decoding.

- [ ] **Step 1: Add a CI-only initializer/path to `TranzitTouchGameplayView`**

Introduce an explicit configuration type or optional injected mesh path. Preferred shape:

```swift
enum TranzitGameplaySource {
    case production(loadedArea: TranzitLoadedArea, rootURL: URL, sharedContainers: [TranzitLoadedResource], audioBankCount: Int)
    case ci(mesh: T6RuntimeMesh)
}
```

`TranzitTouchGameplayView` should consume one `source` value instead of relying on implicit globals.

- [ ] **Step 2: Preserve the production path exactly**

For `.production`, keep current `validateStream()`, `prefetchInitialBurst()`, `decodeT6Payload()`, runtime banners, and external-folder behavior unchanged.

- [ ] **Step 3: Implement CI path**

For `.ci(mesh:)`:

```swift
runtimeMesh = mesh
runtimeStatus = "CI GAMEPLAY READY"
decodedSourceName = "CI-FIXTURE"
decodedSeed = 0xC1
runtimeError = nil
```

Do not call `validateStream()`, `FastFileStreamReader`, `T6PS3PayloadDecoder`, or any folder APIs.

- [ ] **Step 4: Create a minimal CI entry view**

Add a small internal view in `ContentView.swift` or a focused new file if needed:

```swift
struct CIGameplayValidationEntryView: View {
    var body: some View {
        NavigationStack {
            TranzitTouchGameplayView(source: .ci(mesh: CIRuntimeMeshFixture.make()))
        }
    }
}
```

The simulator launch must land in gameplay immediately.

- [ ] **Step 5: Verify production UI remains unchanged**

Source checks must still find `Choose BO2 Game Folder`, `.fileImporter(... .folder ...)`, bookmark storage, and no copying of the game directory.

- [ ] **Step 6: Build simulator target**

Run the same simulator build command from Task 1. Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/ZombiesIOS/ContentView.swift Sources/ZombiesIOS/Views/TranzitTouchGameplayView.swift
git commit -m "feat: inject CI gameplay fixture without BO2 assets"
```

---

### Task 3: Renderer Diagnostics and Frame Heartbeat

**Files:**
- Create: `Sources/ZombiesIOS/Support/CIRenderDiagnostics.swift`
- Modify: `Sources/ZombiesIOS/Views/NativeFPSSceneView.swift`

**Interfaces:**
- Produces: `struct CIRenderDiagnostics: Codable`
- Produces: JSON written in CI mode to a stable app-container path, for example `Documents/ci-render-diagnostics.json`.
- Required fields: `vertexCount`, `indexCount`, `triangleCount`, `sceneNodeCount`, `cameraPosition`, `worldBoundsMin`, `worldBoundsMax`, `worldInFrustum`, `frameCount`, `ready`, `lastFrameTimestamp`.

- [ ] **Step 1: Define diagnostics schema**

Create codable helper structs:

```swift
struct CIVector3: Codable { let x: Float; let y: Float; let z: Float }
struct CIRenderDiagnostics: Codable {
    var vertexCount: Int
    var indexCount: Int
    var triangleCount: Int
    var sceneNodeCount: Int
    var cameraPosition: CIVector3
    var worldBoundsMin: CIVector3
    var worldBoundsMax: CIVector3
    var worldInFrustum: Bool
    var frameCount: Int
    var ready: Bool
    var lastFrameTimestamp: Double
}
```

- [ ] **Step 2: Add safe atomic-ish file write helper**

Write JSON to a temporary file then replace the final file to avoid partial reads:

```swift
let tmp = url.appendingPathExtension("tmp")
try data.write(to: tmp, options: .atomic)
try? FileManager.default.removeItem(at: url)
try FileManager.default.moveItem(at: tmp, to: url)
```

Only run in CI mode.

- [ ] **Step 3: Emit geometry and camera diagnostics after world creation**

After `buildDecodedWorld()`, record runtime mesh counts, scene node count, camera position, and world bounding box. Use `SCNNode.boundingBox` or `SCNGeometry.boundingBox` for min/max.

- [ ] **Step 4: Add frame heartbeat**

In `step(_:)`, increment a CI-only frame counter on every display-link callback and update `lastFrameTimestamp`. Persist diagnostics no more than about 4 times per second to avoid excess I/O.

- [ ] **Step 5: Add frustum visibility check**

Once the SCNView exists, use SceneKit's frustum helper where available, e.g. `view.isNode(worldNode, insideFrustumOf: cameraNode)`, and persist `worldInFrustum`.

- [ ] **Step 6: Define ready state**

Set `ready = true` only when all are true:

```text
vertexCount >= 3
triangleCount >= 1
world node exists
camera exists
worldInFrustum == true
frameCount >= 10
```

- [ ] **Step 7: Build simulator target**

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/ZombiesIOS/Support/CIRenderDiagnostics.swift Sources/ZombiesIOS/Views/NativeFPSSceneView.swift
git commit -m "test: emit CI renderer diagnostics and heartbeat"
```

---

### Task 4: Screenshot and Diagnostics Analyzer

**Files:**
- Create: `Tools/ci_visual_validate.py`
- Create: `Tools/tests/test_ci_visual_validate.py`

**Interfaces:**
- Produces CLI:

```bash
python3 Tools/ci_visual_validate.py \
  --screenshot-1 build/ci-gameplay/gameplay-1.png \
  --screenshot-2 build/ci-gameplay/gameplay-2.png \
  --diagnostics build/ci-gameplay/ci-render-diagnostics.json \
  --report build/ci-gameplay/visual-report.json
```

- Exit code `0` = pass, nonzero = fail.

- [ ] **Step 1: Write failing unit tests for black-frame detection**

Test pure-black and near-black synthetic images and ensure they fail.

```python
def test_black_viewport_fails(tmp_path):
    image = Image.new("RGB", (400, 800), (0, 0, 0))
    path = tmp_path / "black.png"
    image.save(path)
    assert analyze_image(path)["passes_visibility"] is False
```

- [ ] **Step 2: Write passing unit test for visible fixture geometry**

Generate a dark image with a substantial bright polygon/line region and assert it passes.

- [ ] **Step 3: Implement viewport crop**

Crop away the upper HUD and lower touch controls so analysis focuses on the central gameplay viewport. Use proportional coordinates instead of device-specific pixels, for example left `5%`, right `95%`, top `18%`, bottom `72%`.

- [ ] **Step 4: Implement visibility metrics**

Calculate at least:

```text
mean luminance
fraction of pixels with luminance > 18/255
fraction of pixels with luminance > 40/255
luminance standard deviation
```

Pass only when the viewport is not overwhelmingly black. Conservative initial gate:

```text
bright_fraction_18 >= 0.02
and luminance_stddev >= 4.0
```

The exact threshold should be tuned against the bright CI fixture, not against proprietary gameplay screenshots.

- [ ] **Step 5: Validate diagnostics JSON**

Fail unless:

```text
ready == true
vertexCount >= 3
indexCount >= 3
triangleCount >= 1
worldInFrustum == true
frameCount >= 10
lastFrameTimestamp > 0
```

- [ ] **Step 6: Add frame-stall comparison**

Compare the two screenshots and diagnostics. If screenshots are byte-identical or pixel-identical and frame count is not increasing between captures, fail as a hang. Do not fail merely because a static CI scene produces similar frames when heartbeat advances.

- [ ] **Step 7: Emit machine-readable report**

Write JSON containing every metric, each pass/fail predicate, diagnostics summary, and final `passed` boolean.

- [ ] **Step 8: Run tests**

Run:

```bash
python3 -m unittest Tools.tests.test_ci_visual_validate -v
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Tools/ci_visual_validate.py Tools/tests/test_ci_visual_validate.py
git commit -m "test: detect black simulator gameplay frames"
```

---

### Task 5: GitHub Actions Gameplay Validation Gate

**Files:**
- Modify: `.github/workflows/ios-build.yml`

**Interfaces:**
- Consumes: `--ci-gameplay-validation` or `ZOMBIESIOS_CI_GAMEPLAY=1`
- Consumes: `Tools/ci_visual_validate.py`
- Produces artifact: `ZombiesIOS-ci-validation-evidence`

- [ ] **Step 1: Keep existing source/content audits first**

Do not weaken the redistribution audit or existing GfxWorld source validation.

- [ ] **Step 2: Boot a specific iPhone simulator class when available**

Prefer an iPhone Plus/large-screen simulator if installed; otherwise select the newest available iPhone. Record selected name, UDID, runtime, and OS version to `build/ci-gameplay/simulator-metadata.txt`.

- [ ] **Step 3: Install and launch in explicit CI mode**

Launch with:

```bash
xcrun simctl launch --console-pty "$DEVICE_UDID" "$BUNDLE_ID" --ci-gameplay-validation
```

or set the documented environment variable through `simctl spawn`/launch-compatible configuration if needed. Capture console output to `build/ci-gameplay/app-console.log`.

- [ ] **Step 4: Wait for gameplay readiness with timeout**

Poll the app container for `ci-render-diagnostics.json` for up to 30 seconds. Fail if the file never appears or `ready` never becomes true.

Resolve the app data container with:

```bash
APP_DATA="$(xcrun simctl get_app_container "$DEVICE_UDID" "$BUNDLE_ID" data)"
```

Copy diagnostics from the known Documents path into `build/ci-gameplay/`.

- [ ] **Step 5: Capture two gameplay screenshots**

After readiness:

```bash
xcrun simctl io "$DEVICE_UDID" screenshot build/ci-gameplay/gameplay-1.png
sleep 2
xcrun simctl io "$DEVICE_UDID" screenshot build/ci-gameplay/gameplay-2.png
```

Copy diagnostics again after the second screenshot.

- [ ] **Step 6: Verify process remains alive**

Use `xcrun simctl spawn "$DEVICE_UDID" launchctl print system` or a second `simctl launch`/process check to verify the bundle process has not exited. Any crash or missing process fails validation.

- [ ] **Step 7: Collect simulator logs**

Collect relevant recent logs:

```bash
xcrun simctl spawn "$DEVICE_UDID" log show --style compact --last 2m --predicate 'process == "ZombiesIOS"' > build/ci-gameplay/simulator.log || true
```

Logs are evidence, not a substitute for explicit readiness checks.

- [ ] **Step 8: Run visual analyzer**

Install Pillow if needed:

```bash
python3 -m pip install --user pillow
python3 Tools/ci_visual_validate.py \
  --screenshot-1 build/ci-gameplay/gameplay-1.png \
  --screenshot-2 build/ci-gameplay/gameplay-2.png \
  --diagnostics build/ci-gameplay/ci-render-diagnostics.json \
  --report build/ci-gameplay/visual-report.json
```

Any nonzero exit must stop the job before the device build begins.

- [ ] **Step 9: Upload evidence even on failure**

Use `if: always()` for `actions/upload-artifact@v4`, artifact name `ZombiesIOS-ci-validation-evidence`, including screenshots, diagnostics, analysis report, logs, and simulator metadata.

- [ ] **Step 10: Keep device IPA build downstream of validation**

The `Build unsigned device app` step must remain after all simulator validation commands. No `continue-on-error` may be applied to gameplay validation.

- [ ] **Step 11: Run workflow YAML/source checks locally where possible**

At minimum run the Python unit tests and simulator build; inspect YAML for ordering.

- [ ] **Step 12: Commit**

```bash
git add .github/workflows/ios-build.yml
git commit -m "ci: gate IPA on rendered gameplay validation"
```

---

### Task 6: End-to-End CI Run, Evidence Review, and Release Gate Verification

**Files:**
- Modify if needed based on evidence: the focused files from Tasks 1-5 only.
- No unrelated refactors.

**Interfaces:**
- Produces successful GitHub Actions run with both `ZombiesIOS-ci-validation-evidence` and `ZombiesIOS-unsigned-IPA` artifacts.

- [ ] **Step 1: Trigger a manual build**

Use the repository's manual trigger mechanism (`.github/build-trigger.txt` or workflow dispatch).

- [ ] **Step 2: Review job steps**

Confirm these complete successfully in order:

```text
Build iPhone Simulator app
Boot/launch CI gameplay simulator
Wait for CI gameplay readiness
Capture gameplay screenshots
Validate gameplay visuals and diagnostics
Upload CI validation evidence
Build unsigned device app
Package IPA
Upload Actions artifact
```

- [ ] **Step 3: Download and inspect evidence artifact**

Verify `gameplay-1.png` and `gameplay-2.png` visibly show the synthetic fixture in the gameplay viewport rather than the folder picker or a black frame.

- [ ] **Step 4: Inspect `visual-report.json`**

Confirm `passed: true`, nonzero brightness variance, valid geometry counts, `worldInFrustum: true`, and frame heartbeat progression.

- [ ] **Step 5: Inspect simulator logs**

Confirm there is no app crash, SceneKit initialization failure, or fatal runtime error during the validation window.

- [ ] **Step 6: Negative-gate verification**

Temporarily force one failing condition on an isolated branch or throwaway commit (for example black material + zero ambient emission or `ready = false`) and verify the workflow stops before IPA packaging. Revert immediately after proof.

- [ ] **Step 7: Re-run clean build**

Trigger one final clean run after reverting the negative test. Expected: validation passes and IPA artifact is generated.

- [ ] **Step 8: Final commit if evidence-driven tuning was required**

```bash
git add <only files changed by evidence-driven fixes>
git commit -m "test: finalize CI gameplay validation thresholds"
```

- [ ] **Step 9: Completion criteria**

Do not call this work complete until all are true:

```text
CI launches directly into gameplay
fixture geometry is visible in simulator screenshots
renderer diagnostics report ready=true
frame heartbeat advances
black-frame analyzer passes
crash/hang checks pass
validation evidence artifact uploads
IPA packaging is skipped on failed validation
clean successful run produces the IPA artifact
```
