extends Node3D

var _game_manager: Node
var _grid_manager: GridManager
var _resource_manager: Node

var _preview: Node3D = null
var _current_cell: Vector2i = Vector2i(-999, -999)
var _is_valid: bool = false
var _rotation: int = 0  # 0/1/2/3 = 0°/90°/180°/270°

var _mat_valid: StandardMaterial3D
var _mat_invalid: StandardMaterial3D

var _left_press_pos: Vector2 = Vector2(-9999, -9999)
const CLICK_THRESHOLD: float = 6.0

var _confirming: bool = false
var _locked_cell: Vector2i = Vector2i(-999, -999)

func _ready() -> void:
	add_to_group("building_placer")
	_game_manager = get_node_or_null("/root/GameManager")
	_resource_manager = get_node_or_null("/root/ResourceManager")

	if _game_manager == null:
		push_error("BuildingPlacer: GameManager not found")
		return
	if _resource_manager == null:
		push_error("BuildingPlacer: ResourceManager not found")
		return

	_game_manager.state_changed.connect(_on_state_changed)

	_mat_valid = StandardMaterial3D.new()
	_mat_valid.albedo_color = Color(0.0, 1.0, 0.3, 0.5)
	_mat_valid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_mat_invalid = StandardMaterial3D.new()
	_mat_invalid.albedo_color = Color(1.0, 0.1, 0.1, 0.5)
	_mat_invalid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	print("[BuildingPlacer] ready")

func _process(_delta: float) -> void:
	if _game_manager == null or not _game_manager.is_placing():
		return
	if _confirming:
		return  # preview is locked, no update needed
	if _grid_manager == null:
		_grid_manager = get_tree().get_first_node_in_group("grid_manager") as GridManager
		if _grid_manager == null:
			return
	_update_preview()

func _get_rotated_size(data: BuildingData) -> Vector2i:
	if _rotation % 2 == 1:
		return Vector2i(data.size.y, data.size.x)
	return data.size

func _unhandled_input(event: InputEvent) -> void:
	if _game_manager == null:
		return
	# Press R to rotate building 90° while placing
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).keycode == KEY_R and _game_manager.is_placing():
			_rotation = (_rotation + 1) % 4
			if _preview != null:
				_preview.queue_free()
				_preview = null
			_current_cell = Vector2i(-999, -999)
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	# Track press position to distinguish click from drag
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_left_press_pos = mb.position
	# IDLE left release → if mouse did not move beyond threshold = real click
	if _game_manager.current_state == 0 and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		var moved := mb.position.distance_to(_left_press_pos)
		if moved < CLICK_THRESHOLD:
			if _grid_manager == null:
				_grid_manager = get_tree().get_first_node_in_group("grid_manager") as GridManager
			if _grid_manager != null:
				var cell: Vector2i = _get_hovered_cell()
				if _grid_manager._buildings.has(cell):
					var bld: Node = _grid_manager._buildings[cell]
					_game_manager.show_building_info(bld)
				elif _grid_manager.get_terrain(cell) == GridManager.Terrain.WATER:
					var pond_origin := _grid_manager.get_pond_at(cell)
					if pond_origin != Vector2i(-1, -1):
						_game_manager.pond_cell_clicked.emit(cell)
				elif _grid_manager.is_cell_valid(cell):
					if _grid_manager.get_terrain(cell) == GridManager.Terrain.FOREST:
						_game_manager.forest_cell_clicked.emit(cell)
					else:
						_game_manager.empty_cell_clicked.emit()
				get_viewport().set_input_as_handled()
		_left_press_pos = Vector2(-9999, -9999)
		return
	if _game_manager.is_placing():
		if _confirming:
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _is_valid:
				_enter_confirm_mode()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_game_manager.cancel_placement()
	elif _game_manager.is_demolishing():
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_try_demolish()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_game_manager.cancel_placement()
	elif _game_manager.is_placing_road():
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_try_place_road()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_game_manager.cancel_placement()

func _update_preview() -> void:
	var data = _game_manager.selected_building_data
	if data == null:
		return

	var cell := _get_hovered_cell()
	if cell == _current_cell and _preview != null:
		return
	_current_cell = cell

	if _preview == null:
		_preview = _build_preview_mesh(data)
		add_child(_preview)

	var rsz := _get_rotated_size(data)
	_is_valid = _grid_manager.is_area_free(cell, rsz)

	if _is_valid and not _is_no_road_building(data):
		_is_valid = _grid_manager.is_area_adjacent_to_road(cell, rsz)

	if _is_valid and data.id == "trade_depot":
		_is_valid = _is_on_map_edge(cell, rsz)

	var wp := _grid_manager.cell_to_world(cell)
	wp.x += rsz.x * GridManager.CELL_SIZE * 0.5
	wp.z += rsz.y * GridManager.CELL_SIZE * 0.5
	_preview.position = wp
	_preview.rotation_degrees.y = _rotation * 90.0

	var mat := _mat_valid if _is_valid else _mat_invalid
	for child in _preview.get_children():
		if child is MeshInstance3D:
			child.material_override = mat

