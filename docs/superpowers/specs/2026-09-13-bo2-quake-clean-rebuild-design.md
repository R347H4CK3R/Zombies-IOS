# BO2 Quake iOS Clean Rebuild Design

## Goal

Build a clean native iOS game project that consumes a complete user-owned Call of Duty: Black Ops II PS3 dump, converts supported retail content into a native runtime format, embeds the converted content into a final self-contained IPA during a private/local packaging step, and runs without a PS3 emulator or a separate game-data folder after installation.

The public GitHub repository remains code-only and must not contain or publish converted retail BO2 assets. The finished user-specific IPA may contain the user's privately converted BO2 content because it is assembled outside the public repository/release pipeline.

## User-facing success criteria

The project is not called complete until all of the following are true:

1. The converter accepts the whole BO2 PS3 dump as one source tree and discovers all required base-game, multiplayer, and Zombies resources without manual per-file conversion.
2. The converter produces deterministic native runtime assets for maps, geometry, collision, materials, textures, models, animations, sounds, weapons, entities, scripts, UI data, and supported game-mode data.
3. The packaging stage inserts those converted assets directly into `Payload/BO2Quake.app/GameData/` before the final IPA is created.
4. The installed application can launch through the user's normal iOS sideloading/LiveContainer workflow without needing the original PS3 dump, a separate asset folder, or a PS3 emulator.
5. At least the full supported BO2 content set targeted by this project can be selected and launched from inside the app, with correct geometry, collision, material rendering, models, audio, player controls, weapon behavior, game rules, and scripts required for play.
6. Automated simulator/device CI validates the code-only runtime with redistributable synthetic fixtures, while user-specific asset validation runs only in the private packaging workflow.
7. No build is described as the finished game while any required production subsystem below is still represented by a stub, placeholder, diagnostic renderer, synthetic fallback, or unimplemented decoder.

## Architecture

The clean project has four strict layers.

### 1. T6 Source Conversion Layer

A host-side converter reads the complete user-owned PS3 dump and performs all source-format work before packaging. It contains the verified T6 PS3 FastFile/Salsa20/XChunk path, IPAK/LZO decoding, SABS parsing, XAsset table parsing, GfxWorld extraction, Material/GfxImage resolution, XModel/XAnim parsing, WeaponDef parsing, MapEnts/script extraction, and game-mode metadata extraction.

The converter writes a deterministic native asset tree. Retail file formats are never read directly by the production gameplay loop after conversion.

### 2. Native Runtime Asset Format

Converted content is organized under a versioned `GameData` root. Major package families are:

- `worlds/` — world geometry, surface ranges, material references, collision, lightmaps, portals/cells, reflection/light metadata.
- `materials/` — runtime material definitions and texture bindings.
- `textures/` — GPU-ready or transcodable texture payloads with mip metadata.
- `models/` — XModel geometry, LODs, skeletons, collision and placement metadata.
- `animations/` — XAnim tracks, notify events, frame rates, looping metadata.
- `audio/` — decoded/converted SABS banks, aliases and streaming metadata.
- `weapons/` — BO2 weapon definitions, ammo, damage, fire modes, recoil, timing, attachments, viewmodel references and animation bindings.
- `entities/` — MapEnts, triggers, spawn points, objectives, script-model placements and runtime entity properties.
- `scripts/` — supported converted game logic and event bindings.
- `gamemodes/` — multiplayer, Zombies and other supported mode rules/configuration.
- `ui/` — HUD/menu assets and runtime UI definitions where required.
- `manifest.json` — format version, content hashes, dependency graph and validation state.

Every binary structure uses explicit versioning and bounds validation. Runtime indexes use 32-bit or wider identifiers where required; no production asset path inherits old SceneKit-era 16-bit or preview-only limits.

### 3. Native iOS Runtime

The gameplay app is a Swift/Metal host around a Quake III-derived native C runtime facade. The runtime owns simulation, player movement, collision, entity state, combat, weapons, game-mode state, triggers and AI integration. Metal owns rendering.

Production gameplay must not depend on SceneKit. The runtime uses one documented BO2-to-iOS coordinate transform shared by world geometry, collision, entities, models and animation roots.

Subsystems are isolated behind clear APIs:

- World renderer and visibility
- Collision and movement
- Materials/textures/lightmaps
- Static/dynamic models
- Skeletal animation
- Audio mixer/playback
- Weapon/combat system
- Entity/trigger system
- Script/event VM or translated runtime
- Multiplayer game-rules layer
- Zombies systems and AI/navigation
- HUD/menu/touch-input layer
- Save/settings state

### 4. Private Self-contained IPA Packager

The public GitHub workflow builds an unsigned code-only base IPA and synthetic-test artifacts. It never publishes retail BO2 content.

A separate private/local packaging tool takes:

- the validated base app bundle,
- the converted `GameData` tree produced from the user's BO2 dump,
- the converter validation report,

and outputs a user-specific unsigned IPA with `GameData` embedded inside `BO2Quake.app`.

The packager refuses to create a final IPA unless the conversion manifest reports all required production asset classes as complete and all integrity checks pass. The user can then sign that IPA using their existing sideloading method.

## Full-dump conversion behavior

The converter is one-command/one-action from the user's perspective. It receives the BO2 dump root, discovers content recursively, fingerprints inputs, and creates one output tree. It does not require the user to identify individual maps, IPAKs, FastFiles, SABS banks, or model files.

