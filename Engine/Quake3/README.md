# BO2 Quake III iOS Runtime

This subtree is the native C runtime boundary used by ZombiesIOS for the BO2-on-iOS project.

The architecture follows the GPL-released id Software Quake III Arena engine model: a native game loop, Quake-style user commands/player movement, triangle-world rendering, and an explicit collision/world-loading boundary. It does **not** execute the PS3 BO2 executable and is not a PS3 emulator.

Upstream reference source: `id-Software/Quake-III-Arena` on GitHub. Quake III Arena source is released under GNU GPL version 2. See `COPYING.txt`.

Retail Call of Duty: Black Ops II assets are not part of this repository. The iOS app converts user-supplied BO2 PS3 data locally into the `BO2RuntimePackage` format and passes that data to this runtime.
