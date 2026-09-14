# BO2 Full Conversion Checkpoint

## Resume Anchor
- Branch: `bo2-full-conversion`
- Current task: Task 1 — Full-game source classification
- Current substep: Generalize scanner source selection from `BO2ZombiesManifest` to all convertible BO2 resources.
- Last completed implementation commit before checkpoint protocol: `f1483339504d81b1fd38a054ff753c4bc89bb1e1` (`feat: expose full-game content catalog from scans`)
- Latest test-driving commit: `d88099adb920c90bbbf9ca5380d8477738c7a3de` (`test: cover full-game convertible source selection`)
- Latest plan/checkpoint-protocol commit: `e0d91cd449e2f6c86b84d9bf43e82636782950c7`

## CI State
- First isolated CI run: `34792526107` — failed as expected because `BO2ContentClassifier` did not exist yet.
- Subsequent classifier implementation was added; newer branch-head CI runs were triggered automatically.
- Before resuming implementation, inspect the newest `BO2 Full Conversion CI` run for the current branch head and record its final result here.

## Current Expected Failure
`BO2ContentCatalogTests` now expects `BO2ContentClassifier.isConvertibleResource(path:)`, which has not yet been fully committed because the previous editing turn was interrupted mid-change.

## Files In Flight
- `Sources/ZombiesIOS/Models/BO2ContentCatalog.swift`
- `Sources/ZombiesIOS/Services/PS3DumpScanner.swift`
- `Tests/ZombiesIOSTests/BO2ContentCatalogTests.swift`

## Next Concrete Actions
1. Finish `BO2ContentClassifier.isConvertibleResource(path:)` with a strict allowlist of BO2 data/container extensions and exclusion of PS3 executable/platform metadata.
2. Change direct-folder and ZIP scanning to select `isConvertibleResource(path:)` instead of `BO2ZombiesManifest.contains(...)`.
3. Update scanner error wording so failure means no convertible BO2 resources were found, not no Zombies manifest match.
4. Run isolated CI until Task 1 is green.
5. Update this checkpoint with the green run ID and branch head.
6. Begin Task 2 by adding failing interruption/resume tests for `GameDataManifest` and atomic `.part` output recovery.

## User Input Required
None for the current Task 1/Task 2 code work.

## Resume Rule
On any new chat/session, read this file first, verify the branch head, inspect the latest CI run, and continue at `Next Concrete Actions`. Do not restart from Hijacked or from the Zombies-only scanner unless this checkpoint explicitly says to do so.
