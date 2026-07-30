# AUTO Battle - мод на автобой для Dead Weight | RU / EN

## Что это

**Mod: Dead Weight - AUTO Battle** добавляет кнопку `AUTO` в верхней части HUD только во время боя. Яркая кнопка — автобой включён, серая — выключен. Выбор сохраняется: если AUTO был включён в предыдущем бою, он включится и в следующем.

[Скачать последнюю версию на GitHub](https://github.com/Trioracks/DeadWeight-AutoBattle/releases/latest) | [Исходный код](https://github.com/Trioracks/DeadWeight-AutoBattle)

## Установка один раз

1. Скачайте `DeadWeight_AutoBattle_v0.1.0.zip` из последнего GitHub-релиза.
2. Распакуйте его в любую временную папку.
3. Запустите `Install-DeadWeightAutoBattle.cmd` двойным щелчком.
4. Если Steam-версия не найдена автоматически, укажите папку с `Dead_weight.exe`.
5. Установщик скопирует готовую команду запуска. В Steam откройте **Dead Weight -> Свойства -> Параметры запуска** и просто нажмите `Ctrl+V`.
6. Нажимайте обычную кнопку **Играть** в Steam.

Установщик также создаёт ярлык `Dead Weight - AUTO Battle` на рабочем столе.

## Автообновление

После первого запуска ничего скачивать вручную не нужно. Перед запуском игра проверяет официальный GitHub-релиз. Если есть новая версия, появится окно: обновить сразу или пропустить эту версию. При обновлении пакет проверяется SHA-256, заменяется только папка `DeadWeightAutoBattle\runtime`, затем игра запускается сама.

Если сеть недоступна или пакет не прошёл проверку, старая версия остаётся и игра стартует нормально. Сохранения и файлы Dead Weight не затрагиваются.

## Логика AUTO

- анализирует клетки будущих атак, ловушки, край карты, HP и энергию всей группы;
- старается сначала безопасно добить цель, оттолкнуть её в пропасть или ударить по нескольким врагам;
- не тратит энергию на возврат под удар, если уже стоит в безопасности;
- учитывает доступные способности, часть талантов/экипировки и расходники;
- не нажимает автоматически выход из боя или завершение забега.

Мод тестовый: при сомнительном решении выключите AUTO верхней кнопкой и продолжите вручную.

## Баг-репорт

Пришлите в Steam-чат автору полный скриншот боя с кнопкой AUTO, краткое описание ситуации и ожидаемого действия. Для проблем установки/обновления приложите `DeadWeightAutoBattle\AutoBattle.update.log`.

[Шаблон отчёта](https://github.com/Trioracks/DeadWeight-AutoBattle/blob/main/docs/FEEDBACK_RU.md)

## English

**Mod: Dead Weight - AUTO Battle** adds an `AUTO` button only during combat. Bright means ON; grey means OFF. The choice is retained for the next battle.

1. Download `DeadWeight_AutoBattle_v0.1.0.zip` from the [latest GitHub release](https://github.com/Trioracks/DeadWeight-AutoBattle/releases/latest).
2. Extract it anywhere and double-click `Install-DeadWeightAutoBattle.cmd`.
3. If necessary, select the folder containing `Dead_weight.exe`.
4. The installer copies the Steam launch command. Open **Dead Weight -> Properties -> Launch Options** and press `Ctrl+V`.
5. Use Steam's normal **Play** button.

Every launch checks the official GitHub release. A newer version is verified with SHA-256 and only the mod runtime is replaced; saves and original game files are untouched. If the network or verification fails, the currently installed version starts normally.

For feedback, send a full combat screenshot with AUTO visible, concise reproduction steps and `DeadWeightAutoBattle\AutoBattle.update.log` for updater issues.

## Поддержать автора / Support the author

Если мод оказался полезен, поддержать разработку можно на [Boosty](https://boosty.to/gobelen).
