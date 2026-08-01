# AUTO Battle — Dead Weight mod | EN

**Mod: Dead Weight — AUTO Battle** adds an `AUTO` button in the top-right corner during combat only. A bright button means AUTO is on; grey means off. The setting is remembered for the next battle.

[Download latest version](https://github.com/Trioracks/DeadWeight-AutoBattle/releases/latest) | [Source code](https://github.com/Trioracks/DeadWeight-AutoBattle)

## Install once

> On the release page, download **only the ZIP** named `DeadWeight_AUTO_Battle_Install_vX.Y.Z.zip`.
> `deadweight-autobattle-update.json` is a tiny compatibility bridge for already-installed older versions. Do not download or open it manually.

1. Download the only ZIP, `DeadWeight_AUTO_Battle_Install_vX.Y.Z.zip`.
2. Extract it anywhere temporary.
3. Double-click `Install-DeadWeightAutoBattle.cmd`.
4. The installer finds Dead Weight in every Steam library on any drive. If it cannot, select the game folder containing `Dead_weight.exe`.
5. The installer copies the launch command. In Steam, open **Dead Weight → Properties → Launch Options** and press `Ctrl+V`.
6. Use Steam’s ordinary **Play** button.

The installer also creates a fallback desktop shortcut named `Dead Weight — AUTO Battle`.

## Existing older installations

If the mod was installed before v0.1.18, start Steam once with the existing launch option. The small compatibility JSON automatically moves the old setup to the new format. If no update appears, simply run the new ZIP installer once; saves and game files are never touched.

## Automatic updates

After installation, no manual download is needed. Before the game starts, the launcher checks the latest official GitHub release. A new version is downloaded from the installer ZIP, verified with SHA-256, then only `DeadWeightAutoBattle\runtime` is replaced before the game starts.

If the network is unavailable or verification fails, the installed version stays in place and starts normally.

## AUTO behaviour

- evaluates future attack cells, traps, map edges, health and energy for the whole party;
- treats every cell highlighted by the game for a prepared attack as dangerous, including the far end of a line strike;
- looks for safe kills, pushes into a fall and attacks hitting multiple enemies;
- when one enemy remains and can be finished, ends the encounter instead of spending a separate turn on a trap;
- does not spend energy to step back into danger when already safe;
- considers available abilities, some talents, equipment and consumables;
- resolves every active skill granted by equipped weapons and items, including damage-over-time effects; ready attack skills are preferred, while a critical hero retreats if a boss has an untelegraphed attack;
- never automatically presses escape, main menu or any run-ending control.

This is a test mod. If a decision looks questionable, turn AUTO off with the top-right button and continue manually.

## Feedback

Send the author via Steam chat:

- a full battle screenshot with AUTO and AUTO DEBUG visible;
- a short description of the expected action;
- `DeadWeightAutoBattle\AutoBattle.update.log` for startup or updater issues.

[Feedback template](https://github.com/Trioracks/DeadWeight-AutoBattle/blob/main/docs/FEEDBACK_EN.md)

## Support the author

If this mod is useful, you can support further development on [Boosty](https://boosty.to/gobelen).
