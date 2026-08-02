param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [Parameter(Mandatory = $true)]
    [string]$ReleaseRoot,
    [string]$GameExe = 'H:\Steam\steamapps\common\Dead Weight\Dead_weight.exe'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$probe = Join-Path $PSScriptRoot 'auto_battle_ui_regression_probe.gd'
$sourceManager = Join-Path $projectRoot 'mod\launcher\auto_battle_external_v3.gd'
$installerSource = Join-Path $projectRoot 'mod\distribution\Install-DeadWeightAutoBattle.ps1'
$runtimeManager = Join-Path $ReleaseRoot 'installer-verify\runtime\launcher\auto_battle_external_v3.gd'
$runtimeVersion = Join-Path $ReleaseRoot 'installer-verify\runtime\version.json'

foreach ($path in @($GameExe, $probe, $sourceManager, $installerSource, $runtimeManager, $runtimeVersion)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "AUTO UI regression gate is missing: $path" }
}

$runtimeManifest = Get-Content -LiteralPath $runtimeVersion -Raw | ConvertFrom-Json
if ([string]$runtimeManifest.version -cne $Version) {
    throw "Release runtime version '$($runtimeManifest.version)' does not match requested '$Version'."
}

$requiredSourceContracts = @(
    'const MOD_VERSION := "__AUTO_BATTLE_VERSION__"',
    '_button = Button.new()',
    '_button.name = "auto_battle_button"',
    'root.add_child(_button)',
    '_companions_button = Button.new()',
    '_companions_button.name = "auto_companions_button"',
    '_companions_button.text = "ONLY COMPANIONS"',
    'root.add_child(_companions_button)',
    'func _on_auto_toggled(is_enabled: bool) -> void:',
    'func _on_companions_toggled(is_enabled: bool) -> void:'
)
$sourceText = Get-Content -LiteralPath $sourceManager -Raw
foreach ($contract in $requiredSourceContracts) {
    if (-not $sourceText.Contains($contract)) { throw "AUTO UI source contract is missing: $contract" }
}

