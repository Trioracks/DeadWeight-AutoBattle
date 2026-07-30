# AUTO Battle mod for Dead Weight | EN / RU

## What it is

**Mod: Dead Weight - AUTO Battle** adds an `AUTO` button to the top HUD only while in combat. Bright means AUTO is ON; grey means OFF. The preference persists into the next encounter.

[Download latest release](https://github.com/Trioracks/DeadWeight-AutoBattle/releases/latest) | [Source code](https://github.com/Trioracks/DeadWeight-AutoBattle)

## One-time installation

1. Download `DeadWeight_AutoBattle_v0.1.0.zip` from the latest GitHub release.
2. Extract it to any temporary folder.
3. Double-click `Install-DeadWeightAutoBattle.cmd`.
4. If the Steam game is not found automatically, select the folder containing `Dead_weight.exe`.
5. The installer copies a ready Steam launch command. In Steam, open **Dead Weight -> Properties -> Launch Options** and press `Ctrl+V`.
6. Use Steam's normal **Play** button.

The installer also creates a `Dead Weight - AUTO Battle` desktop shortcut.

## Automatic updates

After the first setup, no manual downloads are needed. Before every launch, the launcher checks the official GitHub release. When there is a newer version, a window offers to update immediately or skip that version. The package is SHA-256 checked, only `DeadWeightAutoBattle\runtime` is replaced, then the game starts automatically.

If the network is unavailable or verification fails, the installed version is preserved and starts normally. Saves and original Dead Weight files are never touched.

## AUTO behaviour

- evaluates future attack cells, traps, map edges, health and energy for the party;
- prefers safe lethal attacks, pushes into a fall and attacks that hit multiple enemies;
- avoids spending energy to step back into danger when already safe;
- considers available abilities, some talents/equipment and consumables;
- never automatically presses escape or any run-ending control.

The mod is a test build. If a decision is questionable, switch AUTO off from the top-right button and continue manually.

## Feedback

Send the author a full combat screenshot with the AUTO button visible, concise reproduction steps and the expected action. For install/update issues, include `DeadWeightAutoBattle\AutoBattle.update.log`.

[Feedback template](https://github.com/Trioracks/DeadWeight-AutoBattle/blob/main/docs/FEEDBACK_EN.md)

## Русский

**Mod: Dead Weight - AUTO Battle** добавляет кнопку `AUTO` только во время боя. Яркая — включено, серая — выключено; состояние запоминается на следующий бой.

1. Скачайте `DeadWeight_AutoBattle_v0.1.0.zip` из [последнего GitHub-релиза](https://github.com/Trioracks/DeadWeight-AutoBattle/releases/latest).
2. Распакуйте и запустите `Install-DeadWeightAutoBattle.cmd`.
3. При необходимости укажите папку с `Dead_weight.exe`.
4. Установщик копирует команду запуска Steam. Откройте **Dead Weight -> Свойства -> Параметры запуска** и нажмите `Ctrl+V`.
5. Дальше используйте обычную кнопку **Играть**.

Перед запуском мод сам проверяет GitHub. Новая версия сверяется по SHA-256, заменяет только runtime мода и запускает игру; сохранения и игровые файлы не меняются.

## Support the author / Поддержать автора

If the mod is useful, support further work on [Boosty](https://boosty.to/gobelen).
