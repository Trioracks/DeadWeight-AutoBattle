extends SceneTree

const MAIN_SCENE := "res://UI/WinhudLayers/Wins/start_menu.tscn"


func _init() -> void:
	call_deferred("_boot")


func _boot() -> void:
	print("[DW LAUNCH] external auto-battle launcher started")
	# This launcher is started as an external Godot script. Resolving the
	# manager beside this file keeps the package portable: neither the Steam
	# library letter nor the installer's Windows account is baked into the mod.
	var manager_path: String = get_script().resource_path.get_base_dir().path_join("auto_battle_external_v3.gd")
	var manager_script = load(manager_path)
	if manager_script == null:
		quit(1)
		return

	var manager = manager_script.new()
	root.add_child(manager)
	var error = change_scene_to_file(MAIN_SCENE)
	if error != OK:
		push_error("[DW LAUNCH] Cannot open main scene: %s" % MAIN_SCENE)
		quit(error)
