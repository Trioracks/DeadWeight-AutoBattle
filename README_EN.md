# Mod: Dead Weight - AUTO Battle

[Русский](README.md) | [English](README_EN.md)

A Windows test build of AUTO Battle for the Steam version of **Dead Weight**. The mod adds an `AUTO` button during combat only: a bright button means ON, a grey button means OFF. The AUTO preference is remembered for the next encounter.

## Player installation

1. Download `DeadWeight_AUTO_Battle_Install_vX.Y.Z.zip` from the [latest release](https://github.com/Trioracks/DeadWeight-AutoBattle/releases/latest).
   `deadweight-autobattle-update.json` is a technical compatibility file for automatic migration of old installations; do not download it manually.
2. Extract it anywhere temporary and double-click `Install-DeadWeightAutoBattle.cmd`.
3. Close Steam. The installer automatically searches **every** Steam library on the user's machine, including libraries on other drives. If Steam cannot locate the game, it asks to choose the folder that contains `Dead_weight.exe`. It creates `DeadWeightAutoBattle` next to the game and configures Steam's permanent launch option itself.
4. Open Steam and use its ordinary **Play** button. The launch command is copied to the clipboard as a fallback, but pasting it manually is not required.

The installer also creates a `Dead Weight - AUTO Battle` desktop shortcut. It is a useful fallback, although Steam launch options are preferable for the Steam overlay.

## Automatic updates

No manual downloads are needed after the first installation. Every launch through the Steam launcher:

1. reads the version of the latest official GitHub release;
2. when a newer version exists, shows its version and **Update now** / **Skip this version**;
3. downloads that same installer archive, verifies the SHA-256 supplied by GitHub, and replaces only `DeadWeightAutoBattle\runtime`;
4. starts the game automatically.

If GitHub is unavailable, a hash does not match, or an update is interrupted, the existing runtime is kept and starts normally. Saves and original game files are never changed.

## What AUTO does

AUTO uses available game controllers, so the game itself applies energy costs, cooldowns, animations and effects. The current test logic:

- shows the button only in combat;
- evaluates next-turn danger cells, traps, map edges, health and energy for the whole party;
- treats every cell highlighted by the game for a prepared attack as dangerous, including the far end of a line strike;
- prefers safe kills, pushes into a fall, and multi-target attacks;
- when one enemy remains and can be finished, ends the encounter instead of spending a separate turn on a trap;
- may keep energy and end on a safe cell instead of returning into an attack;
- reads abilities, talents, some equipment and available consumables;
- resolves every active skill granted by equipped weapons and items, including damage-over-time effects; ready attack skills are preferred, while a critical hero retreats if a boss has an untelegraphed attack;
- deliberately never triggers the game's escape/run-ending controls automatically.

This is an active test build. If a decision looks wrong, turn AUTO off with the top-right button and continue manually.

## Bug reports

Please send the author via Steam chat:

1. a full combat screenshot with the AUTO button visible;
2. `DeadWeightAutoBattle\AutoBattle.update.log` for installation/update issues;
3. concise reproduction steps and the expected result.

A detailed template is in [docs/FEEDBACK_EN.md](docs/FEEDBACK_EN.md).

## Development

Source code is under `mod/`. Build a release with:

```powershell
.\mod\release\Build-Release.ps1 -Version 0.1.0
```

Artifacts are written to `D:\Codex\Builds\Mod-Dead-Weight` and then uploaded to a GitHub Release together with its manifest. The repository deliberately contains no game EXEs, PCKs, saves or extracted game files.

## Support the author

If the mod is useful, you can support further development on [Boosty](https://boosty.to/gobelen).
