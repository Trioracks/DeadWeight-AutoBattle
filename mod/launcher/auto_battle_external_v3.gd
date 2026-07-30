extends Node

## Tactical autobattle for the whole playable party.
## All actions still go through player_controller, so costs, cooldowns, effects
## and animations are handled by the game itself.


const MAX_DECISIONS_PER_TURN := 7
const MAX_STALEMATE_MOVES := 4
const FALL_KILL_SCORE := 100000.0
const ENEMY_KILL_SCORE := 18000.0
const EMERGENCY_DAMAGE_RATIO := 0.45
const LOW_HP_RATIO := 0.40
const BATTLE_UI_ATTACH_RETRIES := 40
const ICON_OFF_TINT := Color(0.58, 0.58, 0.58, 0.82)

var _signals_bus = null
var _turns = null
var _move_system = null
var _battle_system = null
var _enabled := false
var _auto_preference := false
var _battle_closing := false
var _battle_ui_visible := false
var _battle_nonce := 0
var _turn_running := false
var _active_controller = null
var _decisions_this_turn := 0
var _pending_action := ""
var _overlay: CanvasLayer
var _overlay_root: Control
var _button = null
var _debug_label: Label
var _debug_lines: Array[String] = []
var _bind_attempts := 0
var _disabled_icon_material: ShaderMaterial
var _approach_memory: Dictionary = {}
var _last_consumable_catalog: Dictionary = {}
var _last_talent_profile: Dictionary = {}
var _last_equipment_profile: Dictionary = {}
var _last_meta_profile := ""
var _last_rage_profile: Dictionary = {}
var _rage_followup_controller_id := -1
var _last_party_profile := ""
var _battle_round := 0
var _round_hero_ids: Dictionary = {}


func _ready() -> void:
	_log("AUTO TACTICS v3 LOADED")
	call_deferred("_bind_game")
func _process(_delta: float) -> void:
	if not _battle_ui_visible:
		return
	# The UI attaches only after battle_started was observed once. Afterwards,
	# battle_end is the authoritative signal for leaving the battle UI.
	if _battle_closing:
		_hide_auto_outside_battle()


func _hide_auto_outside_battle() -> void:
	_battle_ui_visible = false
	_enabled = false
	_debug_lines.clear()
	_refresh_debug_label()
	_turn_running = false
	_active_controller = null
	_pending_action = ""
	if is_instance_valid(_button):
		_button.set_pressed_no_signal(false)
		_set_auto_button_visible(false)


func _set_auto_button_visible(is_visible: bool) -> void:
	if not is_instance_valid(_button):
		return
	_button.visible = is_visible
	_button.mouse_filter = Control.MOUSE_FILTER_STOP if is_visible else Control.MOUSE_FILTER_IGNORE


func _bind_game() -> void:
	_signals_bus = get_tree().root.get_node_or_null("SignalsBus")
	_turns = get_tree().root.get_node_or_null("Turns")
	_move_system = get_tree().root.get_node_or_null("MoveSystem")
	_battle_system = get_tree().root.get_node_or_null("BattleSystem")
	if _signals_bus == null or _turns == null or _move_system == null or _battle_system == null:
		_bind_attempts += 1
		if _bind_attempts < 120:
			call_deferred("_bind_game")
		else:
			_log("ERROR: battle singletons not found")
		return

	if not _signals_bus.player_turn.is_connected(_on_player_turn):
		_signals_bus.player_turn.connect(_on_player_turn)
	if not _signals_bus.battle_ready.is_connected(_on_battle_ready):
		_signals_bus.battle_ready.connect(_on_battle_ready)
	if not _signals_bus.battle_end.is_connected(_on_battle_end):
		_signals_bus.battle_end.connect(_on_battle_end)
	_log("threat scanner + tactical controller connected")


func _on_battle_ready() -> void:
	# battle_ready is raised while the scene is still being built. Do not attach
	# a CanvasLayer, inspect a controller, or submit an action in that window.
	# The native game can safely finish its scene transition first.
	_battle_closing = false
	_battle_ui_visible = false
	_battle_round = 0
	_round_hero_ids.clear()
	_debug_lines.clear()
	_enabled = false
	_refresh_debug_label()
	_battle_nonce += 1
	_log("battle ready - waiting for stable combat scene")
	_wait_for_stable_battle_ui.call_deferred(_battle_nonce, 0)


func _wait_for_stable_battle_ui(battle_nonce: int, attempts: int) -> void:
	if _battle_closing or battle_nonce != _battle_nonce:
		return
	if _turns == null or not _turns.battle_started:
		if attempts < BATTLE_UI_ATTACH_RETRIES:
			get_tree().create_timer(0.10).timeout.connect(_wait_for_stable_battle_ui.bind(battle_nonce, attempts + 1), CONNECT_ONE_SHOT)
		else:
			_log("battle UI attach cancelled - battle never became stable")
		return

	_battle_ui_visible = true
	_enabled = _auto_preference
	_ensure_overlay()
	if is_instance_valid(_overlay_root):
		_overlay_root.show()
	if is_instance_valid(_button):
		_button.set_pressed_no_signal(_enabled)
		_set_auto_button_visible(true)
		_update_button_visual()
	_log("battle stable - AUTO attached")
	if _enabled:
		_start_active_player_turn.call_deferred()


func _on_battle_end() -> void:
	_battle_closing = true
	_battle_ui_visible = false
	_battle_nonce += 1
	_enabled = false
	_debug_lines.clear()
	_refresh_debug_label()
	_turn_running = false
	_active_controller = null
	_pending_action = ""
	_approach_memory.clear()
	_last_consumable_catalog.clear()
	_last_talent_profile.clear()
	_last_equipment_profile.clear()
	_last_meta_profile = ""
	_last_rage_profile.clear()
	_last_party_profile = ""
	_rage_followup_controller_id = -1
	if is_instance_valid(_button):
		_button.set_pressed_no_signal(false)
		_update_button_visual()
		_set_auto_button_visible(false)
	if is_instance_valid(_overlay_root):
		_overlay_root.show()


	_battle_round = 0
	_round_hero_ids.clear()
func _ensure_overlay() -> void:
	if is_instance_valid(_button):
		return

	_overlay = CanvasLayer.new()
	_overlay.name = "DeadWeightAutoBattleOverlay"
	_overlay.layer = 100
	get_tree().root.add_child(_overlay)

	var root := Control.new()
	_overlay_root = root
	root.visible = true
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(root)
	_add_debug_label(root)

	# The original text button uses the game's current UI theme, so its panel,
	# border and pressed state match the rest of the combat interface.
	_button = Button.new()
	_button.text = "AUTO"

	_button.name = "auto_battle_button"
	_button.toggle_mode = true
	_button.tooltip_text = "AUTO BATTLE"
	_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_button.custom_minimum_size = Vector2(58.0, 42.0)
	_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# Match the settings button's y-position; keep a small gap immediately left.
	_button.offset_left = -142.0
	_button.offset_top = 35.0
	_button.offset_right = -82.0
	_button.offset_bottom = 77.0
	_button.toggled.connect(_on_auto_toggled)
	root.add_child(_button)
	_button.set_pressed_no_signal(_enabled)
	_set_auto_button_visible(_battle_ui_visible)
	_update_button_visual()
	_log("button ready - AUTO " + ("ON" if _enabled else "OFF"))




func _add_debug_label(parent: Control) -> void:
	_debug_label = Label.new()
	_debug_label.name = "DeadWeightAutoDebug"
	_debug_label.position = Vector2(152.0, 14.0)
	_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_label.add_theme_font_size_override("font_size", 16)
	_debug_label.add_theme_color_override("font_color", Color("f7e6bd"))
	_debug_label.add_theme_color_override("font_outline_color", Color("1a0d08"))
	_debug_label.add_theme_constant_override("outline_size", 3)
	parent.add_child(_debug_label)
	_refresh_debug_label()


func _on_auto_toggled(is_enabled: bool) -> void:
	_enabled = is_enabled
	if not _battle_ui_visible:
		_enabled = false
		_debug_lines.clear()
		_refresh_debug_label()
		if is_instance_valid(_button):
			_button.set_pressed_no_signal(false)
		return

	_auto_preference = _enabled
	_debug_lines.clear()
	_update_button_visual()
	_refresh_debug_label()
	_log("AUTO %s" % ("ON" if _enabled else "OFF"))
	if _enabled:
		_start_active_player_turn.call_deferred()


func _update_button_visual() -> void:
	if not is_instance_valid(_button):
		return
	if _enabled:
		_button.material = null
		_button.modulate = Color.WHITE
		return
	_button.material = _get_disabled_icon_material()
	_button.modulate = ICON_OFF_TINT


func _get_disabled_icon_material() -> ShaderMaterial:
	if _disabled_icon_material != null:
		return _disabled_icon_material
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nvoid fragment() {\n vec4 c = texture(TEXTURE, UV) * COLOR;\n float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));\n COLOR = vec4(vec3(l), c.a);\n}"
	_disabled_icon_material = ShaderMaterial.new()
	_disabled_icon_material.shader = shader
	return _disabled_icon_material


func _on_player_turn(hero_id: int) -> void:
	if _battle_closing:
		return
	_track_battle_round(hero_id)
	_log("player turn: hero %d | round %d" % [hero_id, _battle_round])
	if _enabled:
		_start_active_player_turn.call_deferred()


func _start_active_player_turn() -> void:
	if _battle_closing or not _enabled or _turn_running or _turns == null or not _turns.battle_started:
		return
	var controller = _turns.active_player_controller
	if controller == null or not controller.active or not controller.controlled_object.is_alive():
		return

	_turn_running = true
	_active_controller = controller
	_decisions_this_turn = 0
	_pending_action = ""
	_log_state(controller)
	_decide_next_action.call_deferred()


func _decide_next_action() -> void:
	if _battle_closing:
		return
	if not _has_living_enemies():
		_stop_after_victory()
		return
	var controller = _active_controller
	if not _enabled or not _turn_running or not _is_current_controller_valid(controller):
		_finish_active_turn()
		return
	if _pending_action != "":
		return
	if _decisions_this_turn >= MAX_DECISIONS_PER_TURN:
		_log("decision limit reached")
		_finish_active_turn()
		return

	var plan := _choose_plan(controller)
	if plan.is_empty():
		_log("no legal useful action")
		_finish_active_turn()
		return

	_decisions_this_turn += 1
	if plan.kind == "attack" or plan.kind == "support" or plan.kind == "ultimate" or plan.kind == "consumable":
		var ability = plan.ability
		var target: Vector2i = plan.target
		_pending_action = str(plan.kind)
		if plan.kind == "ultimate":
			_rage_followup_controller_id = int(controller.get_instance_id())
		var action_label := "ATTACK"
		if plan.kind == "support":
			action_label = "SUPPORT"
		elif plan.kind == "ultimate":
			action_label = "ULTIMATE"
		elif plan.kind == "consumable":
			action_label = "ITEM"
		_log("%s %s -> %s | %s" % [action_label, ability.tag, target, plan.reason])
		controller.set_movement_mode(false)
		controller.activate_ability_from_panel(ability)
		call_deferred("_execute_player_attack", controller, ability, target, 0, _battle_nonce)
		return

	if plan.kind == "move":
		var move_target: Vector2i = plan.target
		_pending_action = "move"
		_log("MOVE -> %s | %s" % [move_target, plan.reason])
		controller.movement_done.connect(_on_auto_move_done.bind(controller, _battle_nonce), CONNECT_ONE_SHOT)
		controller.set_movement_mode(true)
		controller.focused_cell = move_target
		controller.move_to_tile(move_target)
		get_tree().create_timer(2.5).timeout.connect(_on_move_timeout.bind(controller, _battle_nonce), CONNECT_ONE_SHOT)
		return

	if plan.kind == "handoff" or plan.kind == "hold":
		_log(str(plan.reason))
		_finish_active_turn()
		return
	_finish_active_turn()



