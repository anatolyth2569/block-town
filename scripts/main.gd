extends Node3D

var _grid_manager: Node3D = null

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.45, 0.65, 0.88))
	_add_environment()
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

func _add_environment() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.65, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.96, 0.98, 0.95)
	env.ambient_light_energy = 0.06
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	env_node.environment = env
	add_child(env_node)

func _add_light() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_color = Color(1.0, 0.99, 0.94)
	light.light_energy = 0.80
	light.shadow_enabled = true
	add_child(light)

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

	# Trade hub — x=10-13, z=1 (clear of left forest which ends at x=9,z=1)
	_spawn_free("res://resources/buildings/trade_depot.tres",      Vector2i(10, 1))
	_spawn_free("res://resources/buildings/fuel_tank.tres",        Vector2i(12, 1))
	_spawn_free("res://resources/buildings/builder_house.tres",    Vector2i(13, 1))

	# Processing — z=2 (x=9 safe; x=7,8 at z=2 are forest)
	_spawn_free("res://resources/buildings/lumberyard.tres",       Vector2i(9, 2))

	# Harvesting — z=3 (woodcutter adjacent to left forest strip)
	_spawn_free("res://resources/buildings/woodcutter_house.tres", Vector2i(6, 3))
	_spawn_free("res://resources/buildings/silo.tres",             Vector2i(10, 3))

	# Farms — z=5
	_spawn_free("res://resources/buildings/farm.tres",             Vector2i(6, 5))
	_spawn_free("res://resources/buildings/farm.tres",             Vector2i(7, 5))
	_spawn_free("res://resources/buildings/farm_house.tres",       Vector2i(11, 5))

	# Water & storage — z=6, west of pond (pond occupies x=8-11 at z=6)
	_spawn_free("res://resources/buildings/well.tres",             Vector2i(6, 6))
	_spawn_free("res://resources/buildings/warehouse.tres",        Vector2i(7, 6))

	# Roads
	for x in range(10, 14):
		gm.build_road(Vector2i(x, 2))   # connector row z=2 (trade hub to lumberyard area)
	for x in range(6, 13):
		gm.build_road(Vector2i(x, 4))   # main road z=4 (avoid pond at 13,4)
	gm.build_road(Vector2i(9, 3))       # vertical link z=3
	gm.build_road(Vector2i(11, 3))      # vertical link z=3

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
