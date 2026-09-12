# Tranzit Converted Asset Cache Design

## Goal

Replace the fragile runtime PS3-format rendering path with a one-time import-and-convert pipeline. The app will read the user's own BO2 PS3 dump from an externally selected folder, convert only the required Tranzit assets into a stable iOS/runtime-friendly package, store that package under the app's Application Support directory, and render gameplay from the converted package on subsequent launches.

The production success criterion for phase one is: after one successful import, reopening the app must load a recognizable Tranzit area directly from converted assets without decoding `zm_transit.ff` during gameplay. The rendered area must include visible world geometry, visible textures/materials, usable collision, and one weapon model.

## Constraints

- Original BO2 dump remains external and untouched.
- No proprietary BO2 assets are committed to GitHub or bundled in the distributed IPA.
- Converted assets are created locally from the user's own dump and stored in the app sandbox.
- The installed `.app` bundle remains immutable; generated content is stored in `Application Support/ConvertedTranzit`.
- Conversion must be restartable and resumable so interruption does not require a full re-import.
- Runtime gameplay must not depend on PS3 fastfile parsing when a valid converted package exists.
- Phase one is deliberately limited to one recognizable Tranzit area, essential world geometry, textures/materials, collision, and one weapon model.

## Architecture

### 1. Source Importer

The importer receives the remembered external BO2 game-folder URL already used by the project. It validates access and identifies the minimum source containers needed for the selected Tranzit area.

Responsibilities:
- Resolve and retain secure access to the selected external folder.
- Locate required Tranzit fastfiles and referenced asset containers.
- Compute a source fingerprint from file identity, size, and modification metadata.
- Compare that fingerprint with the converted-package manifest.
- Skip conversion when the package version and source fingerprint are unchanged.
- Never copy the entire BO2 folder into app storage.

### 2. Conversion Pipeline

Conversion runs outside the gameplay render loop and writes deterministic outputs into a staging directory. Each converter validates its output before the package becomes active.

Phase-one converters:

#### World geometry converter
- Reuse the existing BO2/T6 decode and GfxWorld extraction logic only as an import-time source reader.
- Convert reconstructed positions and indices into a simple little-endian native mesh file.
- Store explicit vertex/index counts, bounds, and format version in a mesh header.
- Reject meshes with invalid indices, non-finite coordinates, zero useful triangles, or unusable bounds.

#### Material and texture converter
- Resolve material references needed by converted world surfaces.
- Decode source texture data into an iOS-readable representation.
- Prefer GPU-friendly compressed textures when a reliable conversion path exists; otherwise use a deterministic decoded image format supported by the app runtime.
- Emit a compact material manifest mapping converted mesh surface/material IDs to converted texture files and basic render properties.
- Use a visible fallback material only when a specific source material cannot be converted, and record that fallback in diagnostics.

#### Collision converter
- Build collision data from the converted world mesh or validated source collision geometry.
- Store collision separately from render geometry so rendering does not depend on SceneKit generating a giant triangle physics body at load time.
- Validate that the collision bounds overlap the world bounds.

#### Weapon converter
- Convert one selected player weapon model for the first milestone.
- Persist its mesh, material references, and local transform metadata in the same package format.

### 3. Converted Package Store

Root path:

`Application Support/ConvertedTranzit/`

Versioned package layout:

```text
ConvertedTranzit/
  manifest.json
  world/
    area.mesh
    collision.mesh
  materials/
    materials.json
  textures/
    ...converted texture files...
  weapons/
    primary.mesh
    primary.material.json
  diagnostics/
    import-report.json
```

The package is written transactionally:
- Conversion writes into a temporary staging directory.
- Every required phase-one output is validated.
- `manifest.json` is written last.
- Only after validation succeeds is the staging directory promoted to the active package.
- A failed or interrupted conversion must not replace the last known-good package.

## Manifest

`manifest.json` is the authoritative package contract. Minimum fields:

