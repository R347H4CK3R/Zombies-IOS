# Tranzit Native Cache Architecture

Date: 2026-09-11
Repository: `R347H4CK3R/Zombies-IOS`

## Goal

Replace repeated runtime PS3 payload scanning with a deterministic one-time import pipeline that converts Tranzit assets into iOS-native cache files. The original BO2 folder remains external and untouched. Converted assets live inside the app's Application Support directory and are reused on subsequent launches.

The target outcome is a recognizable, textured Tranzit world with substantially faster startup and much clearer diagnostics than the current runtime heuristic scanner.

## User Requirements

- Keep the original BO2/PS3 folder in place. Do not copy the source folder into app storage.
- Store converted cache data inside the app, under Application Support.
- Automatically rebuild cache entries when source files change.
- Preserve and continue using the last known-good cache if a rebuild fails.
- Convert geometry, UVs, materials, and textures rather than stopping at a flat untextured mesh.
- Prefer a deterministic conversion pipeline over repeated runtime heuristic scans.
- Surface exact stage/count diagnostics instead of generic failure messages.

## Architecture Overview

Data flow:

`BO2 source folder -> source fingerprint -> PS3 decoder -> XAsset resolver -> geometry converter -> material/texture converter -> staging cache -> validator -> atomic promotion -> renderer`

The importer performs expensive PS3-specific work once. The renderer consumes only the native cache format after conversion.

## Cache Location and Layout

The cache root lives under Application Support, for example:

```text
Application Support/
  TranzitCache/
    active/
      world.meshbin
      materials.json
      textures/
      manifest.json
    staging/
      ...
```

`active/` is the last known-good cache. `staging/` is disposable and is never used for gameplay until validation succeeds.

The original BO2 source folder is read directly through its persisted external-folder access mechanism and is never copied wholesale into Application Support.

## Source Fingerprinting and Automatic Rebuilds

The importer fingerprints the relevant source files using:

- relative source path
- file size
- modification timestamp
- cache schema version

The manifest stores those values. On launch:

1. If the manifest matches the current source and the active cache validates, load the cache immediately.
2. If source metadata differs, start an automatic rebuild into `staging/`.
3. Continue using the previous `active/` cache while conversion runs.
4. Validate staging completely.
5. Atomically replace `active/` only after successful validation.
6. If rebuild or validation fails, discard staging, keep the previous active cache, and show a warning.

This prevents a partial or failed import from making the map unusable.

## Native Cache Components

### `world.meshbin`

Contains the native world representation required by the renderer:

- vertex positions
- normals
- UV coordinates
- index buffer
- submesh ranges
- per-submesh material IDs
- world bounds
- optional simplified collision geometry metadata

The binary format should be versioned and deterministic.

### `materials.json`

Contains material records and submesh bindings:

- stable material ID
- material/XAsset name when available
- diffuse/base-color texture reference
- normal-map reference
- specular reference
- alpha/cutout mode
- basic sampler/wrap information
- submesh-to-material mapping

The first implementation does not attempt to emulate every T6 shader. It supports the subset needed for recognizable rendering: diffuse/base color, alpha/cutout, normal maps, and an approximate specular/roughness mapping.

### `textures/`

Contains converted iOS-ready texture assets.

Preferred order:

1. KTX2/ASTC when a reliable conversion path is available.
2. A simpler decoded image representation for unsupported formats or transitional implementation stages.

Texture conversion failures must not invalidate otherwise-valid world geometry. Affected submeshes receive a diagnostic fallback material.

### `manifest.json`

Contains:

- cache schema version
- source fingerprints
- conversion timestamps/durations
- source asset counts
- converted surface count
- vertex count
- triangle count
- material count
- texture total/success/failure counts
- warnings
- validation state

## Import Stages

### 1. Decode PS3 FastFile Data

Use the existing T6 PS3 FastFile decoding path to produce decoded zone/XAsset data. The importer owns this work; gameplay no longer performs broad payload scanning after a cache exists.

### 2. Resolve XAssets Deterministically

Use the parsed XAsset table as the primary entry point rather than scanning the full payload for structures on every launch.

Resolve at minimum:

- `GfxWorld`
- world surfaces/submeshes
- vertex/index streams
- `Material`
- `GfxImage`

Heuristic scanning may remain as a development fallback only when deterministic references are unavailable, but it must not be the normal runtime path.

### 3. Convert World Geometry

For each valid world surface:

- decode PS3 big-endian fields
- resolve vertex and index ranges
- decode positions
- decode normals when available
- decode UVs
- validate every index against its vertex range
- record material binding
- append into native shared buffers and submesh ranges