func _execute_player_attack(controller, ability, target: Vector2i, attempts: int = 0, battle_nonce: int = -1) -> void:
	if _battle_closing or battle_nonce != _battle_nonce:
		return
	if not _is_current_controller_valid(controller):
		_finish_active_turn()
		return
	if not controller.activated_combo or controller.selected_ability != ability:
		if attempts < 8:
			get_tree().create_timer(0.05).timeout.connect(_execute_player_attack.bind(controller, ability, target, attempts + 1, battle_nonce), CONNECT_ONE_SHOT)
			return
		_log("attack selection failed: %s" % ability.tag)
		_pending_action = ""
		controller.clear_combo()
		controller.use_ability(false, null)
		_decide_next_action.call_deferred()
		return
	if not ability.can_attack_check(controller.controlled_object.obj_position, target):
		_log("rejected stale target: %s -> %s" % [ability.tag, target])
		_pending_action = ""
		controller.clear_combo()
		controller.use_ability(false, null)
		_decide_next_action.call_deferred()
		return
	controller.toggled_select_tile(target)
	_wait_for_attack(controller, 0, battle_nonce)


func _wait_for_attack(controller, polls: int, battle_nonce: int) -> void:
	if _battle_closing or battle_nonce != _battle_nonce:
		return
	if not _is_current_controller_valid(controller):
		_finish_active_turn()
		return
	if controller.in_attack_state or polls < 3:
		get_tree().create_timer(0.16).timeout.connect(_wait_for_attack.bind(controller, polls + 1, battle_nonce), CONNECT_ONE_SHOT)
		return
	_pending_action = ""
	if not _has_living_enemies():
		_stop_after_victory()
		return
	_clear_approach_memory(controller)
	_log("attack completed")
	_decide_next_action.call_deferred()


func _on_auto_move_done(controller, battle_nonce: int) -> void:
	if _battle_closing or battle_nonce != _battle_nonce:
		return
	if controller != _active_controller or _pending_action != "move":
		return
	_pending_action = ""
	_remember_approach_move(controller)
	_log("move completed")
	_decide_next_action.call_deferred()


func _on_move_timeout(controller, battle_nonce: int) -> void:
	if _battle_closing or battle_nonce != _battle_nonce:
		return
	if controller != _active_controller or not _turn_running or _pending_action != "move":
		return
	_pending_action = ""
	_log("move timeout - reevaluating")
	_decide_next_action.call_deferred()


func _choose_plan(controller) -> Dictionary:
	var hero = controller.controlled_object
	var start: Vector2i = hero.obj_position
	var incoming: int = _incoming_damage_at(start)
	var self_threatened := _is_cell_threatened(start)
	var threatened_party := _get_threatened_player_controllers()
	var other_party_members_threatened := threatened_party.duplicate()
	other_party_members_threatened.erase(controller)
	var support := _choose_best_support(controller)
	var attack := _choose_best_attack(controller, incoming)
	var safe_step := _choose_best_move(controller, incoming, true, true)
	var safe_escape := _choose_best_move(controller, incoming, true, false, self_threatened)
	var attack_then_escape := _choose_attack_then_safe_escape(controller, attack, incoming)
	var recovery_trade := _choose_kill_recovery_trade(controller, incoming)

	var consumable_offense := _choose_best_consumable_offense(controller, incoming)
	var consumable_protection := _choose_best_consumable_protection(controller)
	var escape_energy := _choose_escape_energy_consumable(controller)

	# The same displayed zones that the game paints red are a hard constraint.
	# Damage alone is insufficient: a zero-damage push can still throw a hero off
	# the board, so we only remain when this action removes that exact threat.
	if self_threatened:
		if not attack.is_empty() and bool(attack.self_safe_after):
			attack["reason"] = "CLEAR CURRENT THREAT - " + str(attack.reason)
			return attack
		if not attack_then_escape.is_empty():
			return attack_then_escape

		# A short dodge is worthwhile only if it immediately creates a real hit.
		# Otherwise spend the whole movement budget to leave the enemy's two-cell follow-up.
		var escape_follow_up: Dictionary = safe_step.get("follow_up", {}) if not safe_step.is_empty() else {}
		if not safe_step.is_empty() and _attack_makes_progress(escape_follow_up):
			safe_step["reason"] = "DODGE THEN HIT - " + str(safe_step.reason)
			return safe_step
		# Vitality is a verified, renewable resource: trade one direct point only
		# when this exact hero can kill the sole adjacent attacker next turn and
		# restore every point that it intentionally accepts.
		if not recovery_trade.is_empty():
			return recovery_trade

		if not safe_escape.is_empty():
			safe_escape["reason"] = "FULL-ENERGY ESCAPE - " + str(safe_escape.reason)
			return safe_escape
		if not safe_step.is_empty():
			safe_step["reason"] = "ONLY SAFE DODGE - " + str(safe_step.reason)
			return safe_step
		if not consumable_offense.is_empty() and bool(consumable_offense.get("self_safe_after", false)):
			consumable_offense["reason"] = "NO SAFE EXIT - CLEAR THREAT WITH ITEM - " + str(consumable_offense.reason)
			return consumable_offense
		if not escape_energy.is_empty():
			return escape_energy
		if not support.is_empty() and (bool(support.saves_lethal) or bool(support.prevents_health_damage)):
			support["reason"] = "NO SAFE EXIT - PROTECT SELF - " + str(support.reason)
			return support
		if not consumable_protection.is_empty() and consumable_protection.get("target_controller", null) == controller and (bool(consumable_protection.saves_lethal) or bool(consumable_protection.prevents_health_damage)):
			consumable_protection["reason"] = "NO SAFE EXIT - EMERGENCY ITEM - " + str(consumable_protection.reason)
			return consumable_protection
		# Do not trade ordinary HP for damage. The sole exception above is an
		# explicit Vitality recovery trade, whose next-turn kill has been proved.
		return {
			"kind": "hold",
			"reason": "NO SAFE EXIT - refusing unprotected direct hit"
		}


	# Do not spend a safe hero's AP on routine damage while a companion is still
	# standing in a prepared enemy zone. If this hero cannot remove that threat,
	# end its subturn so the threatened companion receives control and can dodge.
	if not other_party_members_threatened.is_empty():
		if not attack.is_empty() and int(attack.party_threats_after) < threatened_party.size():
			attack["reason"] = "RESCUE COMPANION - " + str(attack.reason)
			return attack
		if not consumable_offense.is_empty() and int(consumable_offense.get("party_threats_after", threatened_party.size())) < threatened_party.size():
			consumable_offense["reason"] = "RESCUE COMPANION WITH ITEM - " + str(consumable_offense.reason)
			return consumable_offense
		if not support.is_empty() and bool(support.saves_lethal):
			var protected_controller = support.target_controller
			if protected_controller != controller and not _support_target_can_escape(protected_controller):
				support["reason"] = "SAVE COMPANION - " + str(support.reason)
				return support
		if not consumable_protection.is_empty() and consumable_protection.get("target_controller", null) != controller and (bool(consumable_protection.saves_lethal) or bool(consumable_protection.prevents_health_damage)):
			consumable_protection["reason"] = "SAVE COMPANION WITH ITEM - " + str(consumable_protection.reason)
			return consumable_protection
		# A companion's red zone is a rescue priority, not a reason to throw
		# away this safe hero's independent AP. Continue with normal safe damage
		# or positioning; the threatened companion still receives its own turn
		# before enemies act.

	var rage_followup := _choose_rage_followup(controller, incoming)
	if not rage_followup.is_empty():
		return rage_followup

	# From a safe cell, take any one-AP move that produces real damage this turn.
	# It is the fastest pattern: dodge, step in, hit, then inspect the next telegraph.
	var move_follow_up: Dictionary = safe_step.get("follow_up", {}) if not safe_step.is_empty() else {}
	if not safe_step.is_empty() and _attack_makes_progress(move_follow_up) and (attack.is_empty() or not bool(attack.lethal) and not bool(attack.fall)):
		safe_step["reason"] = "STEP FOR SAFE HIT - " + str(safe_step.reason)
		return safe_step

	# Immediate kills/falls stay ahead of buffs and positioning.
	if not attack.is_empty() and (bool(attack.lethal) or bool(attack.fall)):
		return attack
	var rage_ultimate := _choose_rage_ultimate(controller, incoming)
	if not rage_ultimate.is_empty():
		return rage_ultimate
	# Finite damage/push items are used from safety only when the game predicts a kill or fall.
	if not consumable_offense.is_empty() and (attack.is_empty() or not _attack_makes_progress(attack)):
		return consumable_offense
	if _attack_makes_progress(attack):
		return attack

	# Against one remaining enemy, use spare AP to occupy a safe staging square:
	# next turn it can attack first and still has a verified full-energy escape.
	var staging := _choose_best_staging_move(controller, incoming)
	if not staging.is_empty():
		return staging
	if _should_hold_stalemate(controller):
		return {
			"kind": "hold",
			"reason": "STALEMATE GUARD - safe staging positions exhausted; waiting for enemy"
		}
	return {
		"kind": "hold",
		"reason": "SAFE HOLD - no safe hit or next-turn staging path"
	}


func _attack_makes_progress(attack: Dictionary) -> bool:
	return not attack.is_empty() and (int(attack.get("enemy_damage", 0)) > 0 or bool(attack.get("fall", false)))



func _choose_attack_then_safe_escape(controller, attack: Dictionary, current_incoming: int) -> Dictionary:
	if attack.is_empty() or not _attack_makes_progress(attack):
		return {}
	if controller == null or not is_instance_valid(controller) or controller.controlled_object == null:
		return {}
	var ability = attack.get("ability", null)
	if ability == null or _is_consumable_ability(controller, ability) or ability.cost_end_turn:
		return {}
	if int(attack.get("self_damage", 0)) > 0:
		return {}
	var remaining_ap: int = int(controller.my_params.action_points) - maxi(0, int(ability.get_final_ap_cost()))
	if remaining_ap <= 0:
		return {}
	# The movement trace uses the actual remaining AP, current red cells, traps,
	# board edges and occupied allies. It is a proof, not a hoped-for retreat.
	var escape := _choose_best_move(controller, current_incoming, true, false, true, remaining_ap)
	if escape.is_empty():
		return {}
	attack["reason"] = "HIT THEN ESCAPE - reserve %d AP to %s; " % [remaining_ap, str(escape.target)] + str(attack.reason)
	return attack