func _build_preview_mesh(data) -> Node3D:
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(
		data.size.x * GridManager.CELL_SIZE * 0.62,
		1.1,
		data.size.y * GridManager.CELL_SIZE * 0.62
	)
	mi.mesh = box
	mi.position = Vector3(0, 0.55, 0)
	node.add_child(mi)
	return node

func _enter_confirm_mode() -> void:
	_confirming = true
	_locked_cell = _current_cell
	var world_pos := _preview.position if _preview != null else Vector3.ZERO
	_game_manager.placement_confirming.emit(world_pos)

func confirm_and_place() -> void:
	if not _confirming:
		return
	_confirming = false
	_game_manager.placement_confirm_done.emit()
	var data = _game_manager.selected_building_data
	if data == null or _grid_manager == null:
		return
	var rsz := _get_rotated_size(data)
	if not _grid_manager.is_area_free(_locked_cell, rsz):
		return
	if not _is_no_road_building(data) and not _grid_manager.is_area_adjacent_to_road(_locked_cell, rsz):
		return
	var gold_cost: int = data.build_cost.get("Gold", 0)
	if gold_cost > 0 and not _resource_manager.pay({"Gold": gold_cost}):
		return
	var building := Building.new()
	building.data = data
	building.origin_cell = _locked_cell
	building.facing = _rotation
	building.rotation_degrees.y = _rotation * 90.0
	_grid_manager.place_building(building, data, _locked_cell, rsz)
	# Do not cancel_placement — stay in mode to keep building
	if _preview != null:
		_preview.queue_free()
		_preview = null
	_current_cell = Vector2i(-999, -999)

func cancel_confirmation() -> void:
	if not _confirming:
		return
	_confirming = false
	_game_manager.placement_confirm_done.emit()
	# preview will re-float in the next frame

func _try_place() -> void:
	if not _is_valid:
		return
	var data = _game_manager.selected_building_data
	if data == null:
		return
	var gold_cost: int = data.build_cost.get("Gold", 0)
	if gold_cost > 0 and not _resource_manager.pay({"Gold": gold_cost}):
		return

	var building := Building.new()
	building.data = data
	building.origin_cell = _current_cell
	building.rotation_degrees.y = _rotation * 90.0

	_grid_manager.place_building(building, data, _current_cell, _get_rotated_size(data))
	_rotation = 0
	_game_manager.cancel_placement()

func _try_demolish() -> void:
	if _grid_manager == null:
		_grid_manager = get_tree().get_first_node_in_group("grid_manager") as GridManager
		if _grid_manager == null:
			return
	var cell := _get_hovered_cell()
	var t: int = _grid_manager.get_terrain(cell)
	if _grid_manager.is_road_terrain(t):
		_grid_manager.remove_road_at(cell)
	else:
		_grid_manager.remove_building_at(cell)
		_game_manager.cancel_placement()  # demolish building then exit mode

func _try_place_road() -> void:
	if _grid_manager == null:
		_grid_manager = get_tree().get_first_node_in_group("grid_manager") as GridManager
		if _grid_manager == null:
			return
	var cell := _get_hovered_cell()
	if _game_manager.road_is_paved:
		_grid_manager.build_paved_road(cell)
	else:
		_grid_manager.build_road(cell)
	# Stay in road-placing mode so player can drag-build multiple tiles

func _is_on_map_edge(cell: Vector2i, size: Vector2i) -> bool:
	if _grid_manager == null:
		return false
	var dirs := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for dx in range(size.x):
		for dz in range(size.y):
			var c := cell + Vector2i(dx, dz)
			for d in dirs:
				if _grid_manager.get_terrain(c + d) == GridManager.Terrain.WATER:
					return true
	return false

func _get_hovered_cell() -> Vector2i:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2i.ZERO
	var mouse := get_viewport().get_mouse_position()
	var ro := cam.project_ray_origin(mouse)
	var rd := cam.project_ray_normal(mouse)
	if absf(rd.y) < 0.001:
		return Vector2i.ZERO
	var t := -ro.y / rd.y
	var hit := ro + rd * t
	return _grid_manager.world_to_cell(hit)

const _NO_ROAD_CATEGORIES: Array = [
	"farm", "sugarcane_field", "cotton_field", "pumpkin_patch", "corn_field",
	"tomato_field", "salt_field", "tree_farm",
	"animal_barn", "chicken_coop", "sheep_pen",
	"well", "wind_pump",
	"garage", "trade_depot",
	"builder_house", "farm_house", "woodcutter_house", "ranch_house",
]

func _is_no_road_building(bd) -> bool:
	if bd == null: return false
	if bd.grow_time > 0.0: return true
	return bd.id in _NO_ROAD_CATEGORIES

func _on_state_changed(_new_state) -> void:
	if _game_manager == null or not _game_manager.is_placing():
		if _preview != null:
			_preview.queue_free()
			_preview = null
