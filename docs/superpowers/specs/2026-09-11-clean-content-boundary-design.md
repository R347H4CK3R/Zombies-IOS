# Clean Content Boundary Architecture

Date: 2026-09-11
Repository: `R347H4CK3R/Zombies-IOS`
Status: Approved design, implementation not yet started

## Purpose

Restructure Zombies-IOS so the repository and distributed IPA contain only project-authored code and assets that are safe to redistribute, while retaining compatibility with user-supplied Call of Duty: Black Ops II PS3 game data stored outside the app bundle.

This design does not attempt to alter the copyright status of third-party works. It creates a strict technical boundary so third-party copyrighted game archives and expressive assets are not redistributed by this project.

## Goals

- Keep proprietary BO2/PS3 game content out of Git history going forward and out of IPA build products.
- Preserve the existing native iOS engine, touch controls, parsers, scanners, compatibility code, and runtime-loading work.
- Continue allowing the user to select and use a legally obtained external game folder through iOS Files or attached storage.
- Avoid copying the entire selected game folder into app-private storage.
- Classify generated data so metadata/cache artifacts can be distinguished from extracted expressive game assets.
- Fail CI when prohibited archive or asset classes are accidentally introduced.
- Document provenance and contribution rules clearly enough that future contributors do not accidentally bundle proprietary data.

## Non-goals

- Re-licensing, de-copyrighting, or changing ownership of Activision/Treyarch content.
- Shipping BO2 maps, textures, models, audio, scripts, executables, FastFiles, IPAKs, PKGs, ISOs, or equivalent extracted content in the repository or IPA.
- Removing interoperability with BO2 PS3 data.
- Rewriting working parsers merely because they reference BO2/T6 formats by name.

## Architecture

### 1. Redistributable Application Layer

The repository and IPA may contain:

- Independently authored Swift/Objective-C/C/C++ code.
- UI and touch-control code created for Zombies-IOS.
- Parsers and format readers written for interoperability.
- Generic shaders and rendering code authored for the project.
- Project-authored placeholder/test geometry, textures, sounds, and fixtures.
- Documentation and schema definitions.
- Metadata structures that do not reproduce protected expressive content.

This layer must not require proprietary game assets to exist at build time.

### 2. External Game-Data Layer

Third-party game data remains outside the repository and app bundle. The existing document/folder picker and security-scoped access model remains the supported path.

The app may read user-selected files from:

- iOS Files locations.
- Attached USB storage exposed through Files.
- Other security-scoped file-provider locations supported by iOS.

The app must not silently upload these files to GitHub or another service. It must not copy the whole selected game folder into application storage. Persistent folder access, when available, should use a security-scoped bookmark or equivalent reference rather than bulk duplication.

### 3. Runtime-Derived Data Layer

Derived data is split into two classes.

#### A. Redistributable metadata

Examples:

- File hashes.
- Sizes.
- Relative paths.
- Asset-type classifications.
- Offsets and index records.
- Compatibility/version information.
- Parser diagnostics.
- Project-authored schemas and lookup structures.

This data may be cached locally and may be committed only when it does not reproduce protected content.

#### B. User-local expressive derivatives

Examples include decoded textures, reconstructed map surfaces, extracted meshes, converted game audio, copied scripts, or other output that substantially reproduces original game expression.

These outputs must remain user-local and be excluded from Git and release artifacts. The application may generate them from the user's own data when needed for runtime use, but they are not distributable project assets by default.

## Source and Asset Audit

Implementation must audit the current repository for:

- Binary blobs and archives.
- Executables or console modules.
- `.ff`, `.ipak`, `.pak`, `.pkg`, ISO/image formats, and similar game-content containers.
- Extracted textures, audio, models, scripts, cinematics, map data, fonts, logos, and branding copied from third-party games.
- Test fixtures that embed substantial proprietary byte ranges.
- Generated caches accidentally tracked by Git.

Each item is classified as:

1. Project-authored / redistribution-safe.
2. Third-party with an explicit compatible license.
3. Metadata-only / non-expressive interoperability data.
4. User-local proprietary derivative: exclude from source and releases.
5. Unknown provenance: exclude until provenance is established.

No file is considered safe merely because it was converted, renamed, compressed, encrypted, decompiled, or repackaged.

## Build and CI Guard

Add a repository script and CI step that scans tracked files and the assembled app bundle before release packaging.

The guard should detect at minimum:

- Prohibited game/archive extensions.
- ELF/SELF/EBOOT/PKG/ISO-style binary signatures where practical.
- Known T6/BO2 asset containers and suspicious game-content filenames.
- Oversized binary blobs not explicitly allow-listed.
- Generated extraction/cache directories.
- Known proprietary branding/art asset paths.

The guard should use a small explicit allow-list for legitimate project binaries or fixtures rather than broad exclusions.

A release build must fail when prohibited content is found.

The CI scan is a safeguard, not a legal determination. Passing the scan only means the repository satisfies the project's technical content policy.

## Git Hygiene