func _get_kill_recovery_hp(controller) -> int:
	if controller == null or not is_instance_valid(controller) or controller.my_params == null:
		return 0
	var recovery := 0
	for perk in controller.my_params.perks:
		if perk is vitality_perk:
			recovery += max(0, int(perk.value))
	return recovery


func _get_direct_damage_attackers(cell: Vector2i) -> Dictionary:
	var controllers: Array = []
	var damage := 0
	for enemy_controller in _turns.enemy_controllers:
		if enemy_controller == null or not is_instance_valid(enemy_controller):
			continue
		var prepared_action = enemy_controller.get_prepared_ability_action()
		if prepared_action == null:
			continue
		var hit := max(0, int(prepared_action.get_predicted_damage_on_cell(cell)))
		if hit <= 0:
			continue
		controllers.append(enemy_controller)
		damage += hit
	return {"controllers": controllers, "damage": damage}


func _choose_guaranteed_kill_on_enemy(controller, start: Vector2i, enemy_controller, available_ap: int) -> Dictionary:
	var best := {}
	var best_score := -INF
	for ability in _get_available_combat_abilities(controller):
		if ability == null or _is_consumable_ability(controller, ability):
			continue
		if int(ability.get_final_ap_cost()) > available_ap:
			continue
		for target: Vector2i in _candidate_targets(ability, start):
			if not ability.can_mechanically_attack(start, target, false, false, false) or not ability.check_terms(start, target):
				continue
			var result := _score_attack(controller, ability, start, target, 0)
			var killed: Array = result.get("killed_enemy_controllers", [])
			if not killed.has(enemy_controller):
				continue
			if float(result.score) > best_score:
				best_score = float(result.score)
				best = result
	return best


func _choose_kill_recovery_trade(controller, incoming: int) -> Dictionary:
	var recovery := _get_kill_recovery_hp(controller)
	if recovery <= 0 or controller == null or not is_instance_valid(controller) or controller.controlled_object == null:
		return {}
	var hero = controller.controlled_object
	var hp := int(controller.my_params.hp)
	var start: Vector2i = hero.obj_position
	# Never accept a push, fall, delayed effect, lethal hit, or damage that cannot
	# be fully restored by the actual Vitality value.
	if incoming <= 0 or incoming >= hp or incoming > recovery or _cell_has_forced_movement_threat(start):
		return {}
	var threat := _get_direct_damage_attackers(start)
	var attackers: Array = threat.controllers
	if attackers.size() != 1 or int(threat.damage) != incoming:
		return {}
	var attacker_controller = attackers[0]
	if attacker_controller == null or not is_instance_valid(attacker_controller) or attacker_controller.controlled_object == null:
		return {}
	var attacker = attacker_controller.controlled_object
	# The forecast is accepted only for a stationary adjacent attacker: it will be
	# in the same cell after resolving its prepared melee strike.
	if not attacker.is_alive() or attacker.obj_position.distance_to(start) > 1.5:
		return {}
	var next_turn_ap := max(int(controller.my_params.action_points_max), int(controller.my_params.action_points))
	var kill := _choose_guaranteed_kill_on_enemy(controller, start, attacker_controller, next_turn_ap)
	if kill.is_empty():
		return {}
	return {
		"kind": "hold",
		"reason": "VITALITY TRADE - take %d direct damage; next-turn kill %s restores %d HP" % [incoming, str(attacker.obj_position), recovery]
	}
func _choose_best_attack(controller, current_incoming: int) -> Dictionary:
	var hero = controller.controlled_object
	return _choose_best_attack_from_cell(controller, hero.obj_position, current_incoming, int(controller.my_params.action_points))


func _get_rage_status(params) -> Dictionary:
	var rage_type = GlobalEnums.STACKABLE_RESOURCE_SUB_MECHANICS.RAGE
	return {
		"current": int(params.get_current_additional_resource(rage_type)),
		"maximum": int(params.get_max_additional_resource(rage_type))
	}


func _get_rage_cost(params, ability) -> int:
	var rage_type = GlobalEnums.STACKABLE_RESOURCE_SUB_MECHANICS.RAGE
	var total_cost := 0
	for resource_needed in ability.additional_resources_needed:
		if resource_needed.resource_type == rage_type:
			var modifier := int(params.get_sm_resource_consumtpion_mod_by_tag(str(ability.tag), rage_type))
			total_cost += max(1, int(resource_needed.amount_needed) + modifier)
	return total_cost


func _is_rage_damage_ultimate(controller, ability) -> bool:
	if ability == null or ability.get_is_ability_an_attack():
		return false
	if _get_rage_cost(controller.my_params, ability) <= 0:
		return false
	for effect in ability.get_all_passive_effects():
		if effect is change_damage_effect_class and int(effect.get_fin_value()) > 0:
			return true
	return false


func _get_rage_damage_bonus(ultimate, attack_ability) -> int:
	var bonus := 0
	for effect in ultimate.get_all_passive_effects():
		if effect is change_damage_effect_class and effect.is_special_for_ability(attack_ability):
			bonus += max(0, int(effect.get_fin_value()))
	return bonus


func _choose_best_melee_attack_from_cell(controller, start: Vector2i, current_incoming: int, available_ap: int) -> Dictionary:
	var best := {}
	var best_score := -INF
	for ability in _get_available_combat_abilities(controller):
		if ability == null or _is_consumable_ability(controller, ability) or not ability.get_is_ability_an_attack():
			continue
		if ability.ability_type != character_ability.ABILITY_TYPE.MELEE:
			continue
		var cost: int = max(0, int(ability.get_final_ap_cost()))
		if cost > available_ap:
			continue
		for target: Vector2i in _candidate_targets(ability, start):
			if not ability.can_mechanically_attack(start, target, false, false, false) or not ability.check_terms(start, target):
				continue
			var result := _score_attack(controller, ability, start, target, current_incoming)
			if float(result.score) > best_score:
				best_score = float(result.score)
				best = result
	return best


func _choose_rage_ultimate(controller, current_incoming: int) -> Dictionary:
	if controller == null or not is_instance_valid(controller):
		return {}
	var hero = controller.controlled_object
	if hero == null or not hero.is_alive():
		return {}
	var start: Vector2i = hero.obj_position
	var rage := _get_rage_status(controller.my_params)
	if int(rage.current) <= 0:
		return {}
	var best := {}
	var best_score := -INF
	for ultimate in _get_available_combat_abilities(controller):
		if not _is_rage_damage_ultimate(controller, ultimate):
			continue
		var rage_cost := _get_rage_cost(controller.my_params, ultimate)
		var ap_cost: int = max(0, int(ultimate.get_final_ap_cost()))
		if int(rage.current) < rage_cost or ap_cost > int(controller.my_params.action_points):
			continue
		if not ultimate.can_mechanically_attack(start, start, false, false, false) or not ultimate.check_terms(start, start):
			continue
		var melee := _choose_best_melee_attack_from_cell(controller, start, current_incoming, int(controller.my_params.action_points) - ap_cost)
		if not _attack_makes_progress(melee) or bool(melee.lethal) or bool(melee.fall):
			continue
		var damage_bonus := _get_rage_damage_bonus(ultimate, melee.ability)
		if damage_bonus <= 0:
			continue
		var score := float(melee.score) + float(damage_bonus) * 1200.0
		if score > best_score:
			best_score = score
			best = {
				"kind": "ultimate",
				"ability": ultimate,
				"target": start,
				"score": score,
				"reason": "RAGE %d/%d, spend %d; +%d damage before %s -> %s" % [int(rage.current), int(rage.maximum), rage_cost, damage_bonus, str(melee.ability.tag), str(melee.target)]
			}
	return best

func _choose_rage_followup(controller, current_incoming: int) -> Dictionary:
	if controller == null or not is_instance_valid(controller) or int(controller.get_instance_id()) != _rage_followup_controller_id:
		return {}
	_rage_followup_controller_id = -1
	var hero = controller.controlled_object
	if hero == null or not hero.is_alive():
		return {}
	var melee := _choose_best_melee_attack_from_cell(controller, hero.obj_position, current_incoming, int(controller.my_params.action_points))
	if not _attack_makes_progress(melee):
		return {}
	melee["reason"] = "RAGE FOLLOW-UP - final buffed damage; " + str(melee.reason)
	return melee


func _print_rage_profile(controller) -> void:
	if controller == null or not is_instance_valid(controller) or controller.controlled_object == null:
		return
	var rage := _get_rage_status(controller.my_params)
	if int(rage.maximum) <= 0:
		return
	var status_entries: Array[String] = []
	var start: Vector2i = controller.controlled_object.obj_position
	for ability in _get_available_combat_abilities(controller):
		if not _is_rage_damage_ultimate(controller, ability):
			continue
		var cost := _get_rage_cost(controller.my_params, ability)
		var ready: bool = int(rage.current) >= cost and ability.can_mechanically_attack(start, start, false, false, false)
		status_entries.append("%s %s (%d)" % [str(ability.tag), "READY" if ready else "charging", cost])
	var profile := "%d/%d#%s" % [int(rage.current), int(rage.maximum), "|".join(status_entries)]
	var controller_key := str(controller.get_instance_id())
	if _last_rage_profile.get(controller_key, "") == profile:
		return
	_last_rage_profile[controller_key] = profile
	_log("rage: %d/%d | %s" % [int(rage.current), int(rage.maximum), ", ".join(status_entries) if not status_entries.is_empty() else "no rage ultimate"])




func _get_support_values(ability) -> Dictionary:
	var values := {"heal": 0, "defence": 0}
	if ability == null:
		return values
	for effect in ability.get_all_passive_effects():
		if effect is full_heal_effect_class:
			values["heal"] = 999
		elif effect is heal_effect_class:
			values["heal"] = int(values["heal"]) + max(0, int(effect.value))
		elif effect is change_defence_effect_class:
			var defence_value: int = int(effect.get_fin_value()) if effect.has_method("get_fin_value") else int(effect.value)
			values["defence"] = int(values["defence"]) + max(0, defence_value)
	return values


