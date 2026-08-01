# AUTO Battle — Dead Weight mod | EN

**Mod: Dead Weight — AUTO Battle** adds `AUTO` and `ONLY COMPANIONS` buttons in the top-right corner during combat only. `AUTO` controls the whole party; `ONLY COMPANIONS` appears when a living companion is present and controls companions only, leaving the main hero manual. The modes are mutually exclusive and remembered for the next battle.

[Download latest version](https://github.com/Trioracks/DeadWeight-AutoBattle/releases/latest) | [Source code](https://github.com/Trioracks/DeadWeight-AutoBattle)

## Install once

> On the release page, download **only the ZIP** named `DeadWeight_AUTO_Battle_Install_vX.Y.Z.zip`.
> `deadweight-autobattle-update.json` is a tiny compatibility bridge for already-installed older versions. Do not download or open it manually.

1. Download the only ZIP, `DeadWeight_AUTO_Battle_Install_vX.Y.Z.zip`.
2. Extract it anywhere temporary.
3. Double-click `Install-DeadWeightAutoBattle.cmd`.
4. Close Steam completely. The installer finds Dead Weight in every Steam library on any drive. If it cannot, select the game folder containing `Dead_weight.exe`.
5. The installer configures Steam's permanent launch option itself. It also copies the command to the clipboard as a fallback.
6. Open Steam and use its ordinary **Play** button.

The installer also creates a fallback desktop shortcut named `Dead Weight — AUTO Battle`.

## Existing older installations

If the mod was installed before v0.2.00 or the `AUTO` button does not appear, close Steam completely and run the current ZIP installer once: it restores the permanent Steam launch option. Saves and game files are never touched.

## Automatic updates

After installation, no manual download is needed. Before the game starts, the launcher checks the latest official GitHub release. A new version is downloaded from the installer ZIP, verified with SHA-256, then only `DeadWeightAutoBattle\runtime` is replaced before the game starts.

If the network is unavailable or verification fails, the installed version stays in place and starts normally.

## AUTO behaviour

- `AUTO` evaluates future attack cells, traps, map edges, health and energy for the whole party; `ONLY COMPANIONS` applies the same tactics to companions only;
- treats every cell highlighted by the game for a prepared attack as dangerous, including the far end of a line strike;
- never moves into control (`web`, stun, immobilise, sleep, etc.); if control is already active, it first searches for a legal cleanse from the hero, companion, or consumable;
- looks for safe kills, pushes into a fall and attacks hitting multiple enemies;
- when one enemy remains and can be finished, ends the encounter instead of spending a separate turn on a trap;
- does not spend energy to step back into danger when already safe;
- considers available abilities, some talents, equipment and consumables;
- resolves every active skill granted by equipped weapons and items, including damage-over-time effects; ready attack skills are preferred, while a critical hero retreats if a boss has an untelegraphed attack;
- Bully keeps a thrust lane, retreats through a verified safe route at half HP or lower, and uses the charge-push only for a verified enemy fall;
- never automatically presses escape, main menu or any run-ending control.

This is a test mod. If a decision looks questionable, turn AUTO off with the top-right button and continue manually.

## Feedback

Send the author via Steam chat:

- a full battle screenshot with AUTO and the mod version visible;
- a short description of the expected action;
- `DeadWeightAutoBattle\AutoBattle.update.log` for startup or updater issues, or the last `[AUTO]` lines from `Godot\app_userdata\Dead_weight\logs\godot.log` for a tactical decision.

[Feedback template](https://github.com/Trioracks/DeadWeight-AutoBattle/blob/main/docs/FEEDBACK_EN.md)

## Support the author

If this mod is useful, you can support further development on [Boosty](https://boosty.to/gobelen).