- package format version
- source fingerprint
- source area name
- creation timestamp
- converter/build version
- world mesh path and counts
- world bounds
- collision path
- material manifest path
- converted texture count
- weapon asset path
- completion state
- per-stage diagnostics summary

A package is runtime-loadable only when the manifest version is supported, the package is marked complete, required files exist, and basic integrity checks pass.

## Runtime Loader

At gameplay launch:

1. Check for a valid converted Tranzit manifest.
2. If valid, load the native world mesh, material manifest, textures, collision, and weapon directly from Application Support.
3. Build the gameplay scene from those converted assets.
4. Do not decode `zm_transit.ff` or run the PS3 GfxWorld extractor in the gameplay path.
5. If no valid converted package exists, route the user into import/conversion instead of silently falling back to a black production scene.

The existing PS3 runtime decoder remains available only as import infrastructure until the converted pipeline fully replaces it.

## Native Mesh Format

Use a deliberately small versioned binary format instead of serializing SceneKit objects.

Header fields:
- magic
- format version
- vertex count
- index count
- vertex stride
- index width
- bounds min/max
- material-group count

Payload:
- packed positions and any phase-one attributes required by the renderer
- index buffer
- material-group ranges

The first version should avoid unnecessary fields. Normals, UVs, tangents, and additional attributes are added only when the corresponding source conversion is validated and needed by the material pipeline.

## UI and Progress

When conversion is required, the app shows a blocking import/conversion status rather than entering gameplay with an empty scene. Status should expose meaningful stages such as scanning, decoding world, converting geometry, converting textures, building collision, converting weapon, validating, and ready.

On failure, show the failing stage and preserve the last successful package. The detailed import report remains in the app's diagnostics directory for debugging.

## Error Handling

- Missing source files: fail before destructive package changes.
- Lost folder access: request the user re-select the external game folder.
- Unsupported/undecodable asset: record exact asset/stage; fail only if it is required for the phase-one package.
- Texture conversion failure: use an explicit diagnostic fallback only for non-critical individual materials; do not report full-fidelity success.
- Geometry or collision integrity failure: reject the candidate package.
- Interrupted conversion: leave staging data disposable and preserve the active package.
- Package version mismatch: reconvert from the external source.

## Testing Strategy

### Unit tests
- Manifest validation and version rejection.
- Source fingerprint change detection.
- Native mesh encoder/decoder round-trip.
- Invalid index and non-finite vertex rejection.
- Transactional package promotion behavior.
- Runtime loader chooses converted package when valid and refuses incomplete packages.

### Import fixture tests
Use only redistributable synthetic fixtures in CI. They must prove that the converter can create a complete native package and that the runtime loader can render that converted package without PS3 runtime decoding.

### iPhone 17 simulator validation
CI should launch a converted-package fixture path rather than the old raw runtime path and capture screenshots plus diagnostics. The visual gate must verify non-black output and package-loader diagnostics.

### Real BO2 validation
Real proprietary BO2 assets cannot live in public CI. The user's device/imported dump remains the validation source for actual Tranzit fidelity. The app's import report must make it possible to determine exactly which real assets converted successfully or failed.

## Phase-One Deliverable

Phase one is complete only when all of the following are true:

- The user selects or reuses the remembered external BO2 folder.
- The app converts the minimum required Tranzit assets into `Application Support/ConvertedTranzit`.
- The converted package survives app relaunches.
- Gameplay loads the converted package without decoding `zm_transit.ff` at runtime.
- One recognizable Tranzit area renders with visible materials/textures.
- Collision is usable for player movement.
- One weapon model is visible in first person.
- Missing required converted assets produce a clear error instead of a black screen.

## Deferred Work

The following are explicitly deferred until the phase-one package is stable: zombies/AI, animation systems, audio, scripting, effects, dynamic props, additional weapons, full map streaming, and full-map asset completeness.
