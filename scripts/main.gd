extends Node3D

var _grid_manager: Node3D = null

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.4, 0.65, 1.0))
	_add_light()
	_add_camera()
	_add_grid()
	_add_placer()
	_add_hud()
	var sm = get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_save():
		sm.load_game(_grid_manager)
	else:
		_place_starter_buildings()
		if sm != null:
			sm.start_auto_save()

func _add_light() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -35, 0)
	light.light_energy = 1.5
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 145, 0)
	fill.light_energy = 0.4
	add_child(fill)

func _add_camera() -> void:
	var script = load("res://scripts/camera_controller.gd")
	var cam := Camera3D.new()
	if script:
		cam.set_script(script)
	cam.position = Vector3(10, 30, 55)
	add_child(cam)
	cam.look_at(Vector3(30, 0, 30), Vector3.UP)

func _add_grid() -> void:
	var script = load("res://scripts/grid_manager.gd")
	if script == null:
		push_error("grid_manager.gd failed to load!")
		return
	var gm := Node3D.new()
	gm.name = "GridManager"
	gm.set_script(script)
	add_child(gm)
	_grid_manager = gm

func _add_placer() -> void:
	var script = load("res://scripts/building_placer.gd")
	if script == null:
		push_error("building_placer.gd failed to load!")
		return
	var bp := Node3D.new()
	bp.name = "BuildingPlacer"
	bp.set_script(script)
	add_child(bp)

func _add_hud() -> void:
	var script = load("res://scripts/hud.gd")
	if script == null:
		push_error("hud.gd failed to load!")
		return
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var hud := Control.new()
	hud.name = "HUD"
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.set_script(script)
	canvas.add_child(hud)

# --- Starter layout (Town Star style) ---

func _place_starter_buildings() -> void:
	if _grid_manager == null:
		return
	var gm := _grid_manager as GridManager
	if gm == null:
		return

	# === Row 1 — Trade Depot + Fuel Tank + Builder House ===
	_spawn_free("res://resources/buildings/trade_depot.tres",       Vector2i(7, 1))
	_spawn_free("res://resources/buildings/fuel_tank.tres",         Vector2i(8, 1))
	_spawn_free("res://resources/buildings/builder_house.tres",     Vector2i(9, 1))

	# === Row 2 — Lumberyard ===
	_spawn_free("res://resources/buildings/lumberyard.tres",        Vector2i(10, 2))

	# === Row 3 — Woodcutter House + Silo ===
	_spawn_free("res://resources/buildings/woodcutter_house.tres",  Vector2i(8, 3))
	_spawn_free("res://resources/buildings/silo.tres",              Vector2i(10, 3))

	# === Row 5 — Wheat Farm + Farm House ===
	_spawn_free("res://resources/buildings/farm.tres",              Vector2i(6, 5))
	_spawn_free("res://resources/buildings/farm.tres",              Vector2i(7, 5))
	_spawn_free("res://resources/buildings/farm_house.tres",        Vector2i(11, 5))

	# === Row 6 — Well + Warehouse (pond in terrain) ===
	_spawn_free("res://resources/buildings/well.tres",              Vector2i(9, 6))
	_spawn_free("res://resources/buildings/warehouse.tres",         Vector2i(10, 6))  # processed goods warehouse

	# === Roads ===
	for x in range(6, 10):
		gm.build_road(Vector2i(x, 2))    # horizontal row 2: (6-9, 2)
	for z in range(3, 6):
		gm.build_road(Vector2i(9, z))    # vertical col 9: (9, 3-5)
	gm.build_road(Vector2i(8, 5))        # row 5 extra
	gm.build_road(Vector2i(10, 5))       # row 5 extra

func _spawn_free(path: String, cell: Vector2i) -> void:
	if not ResourceLoader.exists(path):
		return
	var bd: BuildingData = load(path) as BuildingData
	if bd == null:
		return
	var gm := _grid_manager as GridManager
	if gm == null or not gm.is_area_free(cell, bd.size):
		return
	var building := Building.new()
	building.data = bd
	building.origin_cell = cell
	building.skip_construction = true
	gm.place_building(building, bd, cell)