func _score_support(controller, ability, target_controller, target: Vector2i, values: Dictionary) -> Dictionary:
	var target_params = target_controller.my_params
	var incoming := _incoming_damage_at(target)
	var direct_hit := incoming > 0 and not _cell_has_forced_movement_threat(target)
	if not direct_hit:
		return {}
	var heal_amount := min(max(0, int(values.get("heal", 0))), max(0, int(target_params.get_max_hp()) - int(target_params.hp)))
	var defence_amount := max(0, int(values.get("defence", 0)))
	if heal_amount <= 0 and defence_amount <= 0:
		return {}
	var shield_estimate := maxi(0, incoming - defence_amount)
	var hp_after_support := min(int(target_params.get_max_hp()), int(target_params.hp) + heal_amount)
	# A shield cannot be trusted to turn a lethal hit into a safe one: armor-piercing
	# and late modifiers may invalidate that estimate. Only real healing may rescue lethal damage.
	var saves_lethal: bool = heal_amount > 0 and incoming >= int(target_params.hp) and hp_after_support > incoming
	var prevents_health_damage: bool = defence_amount > 0 and incoming < int(target_params.hp) and shield_estimate == 0
	var cost: int = max(0, int(ability.get_final_ap_cost()))
	var score := float(heal_amount + defence_amount) * 80.0 - float(cost) * 24.0
	if saves_lethal:
		score += 1000000.0
	elif prevents_health_damage:
		score += 14000.0
	else:
		score += float(incoming) * 500.0
	var protection_text := "heal %d, shield %d, incoming %d, HP after %d" % [heal_amount, defence_amount, incoming, hp_after_support]
	return {
		"kind": "support",
		"ability": ability,
		"target": target,
		"target_controller": target_controller,
		"score": score,
		"saves_lethal": saves_lethal,
		"prevents_health_damage": prevents_health_damage,
		"reason": protection_text
	}



# Consumables are deliberately classified from the actual ability effects at runtime.
# An item without a recognised, deterministic effect is never used automatically.
func _get_recognized_consumables(controller) -> Array:
	var entries: Array = []
	if controller == null or not is_instance_valid(controller):
		return entries
	var seen_tags: Dictionary = {}
	_collect_recognized_consumables(entries, seen_tags, controller, controller.my_params.items, "equipped")
	_collect_recognized_consumables(entries, seen_tags, controller, controller.my_params.quick_items, "belt")
	return entries


func _collect_recognized_consumables(entries: Array, seen_tags: Dictionary, controller, items: Array, source_name: String) -> void:
	for item in items:
		if item == null or int(item.count) <= 0:
			continue
		var ability_tag := str(item.quick_ability_tag)
		if ability_tag.is_empty() or seen_tags.has(ability_tag):
			continue
		var ability = _find_active_consumable_ability(controller, ability_tag)
		if ability == null:
			continue
		var values := _get_consumable_values(ability)
		if not bool(values.get("known", false)):
			continue
		seen_tags[ability_tag] = true
		entries.append({
			"item": item,
			"item_tag": str(item.tag),
			"source": source_name,
			"ability": ability,
			"values": values
		})


func _find_active_consumable_ability(controller, ability_tag: String):
	for ability in _get_available_combat_abilities(controller):
		if ability != null and _is_consumable_ability(controller, ability) and str(ability.tag) == ability_tag:
			return ability
	return null


func _effect_signature(effect) -> String:
	if effect == null:
		return ""
	var signature := str(effect.get_class())
	var script = effect.get_script()
	if script != null and not str(script.resource_path).is_empty():
		signature += " " + str(script.resource_path).get_file().get_basename()
	return signature.to_lower()


func _effect_amount(effect) -> int:
	if effect == null:
		return 0
	if effect.has_method("get_fin_value"):
		return max(0, int(effect.get_fin_value()))
	var raw_value = effect.get("value")
	if raw_value != null:
		return max(0, int(raw_value))
	var endurance = effect.get("endurance")
	if endurance != null:
		return max(0, int(endurance))
	return 0


func _get_consumable_values(ability) -> Dictionary:
	var values := {
		"known": false,
		"heal": 0,
		"defence": 0,
		"block": 0,
		"evasion": false,
		"energy": 0,
		"offense": false,
		"effects": []
	}
	if ability == null:
		return values

	if ability.get_is_ability_an_attack() or _ability_is_push(ability):
		values["known"] = true
		values["offense"] = true
		values["effects"].append("attack/push")

	for effect in ability.get_all_passive_effects():
		if effect == null:
			continue
		var signature := _effect_signature(effect)
		var amount := _effect_amount(effect)
		if effect is full_heal_effect_class or signature.contains("full_heal"):
			values["known"] = true
			values["heal"] = 9999
			values["effects"].append("full heal")
		elif effect is heal_effect_class or signature.contains("heal"):
			values["known"] = true
			values["heal"] = int(values["heal"]) + amount
			values["effects"].append("heal %d" % amount)
		elif effect is change_defence_effect_class or signature.contains("defence") or signature.contains("defense") or signature.contains("armor") or signature.contains("armour"):
			values["known"] = true
			values["defence"] = int(values["defence"]) + amount
			values["effects"].append("shield %d" % amount)
		elif effect is block_damage_oneshot_effect_class or signature.contains("block_damage") or signature.contains("ignore_incoming"):
			values["known"] = true
			values["block"] = int(values["block"]) + max(1, amount)
			values["effects"].append("block %d" % max(1, amount))
		elif signature.contains("dodge") or signature.contains("evad"):
			values["known"] = true
			values["evasion"] = true
			values["effects"].append("evasion")
		elif signature.contains("action_point") or signature.contains("actionpoint") or signature.contains("spurt"):
			if amount > 0:
				values["known"] = true
				values["energy"] = int(values["energy"]) + amount
				values["effects"].append("energy %d" % amount)
	return values


func _can_use_consumable_on(controller, ability, target: Vector2i) -> bool:
	if controller == null or ability == null or controller.controlled_object == null:
		return false
	var start: Vector2i = controller.controlled_object.obj_position
	if not ability.can_mechanically_attack(start, target, false, false, false):
		return false
	return ability.check_terms(start, target) and ability.can_attack_check(start, target)


func _choose_best_consumable_offense(controller, current_incoming: int) -> Dictionary:
	var hero = controller.controlled_object
	if hero == null:
		return {}
	var start: Vector2i = hero.obj_position
	var best := {}
	var best_score := -INF
	for entry in _get_recognized_consumables(controller):
		var values: Dictionary = entry.values
		if not bool(values.get("offense", false)):
			continue
		var ability = entry.ability
		if int(ability.get_final_ap_cost()) > int(controller.my_params.action_points):
			continue
		for target: Vector2i in _candidate_targets(ability, start):
			if not _can_use_consumable_on(controller, ability, target):
				continue
			var result := _score_attack(controller, ability, start, target, current_incoming)
			var clears_current_threat := _is_cell_threatened(start) and bool(result.get("self_safe_after", false))
			var rescues_party := int(result.get("party_threats_after", 99)) < _get_threatened_player_controllers().size()
			if not bool(result.get("lethal", false)) and not bool(result.get("fall", false)) and not clears_current_threat and not rescues_party:
				continue
			result["kind"] = "consumable"
			result["item_tag"] = str(entry.item_tag)
			result["reason"] = "ITEM %s (%s) - %s" % [str(entry.item_tag), ", ".join(values.effects), str(result.reason)]
			if float(result.score) > best_score:
				best_score = float(result.score)
				best = result
	return best


func _score_consumable_protection(controller, entry: Dictionary, target_controller, target: Vector2i) -> Dictionary:
	var values: Dictionary = entry.values
	var target_params = target_controller.my_params
	var incoming := _incoming_damage_at(target)
	if incoming <= 0 or _cell_has_forced_movement_threat(target):
		return {}
	# Let the threatened hero spend its own turn dodging before any finite item is used.
	if _support_target_can_escape(target_controller):
		return {}
	var hp := int(target_params.hp)
	var max_hp := int(target_params.get_max_hp())
	var heal_amount := min(max(0, int(values.get("heal", 0))), max(0, max_hp - hp))
	var defence_amount := max(0, int(values.get("defence", 0)))
	var block_amount := max(0, int(values.get("block", 0)))
	var evasion := bool(values.get("evasion", false))
	var hp_after_heal := min(max_hp, hp + heal_amount)
	var saves_lethal: bool = heal_amount > 0 and incoming >= hp and hp_after_heal > incoming
	# Armour is intentionally excluded from the lethal calculation: penetration and
	# late modifiers can invalidate it. A literal block/evasion is allowed only as
	# the last available defence on a direct, non-forced hit.
	if incoming >= hp and (block_amount >= incoming or evasion):
		saves_lethal = true
	var prevents_health_damage: bool = incoming < hp and (defence_amount >= incoming or block_amount >= incoming or evasion)
	if not saves_lethal and not prevents_health_damage:
		return {}
	var score := 1000000.0 if saves_lethal else 14000.0
	score += float(heal_amount + defence_amount + block_amount) * 80.0
	score -= float(max(0, int(entry.ability.get_final_ap_cost()))) * 24.0
	return {
		"kind": "consumable",
		"ability": entry.ability,
		"target": target,
		"target_controller": target_controller,
		"score": score,
		"saves_lethal": saves_lethal,
		"prevents_health_damage": prevents_health_damage,
		"reason": "ITEM %s (%s) - no exit, incoming %d, HP %d->%d" % [str(entry.item_tag), ", ".join(values.effects), incoming, hp, hp_after_heal]
	}


func _choose_best_consumable_protection(controller) -> Dictionary:
	if _turns == null or controller == null or not is_instance_valid(controller):
		return {}
	var hero = controller.controlled_object
	if hero == null or not hero.is_alive():
		return {}
	var best := {}
	var best_score := -INF
	for entry in _get_recognized_consumables(controller):
		var values: Dictionary = entry.values
		if int(values.get("heal", 0)) <= 0 and int(values.get("defence", 0)) <= 0 and int(values.get("block", 0)) <= 0 and not bool(values.get("evasion", false)):
			continue
		var ability = entry.ability
		if int(ability.get_final_ap_cost()) > int(controller.my_params.action_points):
			continue
		for target_controller in _turns.player_controllers:
			if target_controller == null or target_controller.controlled_object == null or not target_controller.controlled_object.is_alive():
				continue
			var target: Vector2i = target_controller.controlled_object.obj_position
			if not _can_use_consumable_on(controller, ability, target):
				continue
			var plan := _score_consumable_protection(controller, entry, target_controller, target)
			if not plan.is_empty() and float(plan.score) > best_score:
				best_score = float(plan.score)
				best = plan
	return best


func _has_safe_escape_with_bonus_ap(controller, bonus_ap: int) -> bool:
	if controller == null or controller.controlled_object == null or bonus_ap <= 0:
		return false
	var start: Vector2i = controller.controlled_object.obj_position
	var spurt_data = controller.my_params.get_detailed_spurt_data()
	var ignores_traps := _hero_ignores_traps(controller.my_params)
	for cell in _move_system.get_used_cells():
		if cell == start or _move_system.has_character(cell) or _move_system.can_fall_from_cell(cell):
			continue
		if _move_system.is_obstancle_cell(cell) or (_move_system.has_trap(cell) and not ignores_traps):
			continue
		var trace = controller._trace_motion_path(start, cell, spurt_data)
		if trace == null or not trace.has_valid_path() or int(trace.energy) > bonus_ap:
			continue
		if not ignores_traps and _movement_trace_steps_on_trap(trace, start):
			continue
		if not _is_cell_threatened(cell):
			return true
	return false


