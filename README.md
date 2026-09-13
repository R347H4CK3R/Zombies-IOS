# Zombies-IOS

Native iOS BO2 runtime targeting iPhone, with a Hijacked-first path built on a Quake III-derived C simulation core and Metal renderer.

## Current milestone: Hijacked native runtime

The app reads a user-owned Call of Duty: Black Ops II PS3 dump directly from the iOS Files location. It does **not** emulate a PS3 and does not execute the original BO2 executable. Instead, the existing T6 decoder decrypts/decompresses the PS3 FastFile, reconstructs validated `GfxWorld` triangles, extracts MapEnts text, writes a versioned user-local runtime package, and loads that package into the native Quake/Metal runtime.

The first supported multiplayer proof target is Hijacked. The importer recognizes:

- `mp_hijacked.ff`
- `mp_hijacked.ipak`
- `mpl_hijacked.all.sabs`

When those files are present in the selected BO2 folder, Zombies-IOS attempts the native Hijacked conversion automatically. Original game files remain in place. Converted expressive runtime data stays in the app's cache and is not committed to this repository or bundled in release IPAs.

### Runtime architecture

1. Persist access to the user-selected BO2 folder with an iOS security-scoped bookmark.
2. Decode signed/encrypted T6 PS3 FastFiles with the existing Salsa20/SHA-1 XChunk path.
3. Reconstruct real T6 `GfxSurface` world triangles.
4. Extract BO2 MapEnts/entity data and multiplayer spawn metadata.
5. Serialize a `bo2world-v1` runtime package using separate 32-bit vertex/index binaries plus versioned metadata.
6. Load the world into the native C runtime under `Engine/Quake3`.
7. Simulate first-person movement, gravity, jumping, and world-floor collision in the C runtime.
8. Render the triangle world directly with Metal through `QuakeGameplayView`.
9. Route iPhone touch move/look/fire/aim/jump/reload input into Quake-style runtime commands.

SceneKit remains only as legacy diagnostic code for older Tranzit experiments; the new Hijacked and CI validation paths use the Quake/Metal runtime.

## Building and public IPA

GitHub Actions runs source/content audits, T6 structure tests, runtime-package contract tests, a native C runtime movement/collision test, an iPhone 17 Simulator render validation, and an unsigned device build.

Successful `main` builds produce:

- Actions artifact: `ZombiesIOS-unsigned-IPA`
- Public release tag: `latest-build`
- Release asset: `ZombiesIOS-unsigned.ipa`

The IPA is unsigned and must be signed by the installation environment before use. The public IPA contains the runtime/converter only; it does not contain BO2 retail assets.

## Quake III source and license

The native runtime is derived from the programming model/math conventions of the id Software Quake III Arena GPL source release. Attribution and license information live under `Engine/Quake3/`. The public source repository is retained alongside released binaries so modified covered source remains available.

Upstream: `id-Software/Quake-III-Arena` on GitHub.

## Content and redistribution boundary

The repository and distributed IPA contain only project-authored material or material with redistribution rights. BO2/PS3 game files are supplied separately by the user through iOS Files or attached storage and are read from that external location; the project does not mirror the selected game folder into app-private storage.

Generated metadata such as hashes, paths, offsets, and compatibility information may be cached separately. Decoded textures, reconstructed map geometry, extracted meshes, converted audio, copied scripts, and similar expressive derivatives remain user-local runtime data and are excluded from release artifacts by default.

See `docs/CONTENT_POLICY.md` for the full contribution, provenance, allow-list, and CI audit rules.

## Important

Do not commit full PS3 dumps, FastFiles, IPAKs, audio banks, ISOs, PKGs, EBOOT/SELF/SPRX binaries, extracted game assets, or other copyrighted game archives to this repository. Converting, renaming, compressing, decompiling, encrypting, or repackaging a third-party asset does not by itself change its copyright status.
