# v0.2.34 — Klyukva and tactical safety

- Added tactical handling for Klyukva's opening-range talent and **Hold Position**: after a safe shot, AUTO can preserve a safe firing tile to build the next attack instead of wandering.
- Improved re-target-aware movement. A character that has escaped a prepared attack will not spend a second move returning to a tile that an enemy can re-target after the first move.
- Kept the two combat modes mutually exclusive: `AUTO` controls the whole party, while `ONLY COMPANIONS` leaves the main hero manual.
- The release gate verifies both combat controls, their wiring, source/runtime parsing, Steam launch-option contract, and the critical tactical contracts before packaging.

## Updating

Existing installations update from the latest GitHub Release when the game is started through Steam's normal **Play** button. No manual ZIP download is needed after the first installation.

For a first installation, download only `DeadWeight_AUTO_Battle_Install_v0.2.34.zip`, extract it, close Steam completely, and run `Install-DeadWeightAutoBattle.cmd`.