# A visual UI probe cannot reproduce every generated battle board, so the
# reviewer also protects the critical tactical invariant that caused a prior
# regression: a hero who would die to the shown attack must never spend AP on
# an unverified crate/barrel move before escaping.  The full game validates the
# route itself at runtime; this contract keeps the lethal guard in that branch.
$requiredTacticalContracts = @(
    'var route_clear_is_survivable := incoming > 0 and incoming < int(controller.my_params.hp) and not _cell_has_forced_movement_threat(start)',
    'if not route_clear.is_empty() and route_clear_is_survivable:',
    'ROUTE CLEAR REJECTED - lethal/forced threat; retain AP for a verified escape or defence',
    'damage_limited_escape = _choose_emergency_damage_limited_retreat(controller, incoming)',
    'EMERGENCY DAMAGE-LIMITED RETREAT - ',
    'func _choose_emergency_damage_limited_retreat(controller, current_incoming: int) -> Dictionary:',
    'if _is_cell_control_threatened(cell) or _cell_has_forced_movement_threat(cell):',
    'if cell_incoming >= hp or cell_incoming >= current_incoming:',
    'var priority_enemy = _get_party_priority_enemy()',
    'APPROACH / NEXT-TURN STAGING - priority %s; plan %s; two-turn exit %s, range %.1f, future exits %d, immediate safe %d, reach %d, AP %d',
    'if not has_next_attack and not closes_distance:',
    'elif can_attack_at_all and priority_distance < start_priority_distance:',
    'func _has_attack_capability(controller) -> bool:',
    'var support_escort := _choose_support_escort_move(controller)',
    'func _choose_support_escort_move(controller) -> Dictionary:',
    'SUPPORT ESCORT - close to main hero %s, support range %d, distance %.1f, future exits %d, AP %d',
    'func _has_attack_followup_exit(controller, origin: Vector2i, attack: Dictionary, available_ap: int) -> bool:',
    'func _has_virtual_safe_escape(controller, origin: Vector2i, available_ap: int) -> bool:',
    'var next_turn_exit := _has_attack_followup_exit(controller, cell, next_turn_attack, full_turn_ap)',
    'func _log_hold_diagnostics(controller, current_incoming: int, context: String) -> void:',
    'HOLD DIAGNOSTIC | %s | AP %d, incoming %d, priority %s',
    'for board_cell in _move_system.get_used_cells():',
    'func _find_best_two_tile_strike(controller, current_incoming: int) -> Dictionary:',
    'REACH STRIKE AVAILABLE AT HOLD | %s -> %s | %s',
    'var _pending_move_target = null',
    'MOVE ENDPOINT MISMATCH - expected %s, reached %s; replanning remaining AP',
    'func _apply_support_effect_values(values: Dictionary, effect) -> void:',
    'for mechanic in ability.get_full_mechanics_array():',
    'func _choose_swap_escape(controller) -> Dictionary:',
    'SWAP ESCAPE - safe %s cell %s, future exits %d, reach %d',
    'for target in _move_system.get_used_cells():',
    'if target_object.is_player_character():',
    'var ally_incoming := _incoming_damage_at(start)',
    'var lethal_party_members := _get_lethally_threatened_player_controllers()',
    'SAVE LETHAL COMPANION - ',
    'func _choose_party_rescue_attack(controller, current_incoming: int) -> Dictionary:',
    'func _get_lethally_threatened_player_controllers() -> Array:',
    '"removed_threat_controllers": removed_threat_controllers',
    'RETARGET-SAFE ESCAPE - ',
    'func _get_potentially_retargeted_prepared_cells(controller, origin: Vector2i, excluded_controllers: Array = []) -> Dictionary:',
    'var retargeted_cells: Dictionary = _get_potentially_retargeted_prepared_cells(controller, start, excluded_threat_controllers) if require_retarget_safe else {}',
    'if require_retarget_safe and retargeted_cells.has(cell):',
    'var retarget_safe_escape := _choose_best_move(controller, incoming, true, false, true, -1, [], true) if lethal_self_threat else {}',
    'PERF decision %.1f ms | hero %d | AP %d',
    'var _static_board_edge_risk: Dictionary = {}',
    'if not board_cells.has(adjacent):',
    'var desired_distance := maxf(3.0, float(int(stance.get("preferred_distance", 2))))',
    'if not boss_caution_move.is_empty() and not _attack_makes_enemy_progress(attack) and safe_hit_step.is_empty():',
    'var damage_after_support: int = 0 if evasion or block_amount >= incoming else shield_estimate',
    'var saves_lethal: bool = incoming >= int(target_params.hp) and hp_after_support > damage_after_support',
    'attack_then_escape = _choose_attack_then_safe_escape(controller, attack, incoming)',
    'if not attack_then_escape.is_empty():',
    '"reason": "SAFE HOLD - no AP remaining"',
    'var party_rescue_attack := _choose_party_rescue_attack(controller, incoming) if can_cover_party_rescue and not lethal_party_members.is_empty() else {}',
    'safe_step = _choose_best_move(controller, incoming, true, true)',
    'func _ability_requires_boardwide_target_probe(ability) -> bool:',
    'return str(ability.tag).to_lower().begins_with("abil_hit_2t_")',
    'if not _is_main_hero_controller(controller) and int(escape_profile.exits) <= 0:',
    'if int(exits.exits) <= 0:',
    'func _prepared_action_point_blank_shotgun_damage(prepared_action, cell: Vector2i) -> int:',
    'begins_with("abil_shot_buckshot_dmg3")',
    'return 3 if source.obj_position.distance_to(cell) <= 1.5 else 0',
    'return maxi(point_blank_damage, maxi(reported_damage, full_prediction))',
    'if _prepared_action_point_blank_shotgun_damage(prepared_action, candidate_cell) > 0:',
    'ENEMY INTENT %s | source %s | target %s | distance %.1f | UI %d, full %d, point-blank %d, used %d',
    'if (hp <= 1 and _is_cell_threatened(cell)) or _is_cell_control_threatened(cell) or _cell_has_forced_movement_threat(cell):',
    'boss_caution_move["reason"] = "LETHAL THREAT - " + str(boss_caution_move.reason)',
    'var _move_followup_controller_id := -1',
    'if bool(plan.get("commit_follow_up", false)):',
    'func _choose_committed_move_followup(controller, current_incoming: int) -> Dictionary:',
    'COMMITTED STEP+HIT - execute verified follow-up; ',
    'COMMITTED STEP+HIT CANCELLED - landing is no longer fully safe; replanning',
    '"commit_follow_up": true',
    'if attack.is_empty() or not _attack_makes_enemy_progress(attack):',
    'NO SAFE COMBAT MOVE - ',
    'func _get_future_party_focus_damage(controller, enemy_controller) -> int:',
    'COORDINATED PARTY FINISH - ',
    'score += 15000.0',
    'if not _attack_makes_enemy_progress(follow_up) or int(follow_up.get("self_damage", 0)) > 0:',
    'var retargeted_cells: Dictionary = _get_potentially_retargeted_prepared_cells(controller, start) if _is_cell_threatened(start) else {}',
    'var retarget_applies_control := not _ability_control_tags(ability).is_empty()',
    'if int(predicted_damage.get(candidate_cell, 0)) > 0 or retarget_applies_control or retarget_forces_movement:',
    'int(controller.my_params.hp) - incoming >= 2',
    'if incoming >= hp and (defence_amount >= incoming or block_amount >= incoming or evasion):',
    'if int(escape_profile.exits) <= 1:',
    'score -= 16000.0',
    'MITIGATE THREATENED COMPANION - ',
    'attack_then_escape = _choose_attack_then_safe_escape(controller, attack, incoming)',
    'if bool(result.get("unsafe_party_damage", false)):',
    'var party_trap_blast_risk := false',
    'if party_cell.distance_to(trap_cell) <= 1.5:',
    'UNSAFE FRIENDLY FIRE - ',
    'HIT THEN ESCAPE REJECTED - low mobility after %s: future %d, immediate safe %d',
    'local_safe_exits = _get_immediate_safe_exit_count(controller, cell, excluded_threat_controllers)',
    'func _get_immediate_safe_exit_count(controller, origin: Vector2i, excluded_controllers: Array = []) -> int:',
    'score -= 14000.0',
    'ESCAPE REJECTED - no immediate safe exit at %s; defer pocket until all defences fail',
    'LAST-RESORT POCKET ESCAPE - no sustainable lane after defence scan; ',
    'func _attack_ends_battle(attack: Dictionary) -> bool:',
    'var decisive_attack := _attack_ends_battle(attack) or bool(attack.get("self_safe_after", false))',
    'if _attack_ends_battle(attack) or bool(attack.get("self_safe_after", false)):',
    'var self_control_threat := _is_cell_control_threatened(start)',
    'var lethal_self_threat := self_threatened and (incoming >= int(controller.my_params.hp) or self_control_threat or self_forced_movement_threat)',
    'or _is_cell_control_threatened(cell) or _cell_has_forced_movement_threat(cell):',
    'var escape := _choose_best_move(target_controller, _incoming_damage_at(target), true, false, true, -1, [], true)',
    'return not escape.is_empty() and int(escape.get("local_safe_exits", 0)) > 0',
    'former global hold here made the healer stay uselessly out of range',
    '_counterattack_profile_cache.clear()',
    'func _get_counterattack_profile(enemy_controller, attacker_cell: Vector2i) -> Dictionary:',
    'counter_ability.can_mechanically_attack(enemy_cell, attacker_cell, false, false, false)',
    'COUNTER RISK %s (damage %d, control %s) - ',
    'var counterattack_damage := 0',
    'func _support_effect_key(effect) -> String:',
    'var effect_key := _support_effect_key(effect)',
    'func _choose_preemptive_self_defence(controller) -> Dictionary:',
    'PREEMPTIVE SELF SHIELD - permanent defence +%d before danger',
    'BOARD ACTION REJECTED - current threat remains; preserve AP instead of using a non-enemy action',
    'func _get_ranged_setup_values(controller, ability) -> Dictionary:',
    'func _choose_best_ranged_attack_from_cell(controller, start: Vector2i, current_incoming: int, available_ap: int) -> Dictionary:',
    'func _is_ranged_attack_plan(attack: Dictionary) -> bool:',
    'if _is_ranged_attack_plan(attack):',
    'RANGED HIT THEN RETARGET-SAFE ESCAPE - ',
    'var escape := _choose_best_move(controller, current_incoming, true, false, true, remaining_ap, [], true)',
    'func _choose_ranged_setup_skill(controller, current_attack: Dictionary) -> Dictionary:',
    'RANGED SETUP %s [%s] -> %s -> %s',
    'var ranged_setup := _choose_ranged_setup_skill(controller, attack)',
    'if _is_cell_threatened(start) and not bool(follow_up.get("self_safe_after", false)):',
    'const HOLD_POSITION_PERK_TAG := "perk_tree_shooter_take_position"',
    'func _get_hold_position_values(controller) -> Dictionary:',
    'func _choose_hold_position_after_attack(controller) -> Dictionary:',
    'HOLD POSITION - safe firing square retained; next attack stack +%d damage',
    'var remembered_retargeters: Array = _prepared_retargeter_memory.get(_controller_memory_key(controller), [])',
    'if not targets_origin and not remembered_retargeters.has(enemy_controller):',
    'var retargeted_cells := _get_potentially_retargeted_prepared_cells(controller, start)',
    'if retargeted_cells.has(cell):'
    'func _push_targets_trap(ability, target: Vector2i) -> bool:'
    'if _push_targets_trap(ability, target):'
    'func _prepared_push_lands_target_on_trap(prepared_action, target: Vector2i) -> bool:'
    'func _cell_has_prepared_push_trap_hazard(cell: Vector2i, excluded_controllers: Array = []) -> bool:'
    'if _cell_has_prepared_push_trap_hazard(cell, excluded_controllers):'
    'func _requires_ranged_escape_reserve(controller) -> bool:'
    'if _requires_ranged_escape_reserve(controller) and (int(exits.exits) <= 1 or local_safe_exits <= 0):'
)
foreach ($contract in $requiredTacticalContracts) {
    if (-not $sourceText.Contains($contract)) { throw "AUTO tactical regression contract is missing: $contract" }
}
if ($sourceText.Contains('if enemies.size() != 1:')) {
    throw 'AUTO companion regression: staging must remain available while multiple enemies are alive.'
}

