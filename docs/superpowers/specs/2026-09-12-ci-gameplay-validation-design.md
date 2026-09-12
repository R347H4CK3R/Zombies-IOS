# CI Gameplay Validation Design

Date: 2026-09-12
Repository: R347H4CK3R/Zombies-IOS

## Goal

Replace the current launch-only iPhone Simulator smoke test with an automated gameplay-render validation path that can catch black-screen, renderer, camera, mesh, crash, and hang regressions before an IPA is packaged.

## Scope

This work adds a deterministic CI-only gameplay fixture and validation harness. It does not embed or redistribute copyrighted BO2 game assets. Production/device behavior continues to load the user's external BO2 game folder.

## Architecture

### 1. CI test mode

Add a dedicated CI launch mode, enabled only by an explicit launch argument or environment variable. In CI mode, the app bypasses the game-folder picker and navigates directly to the Tranzit gameplay view using a small redistributable runtime mesh fixture.

Normal builds must remain unchanged when CI mode is absent.

### 2. Deterministic render fixture

Add a compact synthetic world fixture containing:
- valid vertices and triangle indices;
- obvious depth variation and non-coplanar geometry;
- geometry positioned so the gameplay camera must see it;
- no proprietary BO2 content.

The fixture exists only to prove the complete rendering path: runtime mesh -> SceneKit geometry -> camera -> visible frame.

### 3. Runtime validation signals

Expose CI-only diagnostics from the gameplay renderer, including:
- vertex count;
- index count;
- triangle count;
- scene node count;
- camera position and orientation;
- decoded/world node bounding box;
- whether the world node is inside the camera frustum;
- rendered-frame heartbeat / frame counter;
- process-alive state;
- any SceneKit/Metal-facing initialization failure that can be surfaced by the app.

Write the diagnostics to a small machine-readable report in the simulator app container or emit them in a stable log format that GitHub Actions can collect.

### 4. Visual validation

The simulator workflow should:
1. Build the simulator app.
2. Boot an available iPhone Simulator representative of the target phone class.
3. Install the app.
4. Launch with CI test mode enabled.
5. Wait for the gameplay scene to become ready.
6. Capture at least two screenshots separated by a short interval.
7. Analyze the gameplay viewport rather than only the full frame.
8. Fail if the viewport is overwhelmingly black or effectively blank.
9. Fail if screenshots are identical while runtime diagnostics indicate animation/frame progression should be occurring and that condition represents a hang.
10. Save screenshots and analysis results as artifacts.

The black-screen threshold should be conservative enough to allow dark scenes while still detecting the current all-black renderer failure. The diagnostic wireframe phase may use a bright unlit material to make this check deterministic.

### 5. Crash and hang detection

The workflow should fail if:
- the process exits unexpectedly;
- relaunch is required because of a crash;
- the app does not reach the gameplay-ready state within a fixed timeout;
- frame heartbeat stops;
- diagnostics report zero/invalid geometry;
- the camera is outside a useful viewing relationship to the fixture;
- screenshot analysis detects a blank viewport.

Collect simulator logs when any of these conditions occurs.

### 6. Build gate

The unsigned device IPA must only be packaged after all simulator gameplay-validation checks pass.

The order should be:
1. source/content audits;
2. source-level GfxWorld validation;
3. simulator build;
4. simulator gameplay validation;
5. visual screenshot validation;
6. crash/hang/log validation;
7. unsigned device build;
8. compiled-path verification;
9. content audit of built app;
10. IPA packaging and artifact/release upload.

### 7. CI artifacts

Upload a single validation evidence bundle containing:
- startup screenshot;
- gameplay screenshot 1;
- gameplay screenshot 2;
- visual-analysis report;
- runtime diagnostics report;
- relevant simulator logs;
- simulator/device/runtime metadata.

Keep the IPA artifact separate for convenient downloading.

## Files expected to change

Likely implementation targets:
- `Sources/ZombiesIOS/ZombiesIOSApp.swift` or app-entry routing code for CI mode detection;
- `Sources/ZombiesIOS/ContentView.swift` and/or gameplay navigation for bypassing the folder picker in CI mode;
- `Sources/ZombiesIOS/Views/NativeFPSSceneView.swift` for renderer diagnostics and deterministic camera/world validation hooks;
- `Sources/ZombiesIOS/Views/TranzitTouchGameplayView.swift` for CI fixture injection and ready-state reporting;
- a new small source file for the redistributable CI mesh fixture;
- a new CI visual-analysis script under `Tools/`;
- `.github/workflows/ios-build.yml` for the gameplay validation gate and evidence upload.

Exact file placement should follow existing project patterns discovered during implementation.

## Error handling

CI mode must fail closed. Any missing fixture, zero geometry, invalid index, timeout, missing screenshot, failed screenshot analysis, process crash, or missing diagnostics should fail the workflow and prevent IPA packaging.

Production mode must not expose CI-only behavior accidentally. CI mode should require an explicit launch flag or environment variable.

## Testing strategy

Testing should include:
- unit tests for the screenshot/black-frame analyzer;
- unit tests for fixture validity (non-zero vertices/indices, in-range indices, non-degenerate triangles);
- source-level checks that CI mode is not the default path;
- simulator integration test that reaches gameplay automatically;
- runtime diagnostics assertions;
- screenshot-based visibility assertion;
- process-alive and timeout checks;
- verification that IPA packaging is downstream of all validation steps.

## Success criteria

The design is complete when a GitHub Actions build cannot publish the IPA unless:
- the app enters gameplay automatically in the simulator;
- valid geometry is attached to the scene;
- the camera is positioned to view it;
- frames continue rendering;
- the gameplay viewport contains visible non-black geometry;
- no crash or hang is detected;
- evidence artifacts are uploaded for inspection.

This does not claim that proprietary Tranzit assets themselves are visually correct in CI. It proves the renderer, camera, scene, and gameplay path are functioning, while real BO2 content remains user-supplied at runtime.
