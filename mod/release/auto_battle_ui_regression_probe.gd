extends SceneTree

## Loads the real AUTO Battle manager through Dead Weight's own Godot runtime,
## then exercises the exact UI construction path used in combat.  This is a
## release gate: a script parse error, a missing add_child call, or a renamed
## button fails the process before a package can be published.

const DEFAULT_MANAGER_PATH := "../launcher/auto_battle_external_v3.gd"
var _result_path := ""


func _init() -> void:
	_result_path = _argument_value("--result=")
	call_deferred("_run_probe")


func _manager_path() -> String:
	var supplied_path := _argument_value("--manager=")
	if not supplied_path.is_empty():
		return supplied_path
	return get_script().resource_path.get_base_dir().path_join(DEFAULT_MANAGER_PATH).simplify_path()


func _argument_value(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _write_result(result: String) -> void:
	if _result_path.is_empty():
		return
	var file := FileAccess.open(_result_path, FileAccess.WRITE)
	if file != null:
		file.store_string(result)
		file.close()


func _fail(message: String) -> void:
	_write_result("FAIL: " + message)
	push_error("[AUTO UI REGRESSION] FAIL: " + message)
	quit(1)


func _run_probe() -> void:
	var manager_path: String = _manager_path()
	var manager_script = load(manager_path)
	if manager_script == null:
		_fail("cannot load manager: " + manager_path)
		return

	var manager = manager_script.new()
	if manager == null:
		_fail("cannot instantiate manager")
		return
	root.add_child(manager)
	manager._ensure_overlay()

	var auto_button = manager._button as Button
	var companions_button = manager._companions_button as Button
	if auto_button == null or companions_button == null:
		_fail("both AUTO controls must be constructed")
		return
	if auto_button.name != "auto_battle_button" or auto_button.text != "AUTO":
		_fail("primary AUTO button contract changed")
		return
	if companions_button.name != "auto_companions_button" or companions_button.text != "ONLY COMPANIONS":
		_fail("ONLY COMPANIONS button contract changed")
		return
	if not auto_button.toggle_mode or not companions_button.toggle_mode:
		_fail("AUTO controls must remain toggle buttons")
		return
	if not auto_button.toggled.is_connected(Callable(manager, "_on_auto_toggled")):
		_fail("AUTO toggle is not connected")
		return
	if not companions_button.toggled.is_connected(Callable(manager, "_on_companions_toggled")):
		_fail("ONLY COMPANIONS toggle is not connected")
		return

	manager._battle_ui_visible = true
	manager._on_auto_toggled(true)
	if not manager._enabled or manager._companions_only:
		_fail("AUTO must enable the full-party mode")
		return
	manager._on_auto_toggled(false)
	if manager._enabled or manager._companions_only:
		_fail("AUTO must disable cleanly")
		return

	_write_result("PASS")
	print("[AUTO UI REGRESSION] PASS")
	quit(0)
