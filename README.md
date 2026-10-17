# Anime Gatcha

3v3 turn-based anime gacha PvP game for Roblox. Roadmap, decisions and changelog live in the team's Claude Docs roadmap.

## Layout

| Path | Lands in Studio as | What it is |
| --- | --- | --- |
| `src/shared` | `ReplicatedStorage.Shared` | Pure Luau: content data, combat engine, rules. Runs in Studio and in Lune. |
| `src/server` | `ServerScriptService.Server` | Services (profiles, roster, gacha, PvE, PvP queue, admin) |
| `src/client` | `StarterPlayerScripts.Client` | Client entry point |
| `Packages`, `ServerPackages` | same names | Wally packages (not committed) |
| `tests` | — | Lune unit tests |
| `tools` | — | Balance simulator, Studio sync |
| `archive/prototype` | — | The original prototype scripts, for reference |

The prototype menus (`StarterGui`) still live only in the place file; Phase 2 replaces them.

## Setup (Windows)

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then in this folder: `rokit install` and `wally install`.
2. Checks: `stylua src tests`, `selene src`, `lune run tests/run`, `lune run tools/sim`.

## Getting code into Studio

Either:

- **Rojo:** `rojo serve`, then Connect in the Rojo Studio plugin, or
- **No-plugin sync:** `python tools/build_manifest.py`, run `python tools/dev_server.py`, then paste `tools/studio_sync.luau` into the Studio command bar. HTTP is switched on only during the fetch.

Each sync replaces the Rojo-managed folders listed above. Everything else in the place (maps, menus) is untouched.

## Balance simulator

`lune run tools/sim [gamesPerMatchup]` runs time-to-kill checks and AI-vs-AI battles for every 3-class team. CI fails if the Phase 1 gate does not pass.

## Admin console

Press **F2** in game. Commands work only for group rank 254+ (owner/admin) or in Studio: `givegems`, `givechar`, `giveitem`, `resetprofile`.