Conversion is resumable and deterministic. Each source file has a content hash and conversion record. Completed unchanged assets are skipped on rerun. Corrupt, unsupported or unresolved assets remain explicit failures in the final report; they are never silently dropped.

The converter generates a machine-readable completion matrix covering at minimum:

- FastFile/XAsset decoding
- All discovered maps
- World geometry/collision
- Surface/material bindings
- Texture/image conversion
- XModels/static-model instances
- XAnim/skeleton data
- SABS/audio aliases
- Weapons/attachments
- MapEnts/triggers/objectives
- Script/runtime bindings
- Multiplayer rules
- Zombies rules/AI content where present
- HUD/menu dependencies

## Rendering and world fidelity

The world pipeline must preserve the complete T6 GfxWorld rather than a preview subset. Runtime indices are 32-bit. Surface ranges remain intact so material assignment is deterministic. Packed world vertices retain position, texture coordinates, lightmap coordinates, normals/tangents and any additional attributes required by the Metal shaders.

Material conversion resolves T6 Material -> MaterialTextureDef -> GfxImage -> IPAK payload dependencies. The renderer supports the BO2 material classes required by converted maps, including opaque, alpha-tested, blended and lightmapped surfaces as encountered in the dump. Unsupported shader semantics must be reported rather than rendered as an unexplained fallback.

Static model draw instances and XModels are loaded into the same coordinate system and visibility pipeline as world surfaces.

## Collision and physics

Collision is derived from the appropriate BO2 collision structures where available, not solely from render triangles. The native runtime supports player capsule collision, floor/step handling, walls, slopes, ladders and relevant trigger volumes. Weapon traces and AI navigation queries use the same runtime world representation.

## Weapons and combat

Weapon definitions are data-driven from converted BO2 WeaponDef/WeaponVariantDef assets. Required behavior includes ammo pools, magazine state, fire cadence, semi/automatic/burst modes as applicable, ADS, reload timing, recoil/spread, damage/range, hit traces/projectiles, weapon switching, viewmodel animation bindings, muzzle/impact effects and audio aliases.

Hard-coded placeholder weapon values may exist only in synthetic CI fixtures and may not be used as production fallbacks.

## Animation

XModel skeletons and XAnim assets are converted into a native skeletal animation format. The runtime supports player/viewmodel/enemy animation playback, blending, looping and notify events needed for gameplay timing. Weapon firing/reload actions must synchronize to converted animation timing rather than arbitrary constants when source animation data exists.

## Audio

SABS/SndBank/SndAlias data is converted into iOS-playable audio plus deterministic alias metadata. Runtime audio supports one-shot effects, weapon sounds, UI sounds, ambience, looping sources, positional audio and music where present and supported.

## Entity scripting and game logic

MapEnts are preserved as structured runtime entities with typed fields. Trigger models, objectives, spawn points, script-models and map-specific event relationships are resolved during conversion.

BO2 gameplay scripts cannot simply execute as PS3 machine code. The clean project therefore defines a translated/compatible event runtime for the subset of script semantics required by supported BO2 content. Any script behavior not yet translated is a completion blocker for the affected map/mode and must appear in the validation report.

## Multiplayer and Zombies

The first completion target is local native gameplay parity for the supported content set, not network-service emulation. Multiplayer rules include teams, spawn selection, scoring, deaths/respawns, objectives and match state required by supported local modes.

Zombies support includes zombie spawning, navigation, targeting, health/damage, round progression, doors/barriers, points/economy, wall buys/mystery-box style interactions where present, perks/power systems where present, map triggers and other converted script-driven mechanics required by the included Zombies maps.

Online matchmaking/backend recreation is outside the initial completion definition unless explicitly added later.

## Touch/UI

The app provides native iPhone touch controls for movement, look, fire, ADS, jump, crouch/prone where required, reload, weapon switch, interact/use, grenade/equipment and pause/menu functions. HUD values come from live native runtime state. Layout must work on the user's target iPhone class without depending on external controller software.

## Validation strategy

Public CI contains no retail assets. It validates:

- parser/format unit tests using synthetic fixtures,
- C runtime tests,
- Swift/C bridge tests,
- Metal rendering with synthetic geometry/materials/models,
- collision/combat/entity tests,
- iPhone simulator launch and screenshot diagnostics,
- unsigned device compilation,
- content-audit checks that reject retail asset extensions/signatures in public artifacts.

Private/local conversion validation uses the user's complete dump and produces a `conversion-report.json`. The final packager checks the report plus runtime smoke tests before creating the self-contained IPA.

## Completion gate

The project may produce development IPAs during implementation, but they must be explicitly labeled development builds. The final deliverable is called the complete game only when:

- the complete intended BO2 dump has been processed,
- all required asset classes resolve without silent omissions,
- all required maps/modes in scope launch,
- rendering/collision/models/audio/weapons/scripts/game rules function without diagnostic placeholders,
- automated code/runtime tests pass,
- private full-content validation passes,
- the self-contained IPA launches without access to the source dump after installation.

No user-side manual conversion, code editing, repeated diagnostic testing or per-map preparation is part of the intended workflow.

## Distribution boundary

The GitHub repository and its public Actions/releases contain only original project code, open-source engine code under its applicable license, tests, documentation, synthetic fixtures and code-only build artifacts. They do not contain Activision/Treyarch retail BO2 maps, models, textures, sound, animation, scripts or converted equivalents.

The user-specific final IPA is assembled privately from the user's own supplied dump and is not uploaded to the public GitHub release pipeline.
