# Clean Content Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Zombies-IOS repository and distributed IPA contain only project-authored or otherwise redistribution-safe material while preserving runtime compatibility with user-supplied BO2 PS3 data stored outside the app bundle.

**Architecture:** Keep proprietary game data external, read it in place through the existing security-scoped folder workflow, and separate distributable metadata from user-local expressive derivatives. Add a reusable repository/app-bundle content audit, wire it into CI before and after the build, harden ignore rules and documentation, and verify that runtime services do not bulk-copy the selected game folder.

**Tech Stack:** Swift 5, SwiftUI, Foundation security-scoped URLs, XcodeGen, Python 3 standard library, Bash, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-11-clean-content-boundary-design.md`

## Global Constraints

- Do not re-license or claim ownership of third-party game content.
- Do not bundle BO2 maps, textures, models, audio, scripts, executables, FastFiles, IPAKs, PKGs, ISOs, or equivalent extracted content in Git or the IPA.
- Preserve BO2/T6 interoperability using user-selected external files.
- Do not copy the whole selected game folder into app-private storage.
- User-local expressive derivatives must remain local and excluded from source/release artifacts.
- CI must fail closed when bundled binary/resource provenance is unknown.
- Keep the current iOS deployment target at 17.0 and Swift version at 5.0.

---

## File Structure

Create:
- `Tools/content_audit.py` — reusable source-tree and built-app scanner.
- `Tools/tests/test_content_audit.py` — synthetic unit tests for the scanner.
- `docs/CONTENT_POLICY.md` — redistribution/provenance policy.
- `Sources/ZombiesIOS/Services/ExternalGameFolderStore.swift` — persisted security-scoped bookmark ownership for the user-selected source folder.
- `Sources/ZombiesIOS/Services/RuntimeCachePolicy.swift` — central local-only cache path/classification helper.

Modify:
- `.gitignore` — exclude game archives, extracted assets, local source roots, and runtime derivative caches.
- `README.md` — link to policy and clarify external-data model.
- `Sources/ZombiesIOS/Services/DirectFolderImporter.swift` — use the folder-store abstraction without copying source data.
- `Sources/ZombiesIOS/ContentView.swift` — restore/reselect the external folder and surface missing-permission errors through the existing UI state.
- `.github/workflows/ios-build.yml` — call the reusable audit before build and on the built `.app` before IPA packaging.

Do not change parser algorithms unless the audit finds embedded proprietary payload bytes in source or fixtures.

---

### Task 1: Add the content-audit utility and synthetic tests

**Files:**
- Create: `Tools/content_audit.py`
- Create: `Tools/tests/test_content_audit.py`

**Interfaces:**
- Produces: CLI `python3 Tools/content_audit.py <path> [--allowlist Tools/content_allowlist.txt]`
- Produces: `scan_tree(root: pathlib.Path, allowlist: set[str]) -> list[Finding]`
- Produces: `Finding(path: str, reason: str)` dataclass.

- [ ] **Step 1: Write failing unit tests**

Create tests using `unittest` and `tempfile.TemporaryDirectory` that verify:

```python
from pathlib import Path
import tempfile
import unittest

from Tools.content_audit import scan_tree

