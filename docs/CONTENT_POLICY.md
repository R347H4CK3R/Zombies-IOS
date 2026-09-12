# Zombies-IOS Content and Redistribution Policy

Zombies-IOS is designed so the repository and distributed IPA contain only project-authored material or third-party material with explicit redistribution rights. Compatibility with Call of Duty: Black Ops II PS3 data is provided through user-selected external files; the project does not treat conversion, renaming, compression, decompilation, encryption, or repackaging as a change in ownership or copyright status.

## Allowed repository content

The repository may contain independently authored source code, project-authored UI and touch controls, interoperability parsers, format descriptions, metadata schemas, diagnostics, documentation, synthetic fixtures, and third-party dependencies or assets whose licenses permit redistribution.

Descriptive compatibility identifiers such as BO2, PS3, T6, FastFile names, offsets, hashes, and format metadata may be used when needed for interoperability. They are not a license to redistribute the corresponding game assets.

## Content that must remain user-local

Do not commit or bundle game dumps or copied expressive game content, including FastFiles, IPAKs, SABS/SABL audio banks, ISOs, PKGs, EBOOT/SELF/SPRX binaries, extracted maps, textures, models, animation, dialogue, music, cinematics, scripts, branded menu art, HUD artwork, or substantially equivalent converted derivatives unless the project has documented redistribution rights for that specific material.

Unknown-provenance binary or media content is treated as non-redistributable until its provenance is established.

## External game-folder workflow

Users select their own compatible game folder through the iOS Files document picker or attached storage exposed through Files. Zombies-IOS stores a bookmark/reference for the selected location and reads required files in place through security-scoped access.

The application must not mirror or bulk-copy the selected game folder into Documents, Library, Application Support, the app bundle, GitHub, or another service.

## Derived data classification

Redistribution-safe metadata includes file hashes, sizes, relative paths, classifications, offsets, compatibility/version information, parser diagnostics, and project-authored indexes that do not reproduce protected expression.

Decoded textures, reconstructed map surfaces, extracted meshes, converted audio, copied scripts, and similar expressive derivatives are user-local runtime data. They belong in the local runtime expressive cache and must not be exported into release artifacts by default.

## Third-party provenance

Before adding a third-party asset or binary to the repository, record its source, license, copyright holder when known, and the license term that permits redistribution. A narrow entry may then be added to `Tools/content_allowlist.txt` if the automated audit would otherwise reject it.

An allow-list entry is a technical exception to the scanner, not a legal determination.

## Automated content audit

`Tools/content_audit.py` scans the source tree and built app bundle for prohibited archive extensions, known executable/container signatures, prohibited local-data directories, and suspicious large binaries. The GitHub Actions IPA workflow runs the unit tests and source audit before the build, then scans the generated `.app` before IPA packaging.

When the audit fails, remove the prohibited file or establish its provenance and add the narrowest possible allow-list entry. Do not disable a rule broadly just to make a build pass.

## Runtime caches

Metadata and expressive runtime data use separate cache locations. Expressive data generated from user-supplied game files is local-only and may be deleted and regenerated from the external source.

## Contributions

Contributors must not upload proprietary game archives or extracted copyrighted assets to issues, pull requests, repository branches, test fixtures, release assets, or build inputs. Synthetic test fixtures should be used for parser and audit tests whenever possible.

## Scope

This policy defines the project's technical redistribution boundary. It does not re-license third-party works or provide a legal determination about any particular use. Contributors and distributors are responsible for ensuring they have the rights required for material they distribute.