# Steam parses backslashes as VDF escapes. If this contract changes, Steam can
# truncate H:\Steam-style paths and bypass the bootstrap entirely, which makes
# a healthy UI script appear as if its buttons regressed.
$installerText = Get-Content -LiteralPath $installerSource -Raw
$requiredInstallerContracts = @(
    'return $Value.Replace(''\'', ''\\'').Replace(''"'', ''\"'')',
    'if ((Test-Path -LiteralPath $config) -and (Set-LaunchOptionInVdf $config $steamOption))'
)
foreach ($contract in $requiredInstallerContracts) {
    if (-not $installerText.Contains($contract)) { throw "Steam launch installer contract is missing: $contract" }
}

function Invoke-UiProbe([string]$ManagerPath, [string]$Label) {
    $safeLabel = ($Label -replace '[^A-Za-z0-9]+', '-').Trim('-')
    $resultPath = Join-Path $ReleaseRoot ("ui-regression-$safeLabel.txt")
    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    $argumentLine = @(
        '--headless',
        '--script',
        ('"{0}"' -f $probe),
        '--',
        ('"--manager={0}"' -f $ManagerPath),
        ('"--result={0}"' -f $resultPath)
    ) -join ' '
    $process = Start-Process -FilePath $GameExe -ArgumentList $argumentLine -WorkingDirectory (Split-Path -Parent $GameExe) -WindowStyle Hidden -Wait -PassThru
    if (-not (Test-Path -LiteralPath $resultPath)) {
        throw "AUTO UI regression probe produced no result for ${Label} (exit $($process.ExitCode))."
    }
    $result = Get-Content -LiteralPath $resultPath -Raw
    if ($process.ExitCode -ne 0 -or $result -cne 'PASS') {
        throw "AUTO UI regression probe failed for ${Label} (exit $($process.ExitCode)): $result"
    }
}

Invoke-UiProbe $sourceManager 'source manager'
Invoke-UiProbe $runtimeManager 'packaged runtime'
Write-Host "AUTO UI and critical-tactics regression gate passed for v$Version."
