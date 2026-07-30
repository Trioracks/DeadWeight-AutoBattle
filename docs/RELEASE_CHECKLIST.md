# Release checklist / Чек-лист выпуска

Use this checklist for every public version of Mod: Dead Weight - AUTO Battle.

1. Update the release version in the command passed to `mod\release\Build-Release.ps1`.
2. Build in `D:\Codex\Builds\Mod-Dead-Weight` and inspect the generated installer ZIP, runtime ZIP and `deadweight-autobattle-update.json`.
3. Verify the runtime ZIP has only `runtime\version.json` and the two launcher scripts. Never ship game EXEs, PCK files, saves, extracted game data or logs.
4. Commit and push the changed source, documentation and release notes to `main`.
5. Upload all three assets to the GitHub Release with the matching `vX.Y.Z` tag. The manifest URL and the package SHA-256 must refer to that exact uploaded runtime ZIP.
6. Run the isolated end-to-end check: install the full ZIP into a disposable folder, set the local runtime version lower, run the bootstrap in `-NoGameStart -Silent` mode, then require the runtime version and log to confirm the real GitHub update.
7. Update both Steam Community guides when release notes, installation, versioned filename or supported behaviour changes:
   - RU: https://steamcommunity.com/sharedfiles/filedetails/?id=3774293352
   - EN: https://steamcommunity.com/sharedfiles/filedetails/?id=3774296030
8. Keep the GitHub README, RU/EN feedback templates and Steam text consistent. Mention any known limitation rather than claiming it is solved.

Автообновление заменяет только `DeadWeightAutoBattle\runtime`. Если проверка сети, manifest или SHA-256 не проходит, текущая установленная версия должна запускаться без изменений.
