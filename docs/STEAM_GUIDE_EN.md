# AUTO Battle — Dead Weight mod | EN

**Current version: v0.2.03.**

**Dead Weight — AUTO Battle** adds two buttons in the top-right corner during combat only:

- `AUTO` — the upper button; controls the entire living party, including the main hero;
- `ONLY COMPANIONS` — appears directly below `AUTO` only when the hero has a living companion; controls companions only, while the main hero remains manual.

The modes are mutually exclusive: enabling either one immediately disables the other, and the active button is highlighted. The selected mode is remembered for the next battle.

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

## Existing installations

Launch the game through Steam's ordinary **Play** button: the bootstrap checks for updates on every launch. If you see the old single button instead of two modes, `ONLY COMPANIONS` is missing despite a living companion, or `AUTO` does not appear in combat, close Steam completely and run the current ZIP installer once. It restores Steam's launch option. Saves and game files are never touched.

## Automatic updates

After installation, no manual download is needed. Before every Steam launch, the bootstrap checks the latest official GitHub release. A new version is downloaded from the installer ZIP, verified with SHA-256, then only `DeadWeightAutoBattle\runtime` is replaced before the game starts.

If the network is unavailable or verification fails, the installed version stays in place and starts normally. The version number appears in the top-right corner only while `AUTO` or `ONLY COMPANIONS` is enabled.

## How auto-battle works

- `AUTO` evaluates the whole living party, while `ONLY COMPANIONS` applies the same tactics to companions only;
- evaluates future attack cells, traps, map edges, health and energy;
- treats every cell highlighted by the game for a prepared attack as dangerous, including the far end of a line strike;
- avoids cells that apply control: web, stun, immobilise, sleep, freeze, silence and similar effects;
- when a party member is already controlled, searches for a legal cleanse before normal actions — from the hero, a companion, equipped item or consumable;
- looks for safe kills, pushes into a fall and attacks hitting multiple enemies;
- when one enemy remains and can be finished, ends the encounter instead of spending a separate turn on a trap;
- does not spend energy to step back into danger when already safe;
- considers available abilities, some talents, equipment and consumables, including active skills granted by equipped weapons and items;
- ready offensive equipment skills take priority, while a critically wounded hero keeps a move for retreating from an untelegraphed boss attack;
- Bully keeps a thrust lane, retreats through a verified safe route at half HP or lower, and uses charge-push only for a guaranteed enemy fall;
- never automatically presses escape, main menu or any run-ending control.

This is a test mod. If a decision looks questionable, turn the active mode off with its top-right button and continue manually.

## Logs and feedback

All diagnostic output goes to logs, leaving only the buttons and active-mode version in combat. To report an auto-battle decision, send the author via Steam chat:

- a full battle screenshot with the active button and version visible;
- a short description of the expected action;
- `DeadWeightAutoBattle\AutoBattle.update.log` for startup or updater issues;
- the last `[AUTO]` lines from `Godot\app_userdata\Dead_weight\logs\godot.log` for a tactical decision. These include the selected target, danger, control and cleanse attempt.

[Feedback template](https://github.com/Trioracks/DeadWeight-AutoBattle/blob/main/docs/FEEDBACK_EN.md)

## Support the author

If this mod is useful, you can support further development on [Boosty](https://boosty.to/gobelen).