The converter must reject corrupt ranges without discarding unrelated valid surfaces.

### 4. Convert Materials

Resolve material references and map them to a reduced native material model suitable for SceneKit/Metal.

Unsupported shader behavior degrades to the nearest safe approximation instead of aborting the import.

### 5. Convert Textures

Resolve `GfxImage` data and decode supported PS3 formats, including compressed block formats and any required endian/swizzle/tile transforms.

Initial support should prioritize the formats encountered by Tranzit rather than implementing every theoretical T6 texture format up front.

Each texture conversion reports success or a specific failure reason.

### 6. Write Staging Cache

Write all converted files under `staging/`. No cache file is promoted individually.

### 7. Validate

Validation must verify at minimum:

- cache schema version is supported
- files are readable and structurally complete
- vertex/index buffers are in range
- every submesh references valid ranges
- every material reference resolves or explicitly uses a fallback
- texture dimensions/formats are valid
- required world-content thresholds are met
- manifest counts match actual cache contents

### 8. Atomic Promotion

After successful validation, replace the active cache atomically. The previous active cache must remain intact until promotion succeeds.

## Renderer Integration

Replace the renderer's single flat `T6RuntimeMesh` concept with a native cached-world model containing:

- shared vertex/index buffers
- submesh descriptors
- material table
- texture table
- bounds/collision metadata

Each submesh binds its own material. Missing textures use a visible diagnostic fallback without removing valid geometry.

The renderer should not invoke the PS3 decoder once a valid native cache exists.

## Collision Strategy

Do not create full SceneKit physics directly from every rendered triangle if that materially increases startup time or memory usage.

Prefer a simplified collision representation derived from the converted world data. Rendering fidelity and collision complexity are separate concerns.

## Runtime State and Diagnostics

The UI should expose concrete stage progress and counts, for example:

```text
GFXWORLD 1384 SURFACES
62491 VERTICES
103882 TRIANGLES
417 MATERIALS
356/389 TEXTURES
```

Useful stage names include:

- SOURCE CHECK
- DECODING FASTFILE
- RESOLVING XASSETS
- CONVERTING WORLD
- CONVERTING MATERIALS
- CONVERTING TEXTURES
- VALIDATING CACHE
- CACHE READY
- REBUILD FAILED / USING PREVIOUS CACHE

Failures must identify the stage and, when possible, the asset or source file involved.

## Error Handling

- A geometry error in one surface should skip that surface when safe and record a warning.
- A texture failure should use a fallback material and not invalidate valid geometry.
- A staging validation failure must never replace active cache.
- A failed automatic rebuild leaves the last known-good cache active.
- If no valid active cache exists and the rebuild fails, the app reports the exact import failure rather than silently substituting a fake world.

## Determinism

Given identical source files and importer/cache versions, output should be deterministic enough that counts, submesh ordering, material IDs, and cache metadata remain stable.

This simplifies debugging and regression testing.

## Testing Strategy

Tests should cover:

- source fingerprint equality and invalidation
- automatic rebuild after a changed source file
- preservation of active cache after failed rebuild
- staging-to-active atomic promotion
- mesh vertex/index range validation
- invalid submesh rejection without corrupting valid submeshes
- material reference validation
- missing texture fallback behavior
- texture metadata validation
- deterministic output metadata for identical input
- renderer loading entirely from native cache after successful conversion
- no wholesale copy of the source BO2 folder into Application Support

Where direct PS3 fixtures are too large for the repository, use small synthetic binary fixtures that exercise endian conversion, ranges, submeshes, UVs, material bindings, and validator failures.

## Initial Delivery Scope

The first implementation targets:

1. Native cache infrastructure and manifest/fingerprinting.
2. Deterministic `GfxWorld` geometry conversion.
3. UV and per-surface material IDs.
4. Material conversion.
5. Diffuse/base-color texture conversion.
6. Normal/specular support where encountered and practical.
7. SceneKit/Metal material binding from cached assets.
8. Automatic background rebuild and last-known-good behavior.
9. Precise progress/error diagnostics.

Full T6 shader emulation, complete effects/lighting parity, animation systems, and unrelated BO2 asset categories are explicitly out of scope for this phase.

## Success Criteria

The design is successful when:

- Tranzit can be loaded from a native cache without rescanning the PS3 payload during normal gameplay startup.
- Real converted world geometry is rendered with UV-driven per-surface textures/materials.
- A second launch with unchanged source files uses the cache directly and starts substantially faster.
- Changing a relevant BO2 source file automatically triggers a staged rebuild.
- A failed rebuild leaves the previous playable cache intact.
- Diagnostics report exact converted counts and the specific failing stage when conversion is incomplete.