Update `.gitignore` to cover local game data and generated expressive derivatives, including scanner/runtime cache directories and common console/archive formats.

Provide a clearly named local-data root convention so developers can work with game files without accidentally tracking them.

Do not rewrite repository history automatically as part of the first implementation pass. If the audit identifies proprietary material in prior commits, history cleanup should be handled as a separate destructive maintenance operation because it can invalidate clones and existing commit references.

## Runtime Loading Rules

- Game-data discovery begins from a user-selected external folder.
- Security-scoped access is acquired only while the app needs the external location.
- The app may build lightweight metadata indexes in app storage.
- Whole source folders are not mirrored into app storage.
- Expressive conversions required for performance may be cached locally but must be placed under an ignored/non-exported cache location.
- A cache record should retain enough source identity information (for example, size/hash/mtime) to invalidate stale conversions when the user's source changes.
- Errors should distinguish missing source data, unsupported format, decode failure, cache failure, and permission loss.

## Branding and Presentation

Audit visible names, icons, logos, screenshots, textures, fonts, and menu artwork.

Project-authored compatibility labels such as "BO2 PS3" or "T6" may remain where they are descriptive interoperability references. Copied logos, key art, HUD textures, character art, weapon art, or branded menu assets must not ship unless there is a valid redistribution right.

Where needed, replace presentation assets with original Zombies-IOS artwork or neutral project-authored placeholders.

## Documentation

Add a content policy describing:

- What may be committed.
- What must remain local.
- How users supply their own game data.
- That converted/copied proprietary assets are not automatically safe to redistribute.
- How to add a third-party asset with license/provenance evidence.
- How CI content-gate failures are resolved.

The README should point to this policy and retain the existing warning against committing full PS3 dumps and game archives.

## Planned Components

Implementation is expected to touch or add the following areas, subject to the repository audit:

- `.gitignore`
- `README.md`
- `.github/workflows/...` IPA/build workflow
- `Scripts/` or `Tools/` content-audit utility
- `docs/CONTENT_POLICY.md` or equivalent
- External-folder persistence/import services
- Runtime cache path/classification helpers
- Tests/fixtures for the content scanner

Existing T6/PS3 parsers should remain unless the audit finds embedded proprietary payloads in source or fixtures.

## Testing Strategy

### Repository-policy tests

Create synthetic fixtures proving the scanner:

- Accepts ordinary project source and project-authored test data.
- Rejects representative prohibited extensions.
- Rejects representative binary signatures when extensions are misleading.
- Rejects generated proprietary-derivative directories.
- Honors narrow allow-list entries.

Fixtures must be synthetic and must not embed copied game assets.

### App behavior tests

Verify:

- External folder selection still works.
- Persisted access can be restored where iOS permits it.
- The application does not recursively copy the selected folder into app storage.
- Metadata indexes can be rebuilt from the external source.
- Missing/revoked external access produces a clear user-visible failure.
- Runtime-local caches can be deleted and regenerated.

### Release verification

Before an IPA artifact is accepted:

1. Run source-tree content audit.
2. Build the app.
3. Scan the built `.app` payload.
4. Package the IPA only if both scans pass.
5. Record the audit result in CI output.

## Error Handling

The project should fail closed for distribution: if provenance or classification of a bundled binary/resource is unknown, CI rejects it until explicitly reviewed.

Runtime use of user-owned external data should fail gracefully and tell the user whether the issue is permission, missing files, unsupported data, parsing, or local cache generation.

## Security and Privacy

- No automatic upload of selected game folders.
- No hard-coded external file paths.
- Security-scoped resources are released after use.
- Metadata reports should avoid embedding unnecessary source-file bytes.
- Logs should avoid dumping large proprietary byte ranges.

## Migration Sequence

1. Audit tracked files and current build resources.
2. Add content policy and provenance rules.
3. Harden `.gitignore`.
4. Add the source-tree content scanner and synthetic tests.
5. Add the built-app/IPA content scan to CI.
6. Refactor runtime cache locations if any expressive derivatives currently enter distributable paths.
7. Verify external-folder loading still functions without whole-folder copying.
8. Replace/remove any bundled presentation assets whose redistribution rights are not established.
9. Build and verify a clean IPA.

## Success Criteria

The migration is complete when:

- A clean checkout builds without any proprietary BO2/PS3 archive or asset present in the repository.
- The generated IPA contains no bundled BO2/PS3 proprietary game archives or copied expressive assets.
- BO2 PS3 compatibility still works using user-supplied external data.
- The selected game folder is not bulk-copied into app-private storage.
- Local runtime-generated expressive caches are ignored and excluded from distribution.
- CI rejects representative prohibited content and scans both source and built app payloads.
- Documentation states the content boundary and provenance requirements.

## Legal Scope

This architecture is a technical risk-reduction and redistribution-boundary design, not a legal opinion. Copyright, trademark, contract, anti-circumvention, and other rules can vary by jurisdiction and facts. The project should only redistribute material for which it has adequate rights or permission.