class ContentAuditTests(unittest.TestCase):
    def test_rejects_prohibited_extension(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "zm_test.ff"
            p.write_bytes(b"synthetic")
            findings = scan_tree(Path(td), set())
            self.assertTrue(any("prohibited extension" in f.reason for f in findings))

    def test_rejects_eboot_signature_name(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "EBOOT.BIN"
            p.write_bytes(b"synthetic")
            findings = scan_tree(Path(td), set())
            self.assertTrue(any("prohibited filename" in f.reason for f in findings))

    def test_rejects_misnamed_elf(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "fixture.dat"
            p.write_bytes(b"\x7fELF" + b"\x00" * 32)
            findings = scan_tree(Path(td), set())
            self.assertTrue(any("ELF signature" in f.reason for f in findings))

    def test_accepts_plain_source(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "Example.swift"
            p.write_text("struct Example {}")
            self.assertEqual(scan_tree(Path(td), set()), [])
```

- [ ] **Step 2: Run the tests and verify they fail before implementation**

Run:

```bash
python3 -m unittest Tools.tests.test_content_audit -v
```

Expected: import or symbol failure because `Tools/content_audit.py` does not yet exist.

- [ ] **Step 3: Implement the scanner**

Implement with only Python standard library. Required rules:

```python
PROHIBITED_EXTENSIONS = {
    ".ff", ".ipak", ".sabs", ".sabl", ".pkg", ".iso", ".xiso",
    ".self", ".sprx", ".psarc", ".pak"
}
PROHIBITED_FILENAMES = {"eboot.bin"}
PROHIBITED_DIR_NAMES = {
    "ps3_game", "raw_dump", "game-data", "game_data",
    "extracted-assets", "extracted_assets", "runtime-expressive-cache"
}
MAX_UNREVIEWED_BINARY_BYTES = 8 * 1024 * 1024
```

Rules:
- Ignore `.git`, build output, and paths explicitly present in an optional newline-delimited allow-list.
- Reject prohibited extension/filename/directory matches case-insensitively.
- Read the first 16 bytes of regular files and reject ELF (`7f 45 4c 46`) and obvious PKG/SELF signatures when detected.
- Treat files over `MAX_UNREVIEWED_BINARY_BYTES` as suspicious when they are not source/text formats and not allow-listed.
- Print one deterministic line per finding and exit 1 when any finding exists; exit 0 otherwise.

- [ ] **Step 4: Run the tests and verify they pass**

```bash
python3 -m unittest Tools.tests.test_content_audit -v
```

Expected: all tests pass.

- [ ] **Step 5: Run the scanner on the current repository**

```bash
python3 Tools/content_audit.py .
```

Expected: either PASS or concrete findings that become inputs to Task 2. Do not suppress findings by widening the allow-list without reviewing the exact file.

- [ ] **Step 6: Commit**

```bash
git add Tools/content_audit.py Tools/tests/test_content_audit.py
git commit -m "feat: add redistribution content audit"
```

---

### Task 2: Audit current tracked content and harden repository exclusions

**Files:**
- Modify: `.gitignore`
- Create only if justified by reviewed safe binary fixtures: `Tools/content_allowlist.txt`
- Remove any currently tracked proprietary/unknown-provenance asset discovered by Task 1.

**Interfaces:**
- Consumes: `Tools/content_audit.py` from Task 1.
- Produces: source tree that passes `python3 Tools/content_audit.py .` without broad exceptions.

- [ ] **Step 1: Expand `.gitignore` with explicit local-only classes**

Add patterns for:

```gitignore
# User-supplied game data and console archives
*.ff
*.ipak
*.sabs
*.sabl
*.pak
*.iso
*.xiso
*.pkg
*.self
*.sprx
*.psarc
EBOOT.BIN
PS3_GAME/
raw_dump/
game-data/
game_data/

# User-local decoded/converted expressive derivatives
runtime-expressive-cache/
extracted-assets/
extracted_assets/
decoded-textures/
decoded-models/
decoded-audio/
decoded-maps/

# Scanner/runtime outputs
scan-output/
local-runtime-cache/
```

Preserve existing Xcode/build ignores.

- [ ] **Step 2: Run the audit and inspect every finding**

```bash
python3 Tools/content_audit.py .
```

For each finding, classify it against the design categories. Delete tracked proprietary/unknown files; only allow-list a file when provenance is explicit and the file is necessary to build/test.

- [ ] **Step 3: Verify tracked-file policy**

```bash
git ls-files | python3 -c 'import sys; bad=[p.strip() for p in sys.stdin if p.lower().endswith((".ff",".ipak",".sabs",".sabl",".iso",".xiso",".pkg",".self",".sprx",".psarc")) or p.strip().lower().endswith("eboot.bin")]; print("\n".join(bad)); raise SystemExit(bool(bad))'
```

Expected: exit 0 with no paths.

- [ ] **Step 4: Re-run audit**

```bash
python3 Tools/content_audit.py .
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add .gitignore Tools/content_allowlist.txt 2>/dev/null || true
git add -u
git commit -m "chore: enforce local-only game asset policy"
```

---

### Task 3: Persist external folder access without copying game data

**Files:**
- Create: `Sources/ZombiesIOS/Services/ExternalGameFolderStore.swift`
- Modify: `Sources/ZombiesIOS/Services/DirectFolderImporter.swift`
- Modify: `Sources/ZombiesIOS/ContentView.swift`

**Interfaces:**
- Produces: `actor ExternalGameFolderStore`
- Produces: `func save(folderURL: URL) throws`
- Produces: `func resolve() throws -> URL`
- Produces: `func clear()`
- Uses security-scoped bookmark data stored in `UserDefaults`; stores no game-file bytes.

- [ ] **Step 1: Add a source-level regression test script for copy prevention**

Extend `Tools/tests/test_content_audit.py` with a repository-source test that reads `DirectFolderImporter.swift` and `ExternalGameFolderStore.swift` and asserts that neither contains `copyItem(`, `replaceItemAt(`, or `Data(contentsOf:)` against the selected root. This is intentionally a coarse guard against reintroducing bulk-copy behavior.

- [ ] **Step 2: Run tests and verify failure**

```bash
python3 -m unittest Tools.tests.test_content_audit -v
```

Expected: failure because `ExternalGameFolderStore.swift` does not exist yet.

- [ ] **Step 3: Implement `ExternalGameFolderStore`**

Use Foundation bookmark APIs:

```swift
actor ExternalGameFolderStore {
    enum StoreError: LocalizedError {
        case bookmarkCreationFailed
        case noSavedFolder
        case staleBookmark
        case cannotAccessFolder
    }

    private let defaults: UserDefaults
    private let key = "externalGameFolderBookmark"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(folderURL: URL) throws
    func resolve() throws -> URL
    func clear()
}
```

`save(folderURL:)` must call `bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)` and write only the bookmark blob to `UserDefaults`.

`resolve()` must call `URL(resolvingBookmarkData:options:.withSecurityScope,relativeTo:nil,bookmarkDataIsStale:&stale)`, reject stale bookmarks, verify the path exists, and return the URL without reading or copying folder contents.

- [ ] **Step 4: Update `DirectFolderImporter`**

Inject/use `ExternalGameFolderStore`. After a successful scan, save the selected folder bookmark. Keep the existing `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` balance and keep returning the original folder URL as `importedAssetsURL`.

- [ ] **Step 5: Update `ContentView` restore flow**

On app startup or before prompting for a new folder, attempt `ExternalGameFolderStore.resolve()`. If the bookmark resolves, rescan/load from that external URL. If resolution fails because access is gone/stale, surface a clear state such as “Game folder access expired — select the folder again” and show the picker rather than falling back to copied app data.

- [ ] **Step 6: Run tests and source assertions**

```bash
python3 -m unittest Tools.tests.test_content_audit -v
python3 Tools/content_audit.py .
```

Expected: PASS.

- [ ] **Step 7: Build locally in CI-equivalent mode when Xcode is available**

```bash
xcodegen generate
xcodebuild -project ZombiesIOS.xcodeproj -scheme ZombiesIOS -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

Expected: build succeeds.

- [ ] **Step 8: Commit**

```bash
git add Sources/ZombiesIOS/Services/ExternalGameFolderStore.swift Sources/ZombiesIOS/Services/DirectFolderImporter.swift Sources/ZombiesIOS/ContentView.swift Tools/tests/test_content_audit.py
git commit -m "feat: persist external game folder access"
```

---

### Task 4: Centralize user-local runtime cache policy

**Files:**
- Create: `Sources/ZombiesIOS/Services/RuntimeCachePolicy.swift`
- Modify only runtime code that writes generated derivatives after audit/search identifies those write sites.

**Interfaces:**
- Produces: `enum RuntimeCachePolicy`
- Produces: `static func metadataDirectory(fileManager: FileManager = .default) throws -> URL`
- Produces: `static func expressiveDirectory(fileManager: FileManager = .default) throws -> URL`
- Produces: `static func clearExpressiveCache(fileManager: FileManager = .default) throws`

- [ ] **Step 1: Add source-level tests for path separation**

Add tests that inspect `RuntimeCachePolicy.swift` and verify metadata and expressive caches use distinct subdirectories and that neither path points into the app bundle or project source tree.

- [ ] **Step 2: Run tests and confirm failure**

```bash
python3 -m unittest Tools.tests.test_content_audit -v
```

Expected: failure because `RuntimeCachePolicy.swift` is absent.

- [ ] **Step 3: Implement cache policy**

Use `FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first` as the root. Required subdirectories:

```text
ZombiesIOS/metadata
ZombiesIOS/runtime-expressive-cache
```

Create directories with intermediate directories enabled and mark the expressive directory as local-only in comments/documentation. Do not expose it through share/export flows.

- [ ] **Step 4: Route any discovered generated expressive writes to `expressiveDirectory()`**

Search for `write(to:)`, `createFile`, `copyItem`, `FileHandle(forWritingTo:)`, and cache-related paths. Only runtime-generated converted material should move to the expressive cache. JSON indexes/hashes may use `metadataDirectory()`.

- [ ] **Step 5: Verify**

```bash
python3 -m unittest Tools.tests.test_content_audit -v
python3 Tools/content_audit.py .
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ZombiesIOS/Services/RuntimeCachePolicy.swift Sources/ZombiesIOS Tools/tests/test_content_audit.py
git commit -m "feat: separate local runtime derivative caches"
```

---

### Task 5: Add content policy and README guidance

**Files:**
- Create: `docs/CONTENT_POLICY.md`
- Modify: `README.md`

**Interfaces:**
- Produces: contributor/user rules referenced by CI failure messages.

- [ ] **Step 1: Write `docs/CONTENT_POLICY.md`**

Required sections:
- Allowed repository content.
- Content that must remain user-local.
- External-folder workflow.
- Derived-data classification.
- Third-party license/provenance evidence requirements.
- CI audit failure resolution.
- Statement that conversion/renaming/compression/decompilation does not itself remove third-party rights.

- [ ] **Step 2: Update README**

Add a “Content and redistribution boundary” section linking `docs/CONTENT_POLICY.md`. Clarify that the IPA is designed to ship without BO2 game assets and the user supplies compatible game data separately through Files/USB.

- [ ] **Step 3: Verify documentation contains no contradictory statements**

```bash
grep -n "CONTENT_POLICY" README.md
grep -n "user-local\|external\|redistribut" docs/CONTENT_POLICY.md
```

Expected: matches for both commands.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/CONTENT_POLICY.md
git commit -m "docs: define game content redistribution boundary"
```

---

### Task 6: Replace ad-hoc CI checks with source and app-bundle audits

**Files:**
- Modify: `.github/workflows/ios-build.yml`

**Interfaces:**
- Consumes: `Tools/content_audit.py`.
- Produces: CI gate before build and after `.app` assembly, before IPA packaging.

- [ ] **Step 1: Add pre-build audit**

Immediately after checkout, run:

```yaml
      - name: Audit repository redistribution boundary
        run: |
          python3 -m unittest Tools.tests.test_content_audit -v
          python3 Tools/content_audit.py .
```

Keep any existing structural assertions needed for the Tranzit decoder, but remove duplicated extension-only checks once the new scanner covers them.

- [ ] **Step 2: Add built-app audit before `Package IPA`**

After the unsigned app is built:

```yaml
      - name: Audit built app redistribution boundary
        shell: bash
        run: |
          set -euo pipefail
          APP_PATH="$(find build/DerivedData/Build/Products/Release-iphoneos -maxdepth 1 -name '*.app' -print -quit)"
          test -n "$APP_PATH"
          python3 Tools/content_audit.py "$APP_PATH"
```

The IPA packaging step must remain after this gate.

- [ ] **Step 3: Validate workflow syntax and scanner behavior**

At minimum:

```bash
python3 -m unittest Tools.tests.test_content_audit -v
python3 Tools/content_audit.py .
```

Then run the GitHub Actions workflow manually.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ios-build.yml
git commit -m "ci: scan source and app bundle for proprietary assets"
```

---

### Task 7: Final clean-build verification

**Files:**
- No new production files unless verification exposes a defect.

**Interfaces:**
- Validates all previous tasks against the approved spec.

- [ ] **Step 1: Re-run policy tests and repository audit**

```bash
python3 -m unittest Tools.tests.test_content_audit -v
python3 Tools/content_audit.py .
```

Expected: PASS.

- [ ] **Step 2: Verify no tracked prohibited file classes**

```bash
git ls-files | grep -Ei '\.(ff|ipak|sabs|sabl|iso|xiso|pkg|self|sprx|psarc)$|(^|/)EBOOT\.BIN$' && exit 1 || true
```

Expected: no output.

- [ ] **Step 3: Verify no whole-folder copy regression in source**

```bash
grep -RInE 'copyItem\(|replaceItemAt\(' Sources/ZombiesIOS || true
```

Review every match. None may recursively mirror the selected external game root into Documents, Library, Application Support, or Caches.

- [ ] **Step 4: Trigger the manual iOS build workflow**

Verify these CI stages in order:
1. repository audit passes;
2. unsigned device build passes;
3. existing compiled Tranzit decoder verification passes;
4. built `.app` audit passes;
5. IPA packages only after both audits;
6. artifact/release upload succeeds.

- [ ] **Step 5: Inspect the workflow artifact file list**

Unzip the IPA artifact and verify the `Payload/*.app` contains no prohibited archive/asset classes. Re-run:

```bash
python3 Tools/content_audit.py Payload/*.app
```

Expected: PASS.

- [ ] **Step 6: Commit only if verification required fixes**

Use a focused message describing the exact verification defect fixed.