func _choose_escape_energy_consumable(controller) -> Dictionary:
	if controller == null or controller.controlled_object == null or int(controller.my_params.action_points) > 0:
		return {}
	var start: Vector2i = controller.controlled_object.obj_position
	for entry in _get_recognized_consumables(controller):
		var values: Dictionary = entry.values
		var restored_ap := int(values.get("energy", 0))
		var ability = entry.ability
		if restored_ap <= 0 or int(ability.get_final_ap_cost()) > int(controller.my_params.action_points):
			continue
		if not _can_use_consumable_on(controller, ability, start):
			continue
		if _has_safe_escape_with_bonus_ap(controller, restored_ap):
			return {
				"kind": "consumable",
				"ability": ability,
				"target": start,
				"score": 900000.0,
				"reason": "ITEM %s (%s) - restores AP for a proven safe escape" % [str(entry.item_tag), ", ".join(values.effects)]
			}
	return {}

func _choose_best_support(controller) -> Dictionary:
	if _turns == null or controller == null or not is_instance_valid(controller):
		return {}
	var hero = controller.controlled_object
	if hero == null or not hero.is_alive():
		return {}
	var start: Vector2i = hero.obj_position
	var available_ap: int = int(controller.my_params.action_points)
	var best := {}
	var best_score := -INF
	for ability in _get_available_combat_abilities(controller):
		if ability == null or _is_consumable_ability(controller, ability):
			continue
		var values := _get_support_values(ability)
		if int(values.get("heal", 0)) <= 0 and int(values.get("defence", 0)) <= 0:
			continue
		if int(ability.get_final_ap_cost()) > available_ap:
			continue
		for target_controller in _turns.player_controllers:
			if target_controller == null or target_controller.controlled_object == null or not target_controller.controlled_object.is_alive():
				continue
			var target: Vector2i = target_controller.controlled_object.obj_position
			if not ability.can_mechanically_attack(start, target, false, false, false):
				continue
			if not ability.check_terms(start, target) or not ability.can_attack_check(start, target):
				continue
			var plan := _score_support(controller, ability, target_controller, target, values)
			if not plan.is_empty() and float(plan.score) > best_score:
				best_score = float(plan.score)
				best = plan
	return best


func _support_target_can_escape(target_controller) -> bool:
	if target_controller == null or not is_instance_valid(target_controller) or target_controller.controlled_object == null:
		return false
	var target: Vector2i = target_controller.controlled_object.obj_position
	return not _choose_best_move(target_controller, _incoming_damage_at(target), true, false).is_empty()

func _get_available_combat_abilities(controller) -> Array:
	var final_abilities: Array = []
	if controller == null or not is_instance_valid(controller):
		return final_abilities
	var hero = controller.controlled_object
	if hero != null and is_instance_valid(hero):
		for ability in hero.abilities:
			if ability != null and not final_abilities.has(ability):
				final_abilities.append(ability)
	for ability in controller.my_params.get_character_abilities():
		if ability != null and not final_abilities.has(ability):
			final_abilities.append(ability)
	return final_abilities




func _choose_best_attack_from_cell(controller, start: Vector2i, current_incoming: int, available_ap: int) -> Dictionary:
	var abilities = _get_available_combat_abilities(controller)
	var best := {}
	var best_score := -INF

	for ability in abilities:
		if _is_consumable_ability(controller, ability):
			continue
		var cost: int = max(0, int(ability.get_final_ap_cost()))
		if cost > available_ap:
			continue
		var targets := _candidate_targets(ability, start)
		for target: Vector2i in targets:
			if not ability.can_mechanically_attack(start, target, false, false, false):
				continue
			if not ability.check_terms(start, target):
				continue
			var result := _score_attack(controller, ability, start, target, current_incoming)
			if result.score > best_score:
				best_score = result.score
				best = result
	return best


