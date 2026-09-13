# Quake III-derived native runtime

This directory contains the native C gameplay/simulation core used by Zombies-IOS.

The runtime is derived from the programming model and math conventions of the **Quake III Arena GPL source release** by id Software. The upstream source is available from the public `id-Software/Quake-III-Arena` repository. Quake III Arena source code was released under the GNU General Public License version 2 or, for files that say so, any later version.

The Zombies-IOS adaptation is intentionally small: it exposes a stable C API for a Swift/Metal iOS host, consumes project-defined BO2 runtime triangle packages, and does not require or distribute Quake III retail game data. Modified/adapted code in this directory is distributed under GPLv2-or-later so the public repository remains the corresponding source for released IPA builds.

See `COPYING.txt` for the license terms and the individual source-file notices for attribution.
