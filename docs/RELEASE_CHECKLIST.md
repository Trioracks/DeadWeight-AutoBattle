# Release checklist / Чек-лист выпуска

Use this checklist for every public version of Mod: Dead Weight - AUTO Battle.

1. Update the release version in the command passed to `mod\release\Build-Release.ps1`.
2. Compile `auto_battle_external_v3.gd` with the matching GDE bytecode version and run a short headless script-load probe with the installed `Dead_weight.exe`. A static compile alone is not a release gate.
3. Manually verify the battle UI and tactics on these cases: no companion (only `AUTO`); one or more companions (both buttons); switch `AUTO` <-> `AUTO COMPANIONS` during a turn; companion death; and an enemy that is attackable while a trap is also attackable (the enemy action must win).
4. Build in `D:\Codex\Builds\Mod-Dead-Weight` and inspect the user installer ZIP plus `deadweight-autobattle-update.json` compatibility bridge.
5. Verify the user installer includes only the mod installer, bootstrap and `runtime\version.json` plus the two launcher scripts. Never ship game EXEs, PCK files, saves, extracted game data or logs.
6. Commit and push the changed source, documentation and release notes to `main`.
7. Upload exactly two assets to the GitHub Release with the matching `vX.Y.Z` tag: the user installer ZIP and `deadweight-autobattle-update.json`. The bridge SHA-256 and URL must point to that same installer ZIP.
8. Run the isolated end-to-end check: with Steam closed, install the full ZIP into a disposable folder and verify the target Steam `LaunchOptions`; then set the local runtime version lower, run the bootstrap in `-NoGameStart -Silent` mode, and require the runtime version and log to confirm the real GitHub update.
9. Update both Steam Community guides when release notes, installation, versioned filename or supported behaviour changes:
   - RU: https://steamcommunity.com/sharedfiles/filedetails/?id=3774293352
   - EN: https://steamcommunity.com/sharedfiles/filedetails/?id=3774296030
10. Keep the GitHub README, RU/EN feedback templates and Steam text consistent. Mention any known limitation rather than claiming it is solved.

Автообновление заменяет только `DeadWeightAutoBattle\runtime`. Если проверка сети, manifest или SHA-256 не проходит, текущая установленная версия должна запускаться без изменений.