func _candidate_targets(ability, start: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	_candidate_append(cells, start)
	for enemy_cell in _enemy_cells():
		_candidate_append(cells, enemy_cell)
		for targeting_cell in ability.get_targeting_cells_for_cell_attack(start, enemy_cell):
			_candidate_append(cells, targeting_cell)

	if _ability_is_push(ability):
		for object_cell in _pushable_cells():
			_candidate_append(cells, object_cell)

	return cells


func _score_attack(controller, ability, start: Vector2i, target: Vector2i, current_incoming: int) -> Dictionary:
	var predicted_damage: Dictionary = ability.get_predicted_damage(start, target)
	var selected_cells: Array[Vector2i] = ability.get_selecting_cells(start, target)
	var score := float(ability.priority) * 10.0
	var incoming_after := current_incoming
	var lethal := false
	var fall := false
	var enemy_damage := 0
	var self_damage := 0
	var removed_threat_controllers: Array = []
	var killed_enemy_controllers: Array = []
	var hit_enemy_controllers: Array = []
	var priority_enemy = _get_party_priority_enemy()
	var hits_party_priority := false

	for cell in predicted_damage:
		var target_object = _move_system.get_character(cell)
		var damage: int = max(0, int(predicted_damage[cell]))
		if target_object == null:
			continue
		if target_object.is_enemy_character():
			enemy_damage += damage
			score += float(damage) * 650.0
			if damage > 0 and target_object.my_controller != null and not hit_enemy_controllers.has(target_object.my_controller):
				hit_enemy_controllers.append(target_object.my_controller)
			if target_object == priority_enemy:
				hits_party_priority = true
				score += 2200.0
			if damage >= int(target_object.my_params.hp):
				lethal = true
				score += ENEMY_KILL_SCORE
				if target_object.my_controller != null and not removed_threat_controllers.has(target_object.my_controller):
					removed_threat_controllers.append(target_object.my_controller)
				if target_object.my_controller != null and not killed_enemy_controllers.has(target_object.my_controller):
					killed_enemy_controllers.append(target_object.my_controller)
		elif target_object.is_player_character():
			self_damage += damage
			score -= 50000.0 + float(damage) * 1200.0

	if _ability_is_push(ability):
		var push_result := _score_push_falls(ability, start, target)
		score += float(push_result.score)
		fall = bool(push_result.fall)
		if int(push_result.enemy_falls) > 0:
			lethal = true

		for fallen_controller in push_result.fallen_enemy_controllers:
			if fallen_controller != null and not removed_threat_controllers.has(fallen_controller):
				removed_threat_controllers.append(fallen_controller)
			if fallen_controller != null and not killed_enemy_controllers.has(fallen_controller):
				killed_enemy_controllers.append(fallen_controller)
			if fallen_controller != null and not hit_enemy_controllers.has(fallen_controller):
				hit_enemy_controllers.append(fallen_controller)

	incoming_after = _incoming_damage_at(start, removed_threat_controllers)
	var enemy_hit_count: int = hit_enemy_controllers.size()
	# A second real target is worth more than a cosmetic preference: for equal
	# safety and AP it turns one action into two sources of progress.
	if enemy_hit_count >= 2:
		score += float(enemy_hit_count - 1) * 6500.0

	var self_safe_after := not _is_cell_threatened(start, removed_threat_controllers)
	var party_threats_before := _get_threatened_player_controllers([], controller, start).size()
	var party_threats_after := _get_threatened_player_controllers(removed_threat_controllers, controller, start).size()

	var cost: int = max(0, int(ability.get_final_ap_cost()))
	score -= float(cost) * 24.0
	if ability.cost_end_turn:
		score -= 35.0

	var threat_reduction: int = current_incoming - max(0, incoming_after)
	score += float(threat_reduction) * 3500.0
	if current_incoming > 0 and incoming_after >= current_incoming and not lethal and not fall:
		score -= float(current_incoming) * 180.0
	var self_threatened := _is_cell_threatened(start)
	if self_threatened and not self_safe_after:
		score -= 100000.0
	var party_rescues: int = party_threats_before - party_threats_after
	if party_rescues > 0:
		score += float(party_rescues) * 22000.0
	elif party_threats_after > party_threats_before:
		score -= 30000.0

	if enemy_damage <= 0 and not fall:
		score -= 900.0

	var danger_text := "%s->%s" % ["RED" if self_threatened else "CLEAR", "CLEAR" if self_safe_after else "RED"]
	var reason := "damage %d, targets %d, danger %s, party %d->%d, incoming %d->%d, AP %d" % [enemy_damage, enemy_hit_count, danger_text, party_threats_before, party_threats_after, current_incoming, max(0, incoming_after), cost]
	if fall:
		reason = "PUSH INTO FALL (%s)" % reason
	elif lethal:
		reason = "lethal (%s)" % reason
	if enemy_hit_count >= 2:
		reason = "MULTI-HIT x%d - " % enemy_hit_count + reason
	if hits_party_priority:
		reason = "PARTY FOCUS - " + reason

	return {
		"kind": "attack",
		"ability": ability,
		"target": target,
		"score": score,
		"reason": reason,
		"incoming_after": max(0, incoming_after),
		"lethal": lethal,
		"self_safe_after": self_safe_after,
		"party_threats_after": party_threats_after,
		"fall": fall,
		"self_damage": self_damage,
		"enemy_damage": enemy_damage,
		"enemy_hit_count": enemy_hit_count,
		"killed_enemy_controllers": killed_enemy_controllers
	}


func _score_push_falls(ability, start: Vector2i, target: Vector2i) -> Dictionary:
	var score := 0.0
	var enemy_falls := 0
	var object_falls := 0
	var fallen_enemy_controllers: Array = []
	var already_falling: Array = []
	for mechanic in ability.get_full_mechanics_array():
		if not mechanic is push_base_mechanics:
			continue
		var push_power := 1
		if mechanic.has_method("get_actual_push_power"):
			push_power = max(1, int(mechanic.get_actual_push_power()))
		var chains_data: Dictionary = mechanic.get_affected_chains(start, target, false, push_power)
		for chain_head in chains_data.chains:
			var chain: Array = chains_data.chains[chain_head]
			if chain.is_empty():
				continue
			var tail = chain.back()
			if tail == null or not is_instance_valid(tail) or not tail.is_alive():
				continue
			var tail_cells: Array = chains_data.tails.get(chain_head, [])
			var falls := false
			for tail_cell in tail_cells:
				if _move_system.can_fall_from_cell(Vector2i(tail_cell)):
					falls = true
					break
			if not falls or already_falling.has(tail):
				continue
			already_falling.append(tail)
			if tail.is_enemy_character():
				enemy_falls += 1
				score += FALL_KILL_SCORE
				var fallen_controller = tail.my_controller
				if fallen_controller != null and not fallen_enemy_controllers.has(fallen_controller):
					fallen_enemy_controllers.append(fallen_controller)
			else:
				object_falls += 1
				score += 14000.0
	return {
		"score": score,
		"fall": enemy_falls > 0,
		"enemy_falls": enemy_falls,
		"object_falls": object_falls,
		"fallen_enemy_controllers": fallen_enemy_controllers
	}


func _choose_best_move(controller, current_incoming: int, require_safe: bool = false, one_ap_only: bool = false, flee: bool = false, ap_budget: int = -1) -> Dictionary:
	var hero = controller.controlled_object
	var start: Vector2i = hero.obj_position
	var params = controller.my_params
	var hp: int = max(1, int(params.hp))
	var ap: int = int(params.action_points) if ap_budget < 0 else mini(int(params.action_points), ap_budget)
	var spurt_data = params.get_detailed_spurt_data()
	var ignores_traps := _hero_ignores_traps(params)
	var combat_stance := _get_combat_stance(controller)
	var best := {}
	var best_score := -INF
	var current_threatened := _is_cell_threatened(start)

	if ap <= 0:
		return best

	for cell in _move_system.get_used_cells():
		if cell == start:
			continue
		if _move_system.has_character(cell) or _move_system.can_fall_from_cell(cell):
			continue
		if _move_system.has_trap(cell) and not ignores_traps:
			continue
		if _move_system.is_obstancle_cell(cell):
			continue
		var movement_trace = controller._trace_motion_path(start, cell, spurt_data)
		if movement_trace == null or not movement_trace.has_valid_path():
			continue
		if not ignores_traps and _movement_trace_steps_on_trap(movement_trace, start):
			continue
		var path: Array = movement_trace.get_front_motion_path()
		var energy: int = int(movement_trace.energy)
		if path.is_empty() or energy > ap:
			continue
		if one_ap_only and energy > 1:
			continue

		var incoming := _incoming_damage_at(cell)
		var threatened := _is_cell_threatened(cell)
		if require_safe and threatened:
			continue

		var follow_up := _choose_best_attack_from_cell(controller, cell, incoming, ap - energy)
		var score := _score_move_cell(controller, cell, path.size(), incoming, current_incoming, hp, threatened, current_threatened, combat_stance)
		score -= _recent_position_penalty(controller, cell)
		var escape_profile := {"exits": 0, "max_path": 0}
		if flee:
			var full_turn_ap := max(ap, int(params.action_points_max))
			escape_profile = _get_future_escape_profile(controller, cell, full_turn_ap)
			score += float(int(escape_profile.exits)) * 1100.0
			score += float(int(escape_profile.max_path)) * 300.0
			score += _nearest_enemy_distance(cell) * 650.0
			score += float(energy) * 180.0
			score -= float(_edge_risk(cell)) * 350.0
		if not flee and not follow_up.is_empty():
			if bool(follow_up.lethal) or bool(follow_up.fall):
				score += 50000.0
			else:
				score += minf(5000.0, maxf(0.0, float(follow_up.score)))

		if score > best_score:
			best_score = score
			var follow_up_lethal := not follow_up.is_empty() and (bool(follow_up.lethal) or bool(follow_up.fall))
			var follow_up_text := ""
			if follow_up_lethal:
				follow_up_text = "; next %s -> %s" % [follow_up.ability.tag, follow_up.target]
			var escape_text := ""
			if flee:
				escape_text = "; future exits %d, reach %d" % [int(escape_profile.exits), int(escape_profile.max_path)]
			best = {
				"kind": "move",
				"target": cell,
				"score": score,
				"incoming": incoming,
				"energy": energy,
				"follow_up": follow_up,
				"follow_up_lethal": follow_up_lethal,
				"reason": "danger %s->%s, incoming %d->%d, path %d, AP %d, edge risk %d%s%s" % ["RED" if current_threatened else "CLEAR", "RED" if threatened else "CLEAR", current_incoming, incoming, path.size(), energy, _edge_risk(cell), follow_up_text, escape_text]
			}
	return best



# Counts terrain exits that remain reachable with a fresh turn's movement budget.
# The trace uses the final hero parameters, so equipment such as +1 Step is
# automatically reflected here instead of being guessed from item names.
func _get_future_escape_profile(controller, origin: Vector2i, available_ap: int) -> Dictionary:
	var profile := {"exits": 0, "max_path": 0}
	if controller == null or controller.controlled_object == null or available_ap <= 0:
		return profile
	var params = controller.my_params
	var spurt_data = params.get_detailed_spurt_data()
	var ignores_traps := _hero_ignores_traps(params)
	for cell in _move_system.get_used_cells():
		if cell == origin or _move_system.has_character(cell) or _move_system.can_fall_from_cell(cell):
			continue
		if _move_system.is_obstancle_cell(cell) or (_move_system.has_trap(cell) and not ignores_traps):
			continue
		var trace = controller._trace_motion_path(origin, cell, spurt_data)
		if trace == null or not trace.has_valid_path():
			continue
		var path: Array = trace.get_front_motion_path()
		if path.is_empty() or int(trace.energy) > available_ap:
			continue
		if not ignores_traps and _movement_trace_steps_on_trap(trace, origin):
			continue
		profile["exits"] = int(profile["exits"]) + 1
		profile["max_path"] = maxi(int(profile["max_path"]), path.size())
	return profile


# A safe staging square is not an attack this turn. It deliberately lets the
# enemy reveal its next action, while preserving a legal attack and exit for us.
func _choose_best_staging_move(controller, current_incoming: int) -> Dictionary:
	if controller == null or controller.controlled_object == null:
		return {}
	var enemies := _enemy_cells()
	if enemies.size() != 1:
		return {}
	var hero = controller.controlled_object
	var start: Vector2i = hero.obj_position
	var params = controller.my_params
	var ap := int(params.action_points)
	if ap <= 0:
		return {}
	var next_turn_ap := max(ap, int(params.action_points_max))
	var spurt_data = params.get_detailed_spurt_data()
	var ignores_traps := _hero_ignores_traps(params)
	var stance := _get_combat_stance(controller)
	var desired_distance := int(stance.get("preferred_distance", 1))
	var best := {}
	var best_score := -INF

	for cell in _move_system.get_used_cells():
		if cell == start or _move_system.has_character(cell) or _move_system.can_fall_from_cell(cell):
			continue
		if _move_system.is_obstancle_cell(cell) or (_move_system.has_trap(cell) and not ignores_traps):
			continue
		var trace = controller._trace_motion_path(start, cell, spurt_data)
		if trace == null or not trace.has_valid_path():
			continue
		var path: Array = trace.get_front_motion_path()
		var energy := int(trace.energy)
		if path.is_empty() or energy > ap:
			continue
		if not ignores_traps and _movement_trace_steps_on_trap(trace, start):
			continue
		# The enemy will act before our next turn; never stage in its already shown zone.
		if _is_cell_threatened(cell):
			continue
		var next_attack := _choose_best_attack_from_cell(controller, cell, 0, next_turn_ap)
		if not _attack_makes_progress(next_attack):
			continue
		var exits := _get_future_escape_profile(controller, cell, next_turn_ap)
		if int(exits.exits) <= 0:
			continue

		var distance := _nearest_enemy_distance(cell)
		var score := float(int(exits.exits)) * 1800.0
		score += float(int(exits.max_path)) * 260.0
		score += minf(3500.0, maxf(0.0, float(next_attack.score)) * 0.04)
		score -= absf(distance - float(desired_distance)) * 260.0
		score -= float(_edge_risk(cell)) * 850.0
		score -= float(path.size()) * 35.0
		score -= _party_spacing_penalty(controller, cell)
		if bool(next_attack.lethal) or bool(next_attack.fall):
			score += 1600.0
		if score > best_score:
			best_score = score
			best = {
				"kind": "move",
				"target": cell,
				"score": score,
				"energy": energy,
				"reason": "NEXT-TURN STAGING - %s -> %s; range %.1f, future exits %d, reach %d, AP %d" % [str(next_attack.ability.tag), str(next_attack.target), distance, int(exits.exits), int(exits.max_path), energy]
			}
	return best

func _movement_trace_steps_on_trap(movement_trace, start: Vector2i) -> bool:
	if movement_trace.trap_highlighted_cells.size() > 0:
		return true
	for path_cell in movement_trace.path:
		if path_cell != start and _move_system.has_trap(path_cell):
			return true
	return false
func _hero_ignores_traps(params) -> bool:
	for perk in params.perks:
		if perk is ignore_traps_perk:
			return true
	return false

func _get_weapon_ability_tags(params) -> Array[String]:
	var tags: Array[String] = []
	for item in params.items:
		if item == null or int(item.item_type) != int(item_class.ITEM_TYPE.WEAPON):
			continue
		for modifier in item.effects_arr:
			if modifier != null and not str(modifier.skill_new_tag).is_empty() and not tags.has(str(modifier.skill_new_tag)):
				tags.append(str(modifier.skill_new_tag))
	return tags


func _get_combat_stance(controller) -> Dictionary:
	var ranged_strength := 0
	var melee_strength := 0
	var push_strength := 0
	var preferred_distance := 2
	var weapon_abilities := _get_weapon_ability_tags(controller.my_params)
	for ability in _get_available_combat_abilities(controller):
		if ability == null or not ability.get_is_ability_an_attack():
			continue
		var weapon_weight := 4 if weapon_abilities.has(str(ability.tag)) else 1
		if ability.ability_type == character_ability.ABILITY_TYPE.RANGE or ability.ability_type == character_ability.ABILITY_TYPE.CAST or ability.ability_type == character_ability.ABILITY_TYPE.THROW:
			if int(ability.get_max_distance()) >= 2:
				ranged_strength += weapon_weight
				preferred_distance = maxi(preferred_distance, mini(4, maxi(2, int(ability.get_max_distance()) - 1)))
		elif ability.ability_type == character_ability.ABILITY_TYPE.MELEE:
			melee_strength += weapon_weight
		if _ability_is_push(ability):
			push_strength += weapon_weight
	if ranged_strength > melee_strength:
		return {"mode": "RANGED", "preferred_distance": preferred_distance}
	if push_strength > 0 and push_strength >= melee_strength:
		return {"mode": "PUSH", "preferred_distance": 1}
	return {"mode": "MELEE", "preferred_distance": 1}






func _print_equipment_profile(controller) -> void:
	if controller == null or not is_instance_valid(controller):
		return
	var params = controller.my_params
	var equipment: Array[String] = []
	for item in params.items:
		if item == null:
			continue
		var granted_skills: Array[String] = []
		for modifier in item.effects_arr:
			if modifier != null and not str(modifier.skill_new_tag).is_empty():
				granted_skills.append(str(modifier.skill_new_tag))
		var suffix := " -> " + "+".join(granted_skills) if not granted_skills.is_empty() else ""
		equipment.append(str(item.tag) + suffix)
	var attack_stats: Array[String] = []
	for ability in _get_available_combat_abilities(controller):
		if ability == null or not ability.get_is_ability_an_attack():
			continue
		attack_stats.append("%s(AP%d,R%d)" % [str(ability.tag), int(ability.get_final_ap_cost()), int(ability.get_max_distance())])
	var stance := _get_combat_stance(controller)
	var signature := "|".join(equipment) + "#" + "|".join(attack_stats) + "#" + str(stance)
	var controller_key := str(controller.get_instance_id())
	if _last_equipment_profile.get(controller_key, "") == signature:
		return
	_last_equipment_profile[controller_key] = signature
	_log("equipment: " + (", ".join(equipment) if not equipment.is_empty() else "none"))
	_log("combat profile: %s, safe distance %d; final attacks: %s" % [str(stance.get("mode", "MELEE")), int(stance.get("preferred_distance", 1)), ", ".join(attack_stats)])



func _score_move_cell(controller, cell: Vector2i, path_size: int, incoming: int, current_incoming: int, hp: int, threatened: bool, current_threatened: bool, combat_stance: Dictionary) -> float:
	var score := 0.0
	if threatened:
		return -1000000.0
	if incoming >= hp:
		score -= 1000000.0
	score += float(current_incoming - incoming) * 9000.0
	score -= float(incoming) * 650.0
	score -= float(_edge_risk(cell)) * 450.0
	score -= float(path_size) * 20.0
	score -= _party_spacing_penalty(controller, cell)
	if current_threatened:
		score += 12000.0

	var nearest_enemy := _nearest_enemy_distance(cell)
	if incoming == 0:
		if str(combat_stance.get("mode", "MELEE")) == "RANGED":
			var preferred_distance: int = int(combat_stance.get("preferred_distance", 2))
			score += 360.0 - absf(nearest_enemy - float(preferred_distance)) * 110.0
			if nearest_enemy <= 1.25:
				score -= 900.0
		else:
			score += maxf(0.0, 140.0 - nearest_enemy * 18.0)
	else:
		score -= nearest_enemy * 4.0
	return score


func _edge_risk(cell: Vector2i) -> int:
	var risk := 0
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var adjacent: Vector2i = cell + direction
		if _move_system.can_fall_from_cell(adjacent) and not _move_system.is_obstancle_cell(adjacent):
			risk += 1
	return risk


func _incoming_damage_at(cell: Vector2i, excluded_controllers: Array = []) -> int:
	var damage := 0
	for enemy_controller in _turns.enemy_controllers:
		if excluded_controllers.has(enemy_controller):
			continue
		var prepared_action = enemy_controller.get_prepared_ability_action()
		if prepared_action != null:
			damage += int(prepared_action.get_predicted_damage_on_cell(cell))
	for delayed_activator in _battle_system.delayed_activators:
		if delayed_activator != null:
			damage += int(delayed_activator.get_damage_on_cell(cell))
	return max(0, damage)


func _is_cell_threatened(cell: Vector2i, excluded_controllers: Array = []) -> bool:
	if _incoming_damage_at(cell, excluded_controllers) > 0:
		return true
	for enemy_controller in _turns.enemy_controllers:
		if excluded_controllers.has(enemy_controller):
			continue
		var prepared_action = enemy_controller.get_prepared_ability_action()
		if prepared_action != null and _prepared_action_marks_cell(prepared_action, cell):
			return true
	return false



func _cell_has_forced_movement_threat(cell: Vector2i) -> bool:
	if _turns == null:
		return false
	for enemy_controller in _turns.enemy_controllers:
		var prepared_action = enemy_controller.get_prepared_ability_action()
		if prepared_action == null or not _prepared_action_marks_cell(prepared_action, cell):
			continue
		var ability = prepared_action.prepared_ability
		if ability == null:
			continue
		for mechanic in ability.get_full_mechanics_array():
			if mechanic is push_base_mechanics:
				return true
	return false


func _can_endure_current_direct_threat(controller) -> bool:
	if controller == null or not is_instance_valid(controller) or controller.controlled_object == null:
		return false
	var cell: Vector2i = controller.controlled_object.obj_position
	var incoming := _incoming_damage_at(cell)
	if incoming <= 0 or incoming >= int(controller.my_params.hp):
		return false
	return not _cell_has_forced_movement_threat(cell)


func _prepared_action_marks_cell(prepared_action, cell: Vector2i) -> bool:
	if prepared_action == null or not prepared_action.has_method("_get_actual_target"):
		return false
	var ability = prepared_action.prepared_ability
	var source = prepared_action.assigned_character
	if ability == null or source == null or not source.is_alive():
		return false
	var actual_target: Vector2i = prepared_action._get_actual_target()
	var zones = ability.get_display_zones_to_target_cells(source.obj_position, actual_target)
	for zone in zones:
		if zone != null and zone.cells.has(cell):
			return true
	return false


func _get_threatened_player_controllers(excluded_controllers: Array = [], position_override_controller = null, position_override: Vector2i = Vector2i.ZERO) -> Array:
	var threatened: Array = []
	if _turns == null:
		return threatened
	for player_controller in _turns.player_controllers:
		if player_controller == null or player_controller.controlled_object == null or not player_controller.controlled_object.is_alive():
			continue
		var cell: Vector2i = player_controller.controlled_object.obj_position
		if player_controller == position_override_controller:
			cell = position_override
		if _is_cell_threatened(cell, excluded_controllers):
			threatened.append(player_controller)
	return threatened




# All heroes prefer the same dangerous, low-HP enemy unless a local kill is better.
# This prevents a three-person party from spreading damage across three targets.
func _get_party_priority_enemy():
	if _turns == null:
		return null
	var best_enemy = null
	var best_score := -INF
	for enemy_controller in _turns.enemy_controllers:
		if enemy_controller == null or enemy_controller.controlled_object == null:
			continue
		var enemy = enemy_controller.controlled_object
		if not enemy.is_alive():
			continue
		var hp := max(1, int(enemy.my_params.hp))
		var score := 9000.0 / float(hp)
		var prepared_action = enemy_controller.get_prepared_ability_action()
		if prepared_action != null:
			for player_controller in _turns.player_controllers:
				if player_controller == null or player_controller.controlled_object == null or not player_controller.controlled_object.is_alive():
					continue
				var player = player_controller.controlled_object
				var damage := int(prepared_action.get_predicted_damage_on_cell(player.obj_position))
				if damage > 0:
					score += float(damage) * 750.0
					if damage >= int(player.my_params.hp):
						score += 12000.0
				elif _prepared_action_marks_cell(prepared_action, player.obj_position):
					score += 900.0
		if score > best_score:
			best_score = score
			best_enemy = enemy
	return best_enemy


func _party_spacing_penalty(controller, cell: Vector2i) -> float:
	if _turns == null or _turns.player_controllers.size() < 3:
		return 0.0
	var penalty := 0.0
	for other_controller in _turns.player_controllers:
		if other_controller == null or other_controller == controller or other_controller.controlled_object == null or not other_controller.controlled_object.is_alive():
			continue
		var distance := cell.distance_to(other_controller.controlled_object.obj_position)
		if distance <= 1.1:
			penalty += 900.0
		elif distance <= 1.6:
			penalty += 260.0
	return penalty

func _remember_approach_move(controller) -> void:
	var state := _get_approach_state(controller)
	var cells: Array = state.get("cells", [])
	var position: Vector2i = controller.controlled_object.obj_position
	if cells.is_empty() or cells.back() != position:
		cells.append(position)
	while cells.size() > MAX_STALEMATE_MOVES:
		cells.pop_front()
	state["cells"] = cells
	_approach_memory[_controller_memory_key(controller)] = state


func _clear_approach_memory(controller) -> void:
	_approach_memory.erase(_controller_memory_key(controller))


func _should_hold_stalemate(controller) -> bool:
	var state := _get_approach_state(controller)
	var cells: Array = state.get("cells", [])
	return cells.size() >= MAX_STALEMATE_MOVES


func _recent_position_penalty(controller, cell: Vector2i) -> float:
	var state := _get_approach_state(controller)
	var cells: Array = state.get("cells", [])
	if cells.is_empty():
		return 0.0
	if cells.back() == cell:
		return 7000.0
	if cells.has(cell):
		return 3000.0
	return 0.0


func _get_approach_state(controller) -> Dictionary:
	var key := _controller_memory_key(controller)
	var signature := _enemy_tactical_signature()
	var state: Dictionary = _approach_memory.get(key, {})
	if state.is_empty() or str(state.get("enemy_signature", "")) != signature:
		state = {"enemy_signature": signature, "cells": []}
		_approach_memory[key] = state
	return state


func _controller_memory_key(controller) -> String:
	return str(controller.get_instance_id())


func _enemy_tactical_signature() -> String:
	var parts: Array[String] = []
	if _turns == null:
		return ""
	for enemy_controller in _turns.enemy_controllers:
		if enemy_controller == null or enemy_controller.controlled_object == null:
			continue
		var enemy = enemy_controller.controlled_object
		if not enemy.is_alive():
			continue
		var token := str(enemy.obj_position)
		var prepared = enemy_controller.get_prepared_ability_action()
		if prepared != null and prepared.has_method("_get_actual_target"):
			token += ">" + str(prepared._get_actual_target())
		parts.append(token)
	parts.sort()
	return "|".join(parts)
func _enemy_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if _move_system == null:
		return cells
	for cell in _move_system.characters_positions:
		var target = _move_system.get_character(cell)
		if target != null and target.is_enemy_character() and target.is_alive():
			cells.append(cell)
	return cells

func _has_living_enemies() -> bool:
	if _move_system == null:
		return true
	return not _enemy_cells().is_empty()


func _stop_after_victory() -> void:
	if _battle_closing:
		return
	_enabled = false
	_battle_ui_visible = false
	if is_instance_valid(_button):
		_button.set_pressed_no_signal(false)
		_set_auto_button_visible(false)
	_turn_running = false
	_active_controller = null
	_pending_action = ""
	_approach_memory.clear()
	_rage_followup_controller_id = -1
	_battle_nonce += 1
	_log("victory detected - no end turn")



func _pushable_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in _move_system.characters_positions:
		var target = _move_system.get_character(cell)
		if target != null and not target.is_player_character() and target.is_alive() and target.my_params.movability:
			cells.append(cell)
	return cells


func _nearest_enemy_distance(cell: Vector2i) -> float:
	var nearest := INF
	for enemy_cell in _enemy_cells():
		nearest = minf(nearest, cell.distance_to(enemy_cell))
	return nearest if nearest < INF else 99.0


func _ability_is_push(ability) -> bool:
	if ability == null:
		return false
	for mechanic in ability.get_full_mechanics_array():
		if mechanic is push_base_mechanics:
			return true
	# Kept only for legacy content whose compiled mechanic cannot be inspected.
	return str(ability.tag).to_lower().contains("push")


func _direction_from_to(from: Vector2i, to: Vector2i) -> Vector2i:
	return Vector2i(signi(to.x - from.x), signi(to.y - from.y))


func _candidate_append(cells: Array[Vector2i], cell: Vector2i) -> void:
	if not cells.has(cell):
		cells.append(cell)


func _is_current_controller_valid(controller) -> bool:
	if _battle_closing or _turns == null or controller == null or not is_instance_valid(controller):
		return false
	return controller == _turns.active_player_controller and controller.active and controller.controlled_object.is_alive()


func _finish_active_turn() -> void:
	if _battle_closing:
		return
	if not _has_living_enemies():
		_stop_after_victory()
		return
	var controller = _active_controller
	if controller != null and is_instance_valid(controller) and int(controller.get_instance_id()) == _rage_followup_controller_id:
		_rage_followup_controller_id = -1
	_turn_running = false
	_active_controller = null
	_pending_action = ""
	if controller == null or _turns == null or controller != _turns.active_player_controller:
		return
	if controller.active and controller.controlled_object.is_alive():
		var position: Vector2i = controller.controlled_object.obj_position
		var incoming := _incoming_damage_at(position)
		var danger := _is_cell_threatened(position)
		_log("ending hero turn | HP %d/%d, EN %d/%d, danger %s, incoming %d" % [int(controller.my_params.hp), int(controller.my_params.get_max_hp()), int(controller.my_params.action_points), int(controller.my_params.action_points_max), "RED" if danger else "CLEAR", incoming])
		controller.end_turn()

func _is_consumable_ability(controller, ability) -> bool:
	if ability == null:
		return false
	if bool(ability.is_use_item_abil):
		return true
	if controller == null or not is_instance_valid(controller):
		return false
	var params = controller.my_params
	for item in params.items:
		if item != null and str(item.quick_ability_tag) == str(ability.tag) and not str(item.quick_ability_tag).is_empty():
			return true
	for item in params.quick_items:
		if item != null and str(item.quick_ability_tag) == str(ability.tag) and not str(item.quick_ability_tag).is_empty():
			return true
	return false


func _print_consumable_catalog(controller) -> void:
	if controller == null or not is_instance_valid(controller):
		return
	var hero = controller.controlled_object
	if hero == null or not is_instance_valid(hero):
		return
	var entries: Array[String] = []
	_append_consumable_catalog_entries(entries, controller.my_params.items, "equipped", hero)
	_append_consumable_catalog_entries(entries, controller.my_params.quick_items, "belt", hero)
	var automatic_entries: Array[String] = []
	for entry in _get_recognized_consumables(controller):
		var values: Dictionary = entry.values
		automatic_entries.append("%s=[%s]" % [str(entry.item_tag), ", ".join(values.effects)])
	var signature := " | ".join(entries) + " # AUTO " + " | ".join(automatic_entries)
	var controller_key := str(controller.get_instance_id())
	if _last_consumable_catalog.get(controller_key, "") == signature:
		return
	_last_consumable_catalog[controller_key] = signature
	if entries.is_empty():
		_log("consumables: none")
		return
	_log("consumables: " + ", ".join(entries))
	if automatic_entries.is_empty():
		_log("consumables auto: no recognised deterministic items; unknown items are preserved")
	else:
		_log("consumables auto: " + ", ".join(automatic_entries) + " | unknown items are preserved")


func _append_consumable_catalog_entries(entries: Array[String], items: Array, source_name: String, hero) -> void:
	for index in items.size():
		var item = items[index]
		if item == null or int(item.count) <= 0 or str(item.quick_ability_tag).is_empty():
			continue
		var ability = Database.get_ability_by_tag(str(item.quick_ability_tag))
		var effect_names: Array[String] = []
		if ability != null:
			ability.set_owner(hero)
			for effect in ability.get_all_passive_effects():
				if effect == null:
					continue
				var effect_name: String = str(effect.get_class())
				if effect.get_script() != null and not str(effect.get_script().resource_path).is_empty():
					effect_name = str(effect.get_script().resource_path).get_file().get_basename()
				if effect is heal_effect_class:
					effect_name += "(+" + str(effect.value) + " HP)"
				elif effect is full_heal_effect_class:
					effect_name += "(full HP)"
				elif effect is block_damage_oneshot_effect_class:
					effect_name += "(block " + str(effect.endurance) + ")"
				effect_names.append(effect_name)
		var effect_text := "+".join(effect_names) if not effect_names.is_empty() else "unknown"
		entries.append("%s:%s x%d -> %s [%s]" % [source_name, str(item.tag), int(item.count), str(item.quick_ability_tag), effect_text])



func _print_talent_profile(controller) -> void:
	if controller == null or not is_instance_valid(controller):
		return
	var params = controller.my_params
	var all_tags: Array[String] = []
	for perk_tag in params.perks_tags:
		all_tags.append(str(perk_tag))
	all_tags.sort()
	var tactical: Array[String] = []
	for perk in params.perks:
		if perk is ignore_traps_perk:
			tactical.append("ignore traps")
		elif perk is perk_ability_free_use_class:
			var free_text := "free uses %d" % int(perk.count_free_usage())
			if perk.is_motion_included:
				free_text += " + move"
			tactical.append(free_text)
		elif perk is adrenaline_perk_class:
			tactical.append("adrenaline")
		elif perk is perk_take_position_class and int(perk.damage) > 0:
			tactical.append("hold-position +" + str(int(perk.damage)) + " damage")
		elif perk is perk_push_damage_modificator:
			tactical.append("push collision +" + str(int(perk.additional_damage)))
		elif perk is vitality_perk:
			tactical.append("kill restore +" + str(int(perk.value)) + " HP")
		elif perk is second_wind_perk and not params.survived_in_this_battle:
			tactical.append("second wind +" + str(int(perk.restoring_health)) + " HP")
	var profile := "|".join(all_tags) + "#" + "|".join(tactical)
	var controller_key := str(controller.get_instance_id())
	if _last_talent_profile.get(controller_key, "") == profile:
		return
	_last_talent_profile[controller_key] = profile
	print("[AUTO] active talent tags: " + "|".join(all_tags))
	_log("talents: " + (", ".join(tactical) if not tactical.is_empty() else "stat/passive bonuses applied"))
func _meta_profile_entry(meta_mod) -> String:
	var script_name := "unknown"
	if meta_mod != null and meta_mod.get_script() != null:
		script_name = str(meta_mod.get_script().resource_path).get_file().get_basename()
	match script_name:
		"meta_full_heroes_rest":
			return script_name + " (campaign fatigue only)"
		"meta_mod_hp_recovery_after_battle":
			return script_name + " (post-battle recovery only)"
		"meta_heroes_level", "meta_heroes_bonus_slot":
			return script_name + " (final hero stats/equipment included)"
		"meta_mod_max_stats", "meta_mod_add_max_stats_and_limit":
			return script_name + " (campaign fatigue/stat cap)"
		_:
			return script_name + " (runtime effects used where applicable)"


func _print_meta_profile() -> void:
	if Party == null or not Party.has_method("get_unlocked_meta_mods"):
		return
	var entries: Array[String] = []
	for meta_mod in Party.get_unlocked_meta_mods():
		if meta_mod != null:
			entries.append(_meta_profile_entry(meta_mod))
	entries.sort()
	var profile := "|".join(entries)
	if _last_meta_profile == profile:
		return
	_last_meta_profile = profile
	if entries.is_empty():
		_log("meta: no unlocked upgrades")
	else:
		_log("meta: " + ", ".join(entries))









func _print_party_profile() -> void:
	if _turns == null:
		return
	var entries: Array[String] = []
	for player_controller in _turns.player_controllers:
		if player_controller == null or player_controller.controlled_object == null or not player_controller.controlled_object.is_alive():
			continue
		var role_bits: Array[String] = []
		var ability_tags: Array[String] = []
		var total_heal := 0
		var total_defence := 0
		for ability in _get_available_combat_abilities(player_controller):
			if ability == null:
				continue
			ability_tags.append("%s[%d]" % [str(ability.tag), int(ability.get_final_ap_cost())])
			var support := _get_support_values(ability)
			total_heal += int(support.get("heal", 0))
			total_defence += int(support.get("defence", 0))
		var stance := _get_combat_stance(player_controller)
		role_bits.append(str(stance.get("mode", "MELEE")).to_lower())
		if total_heal > 0:
			role_bits.append("heal +" + str(total_heal))
		if total_defence > 0:
			role_bits.append("shield +" + str(total_defence))
		entries.append("hero %d: %s (%s)" % [int(player_controller.get_instance_id()), ", ".join(role_bits), " ".join(ability_tags)])
	var profile := " | ".join(entries)
	if _last_party_profile == profile:
		return
	_last_party_profile = profile
	_log("party %d: %s" % [entries.size(), profile if not profile.is_empty() else "none"])
func _log_state(controller) -> void:
	var hero = controller.controlled_object
	var params = controller.my_params
	var pos: Vector2i = hero.obj_position
	var incoming := _incoming_damage_at(pos)
	var self_threatened := _is_cell_threatened(pos)
	var threatened_party := _get_threatened_player_controllers()
	var skill_text := ""
	for ability in _get_available_combat_abilities(controller):
		skill_text += "%s[%d] " % [ability.tag, int(ability.get_final_ap_cost())]
	_log("HP %d/%d | EN %d/%d | danger %s | incoming %d | party red %d" % [params.hp, params.get_max_hp(), params.action_points, params.action_points_max, "RED" if self_threatened else "CLEAR", incoming, threatened_party.size()])
	_print_talent_profile(controller)
	_print_party_profile()
	_print_rage_profile(controller)
	_print_equipment_profile(controller)
	_print_meta_profile()
	_print_consumable_catalog(controller)
	print("[AUTO] available skills: " + skill_text.strip_edges())


func _track_battle_round(hero_id: int) -> void:
	# Player-turn signals follow the same party cycle as the round banner. A
	# repeated hero starts the next round; this also survives companions dying.
	if hero_id < 0:
		return
	if _battle_round <= 0:
		_battle_round = 1
	elif _round_hero_ids.has(hero_id):
		_battle_round += 1
		_round_hero_ids.clear()
	_round_hero_ids[hero_id] = true


func _find_node_with_script_path(node: Node, script_path: String) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	var node_script = node.get_script()
	if node_script != null and str(node_script.resource_path) == script_path:
		return node
	for child in node.get_children():
		var found := _find_node_with_script_path(child, script_path)
		if found != null:
			return found
	return null




func _log(message: String) -> void:
	var entry := "[AUTO] " + message
	print(entry)
	# Console logging remains available for diagnostics, but the combat overlay
	# receives messages only while the player has explicitly enabled AUTO.
	if not _enabled or not _battle_ui_visible:
		return
	_debug_lines.append(entry)
	if _debug_lines.size() > 5:
		_debug_lines.pop_front()
	_refresh_debug_label()


func _refresh_debug_label() -> void:
	if not is_instance_valid(_debug_label):
		return
	_debug_label.visible = _enabled and _battle_ui_visible
	if not _debug_label.visible:
		_debug_label.text = ""
		return
	var text := "AUTO DEBUG\n"
	for entry in _debug_lines:
		text += entry + "\n"
	_debug_label.text = text.strip_edges()
