# BO2 Full iOS Conversion Design

## Objective
Convert a user-owned Call of Duty: Black Ops II PS3 dump into a native iOS runtime data set and make the iOS app load and play Campaign, Multiplayer, and Zombies content. Hijacked remains a regression fixture only; it is not the product scope.

## Completion Gate
The project is not complete until an unsigned IPA is produced by CI and runtime validation demonstrates: app startup; external BO2 dump discovery; complete conversion/index pass; representative Campaign, Multiplayer, and Zombies map loading; real map geometry/material/texture rendering; player movement and camera control; collision; weapon firing; audio playback; entity/script execution sufficient for mode startup; and no fallback/placeholder-only rendering in the validated maps.

## Isolation
All work lives on the `bo2-full-conversion` branch. Do not mix DukeX, Halo, RPCS3, or unrelated projects into this branch.

## Content Boundary
The repository and public CI artifacts must not contain the original BO2 dump or extracted expressive game assets. The app consumes the user's local dump through security-scoped Files access. Converted runtime data may be cached locally on-device. CI uses synthetic fixtures and metadata-only regression fixtures unless the user explicitly supplies private build inputs through a non-public mechanism.

## Architecture

### 1. Source discovery and inventory
Generalize the current Zombies-oriented scanner into a full BO2 scanner. Inventory Campaign (`sp_*` and common SP resources), Multiplayer (`mp_*`), Zombies (`zm_*`), common/global assets, localization, scripts, audio banks, FastFiles, IPAKs, and supporting archives. Persist stable file identities and hashes so conversion can resume.

### 2. T6 container decoding
Keep the existing PS3 FastFile decrypt/inflate path and finish stream-order relocation. Decode serialized inline pointers (`0xFFFFFFFF`) through a stream cursor model rather than guessed offsets. Parse asset tables and expose typed records for `GfxWorld`, images, materials, models, animations, sounds, weapon definitions, scripts/rawfiles, collision, entities, and mode metadata.

### 3. Runtime GameData format
Write converted user-local data under an app-managed GameData cache with a versioned manifest. Each zone has independent geometry, material, texture, audio, model, animation, collision, entity, script, and metadata records. All records carry source hashes and converter version for deterministic invalidation/resume.

### 4. Rendering/runtime
Use the existing native Swift/Metal path. Replace bounds/fallback geometry with real T6 world surfaces and static-model instances. Add material/image binding, collision meshes, animation/model loading, audio banks, weapon/entity data, and script/game-mode adapters. Keep fallbacks diagnostic-only and fail validation if a release validation path uses them.

### 5. Game modes
Expose a common zone loader with mode-specific launch descriptors for Campaign, Multiplayer, and Zombies. Mode startup must resolve dependencies from common/global zones plus the requested map zone.

### 6. iOS UX
Remember the selected external BO2 folder using a security-scoped bookmark; never copy the full source dump into app-private storage. Present conversion progress, resumable status, mode/map selection, loading failures, and runtime diagnostics. Touch controls remain native iPhone controls.

### 7. Verification and CI
Unit-test binary parsing with synthetic buffers and sanitized metadata fixtures. Add deterministic converter tests for stream relocation and asset table parsing. Add an iOS simulator smoke path for app startup and synthetic runtime fixtures. Build an unsigned IPA artifact on every manual release workflow. A full-game release claim additionally requires device-side validation against the user's local dump.

## Non-goals
- Emulating PS3 hardware or running the PS3 executable.
- Shipping copyrighted BO2 archives in the public repository or public Actions artifact.
- Treating successful indexing, a black screen, fallback boxes, or one map as completion.
