extends Node

const SAVE_PATH := "res://saves/save.json"
const SAVE_VERSION := 1

var _auto_save_timer: Timer = null

func _ready() -> void:
	_auto_save_timer = Timer.new()
	_auto_save_timer.wait_time = 30.0
	_auto_save_timer.autostart = false
	_auto_save_timer.timeout.connect(save_game)
	add_child(_auto_save_timer)
	get_tree().set_auto_accept_quit(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
		get_tree().quit()

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func start_auto_save() -> void:
	if _auto_save_timer != null:
		_auto_save_timer.start()

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)

# ── Save ──────────────────────────────────────────────

func save_game() -> void:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	var rm = get_node_or_null("/root/ResourceManager")
	var om = get_node_or_null("/root/OrderManager")
	if gm == null or rm == null or om == null:
		return

	var game_mgr = get_node_or_null("/root/GameManager")
	var data := {
		"version": SAVE_VERSION,
		"timestamp": int(Time.get_unix_time_from_system()),
		"province": game_mgr.selected_province if game_mgr != null else "",
		"resources": rm.get_save_data(),
		"roads": _collect_roads(gm),
		"buildings": _collect_buildings(gm),
		"fields": _collect_fields(gm),
		"tree_harvests": _collect_trees(gm),
		"orders": om.get_save_data(),
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write to " + SAVE_PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func _collect_roads(gm) -> Array:
	var result: Array = []
	for cell in gm._terrain:
		var t: int = gm._terrain[cell]
		if t == GridManager.Terrain.ROAD:
			result.append({"x": cell.x, "z": cell.y, "type": "road"})
		elif t == GridManager.Terrain.PAVED_ROAD:
			result.append({"x": cell.x, "z": cell.y, "type": "paved"})
	return result

func _collect_buildings(gm) -> Array:
	var result: Array = []
	var seen: Array = []
	for cell in gm._buildings:
		var bld = gm._buildings[cell]
		if seen.has(bld):
			continue
		seen.append(bld)
		if not (bld is Building):
			continue
		var b := bld as Building
		if b.data == null or not b._is_active:
			continue
		result.append({
			"id": b.data.id,
			"cell_x": b.origin_cell.x,
			"cell_z": b.origin_cell.y,
			"facing": b.facing,
			"local_stock": b._local_stock.duplicate(),
			"input_stock": b._input_stock.duplicate(),
		})
	return result

func _collect_fields(gm) -> Array:
	var result: Array = []
	for cell in gm._field_harvest_at:
		result.append({"x": cell.x, "z": cell.y, "harvest_at": gm._field_harvest_at[cell]})
	return result

func _collect_trees(gm) -> Array:
	var result: Array = []
	for cell in gm._tree_harvests:
		result.append({"x": cell.x, "z": cell.y, "remaining": gm._tree_harvests[cell]})
	return result

# ── Load ──────────────────────────────────────────────

func load_game(gm) -> bool:
	if not has_save():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveManager: cannot read " + SAVE_PATH)
		return false
	var text := file.get_as_text()
	file.close()

	var data = JSON.parse_string(text)
	if not (data is Dictionary):
		push_error("SaveManager: corrupted save file")
		return false

	var rm = get_node_or_null("/root/ResourceManager")
	var om = get_node_or_null("/root/OrderManager")
	var game_mgr_load = get_node_or_null("/root/GameManager")

	# Restore province
	if game_mgr_load != null and data.has("province"):
		game_mgr_load.selected_province = str(data["province"])

	# Restore currency
	if rm != null and data.has("resources"):
		rm.load_from_save(data["resources"])

	# Restore roads
	if data.has("roads"):
		for road in data["roads"]:
			var cell := Vector2i(int(road["x"]), int(road["z"]))
			var type_str: String = road.get("type", "road")
			gm.build_road(cell)
			if type_str == "paved":
				gm.build_paved_road(cell)

	# Restore buildings
	if data.has("buildings"):
		for bdata in data["buildings"]:
			_restore_building(gm, bdata)

	# Restore field timers
	if data.has("fields"):
		for f in data["fields"]:
			if not (f.has("x") and f.has("z") and f.has("harvest_at")):
				continue
			var cell := Vector2i(int(f["x"]), int(f["z"]))
			gm._field_harvest_at[cell] = float(f["harvest_at"])

	# Restore tree harvest counts
	if data.has("tree_harvests"):
		for t in data["tree_harvests"]:
			if not (t.has("x") and t.has("z") and t.has("remaining")):
				continue
			var cell := Vector2i(int(t["x"]), int(t["z"]))
			gm._tree_harvests[cell] = int(t["remaining"])

	# Restore orders
	if om != null and data.has("orders"):
		om.load_from_save(data["orders"])

	start_auto_save()
	return true

func _restore_building(gm, bdata: Dictionary) -> void:
	var bid: String = bdata.get("id", "")
	var path := "res://resources/buildings/" + bid + ".tres"
	if not ResourceLoader.exists(path):
		push_warning("SaveManager: building resource not found: " + path)
		return
	var bd: BuildingData = load(path) as BuildingData
	if bd == null:
		return
	var cell := Vector2i(int(bdata.get("cell_x", 0)), int(bdata.get("cell_z", 0)))
	if not gm.is_area_free(cell, bd.size):
		return
	var building := Building.new()
	building.data = bd
	building.origin_cell = cell
	building.facing = bdata.get("facing", 0)
	building.rotation_degrees.y = building.facing * 90.0
	building.skip_construction = true
	gm.place_building(building, bd, cell)
	# Restore stocks after _ready() has run
	if bdata.has("local_stock"):
		building._local_stock.clear()
		for res in bdata["local_stock"]:
			building._local_stock[res] = int(bdata["local_stock"][res])
	if bdata.has("input_stock"):
		building._input_stock.clear()
		for res in bdata["input_stock"]:
			building._input_stock[res] = int(bdata["input_stock"][res])
