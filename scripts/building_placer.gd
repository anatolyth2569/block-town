extends Node3D

signal touch_cell_locked(is_valid: bool)
signal touch_cell_unlocked()

var _game_manager: Node
var _grid_manager: GridManager
var _resource_manager: Node

var _preview: Node3D = null
var _current_cell: Vector2i = Vector2i(-999, -999)
var _is_valid: bool = false
var _rotation: int = 0  # 0/1/2/3 = 0°/90°/180°/270°
var _manual_rotation: bool = false  # true when player pressed R to override auto-facing

var _mat_valid: StandardMaterial3D
var _mat_invalid: StandardMaterial3D
var _mat_highlight: StandardMaterial3D

var _selection_highlight: Node3D = null
var _highlight_tween: Tween = null

var _left_press_pos: Vector2 = Vector2(-9999, -9999)
const CLICK_THRESHOLD: float = 6.0

# Mobile touch placement
var _touch_locked: bool = false       # preview is locked at a tapped cell
var _touch_press_pos: Vector2 = Vector2(-9999, -9999)
var _has_active_touch: bool = false   # finger is currently down
const TOUCH_TAP_THRESHOLD: float = 14.0

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

	_mat_highlight = StandardMaterial3D.new()
	_mat_highlight.albedo_color = Color(1.0, 0.85, 0.1, 0.38)
	_mat_highlight.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_highlight.emission_enabled = true
	_mat_highlight.emission = Color(1.0, 0.78, 0.0)
	_mat_highlight.emission_energy_multiplier = 2.0

	print("[BuildingPlacer] ready")

func _process(_delta: float) -> void:
	if _game_manager == null or not _game_manager.is_placing():
		return
	if _grid_manager == null:
		_grid_manager = get_tree().get_first_node_in_group("grid_manager") as GridManager
		if _grid_manager == null:
			return
	_update_preview()

func _get_rotated_size(data: BuildingData) -> Vector2i:
	if _rotation % 2 == 1:
		return Vector2i(data.size.y, data.size.x)
	return data.size

func _touch_lock_cell(screen_pos: Vector2) -> void:
	if _grid_manager == null:
		_grid_manager = get_tree().get_first_node_in_group("grid_manager") as GridManager
	if _grid_manager == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var ro := cam.project_ray_origin(screen_pos)
	var rd := cam.project_ray_normal(screen_pos)
	if absf(rd.y) < 0.001:
		return
	var t_dist := -ro.y / rd.y
	var hit := ro + rd * t_dist
	var cell := _grid_manager.world_to_cell(hit)

	var data = _game_manager.selected_building_data
	if data == null:
		return

	_current_cell = cell
	_touch_locked = true

	if _preview != null:
		_preview.queue_free()
		_preview = null

	var rsz := _get_rotated_size(data)
	_is_valid = _grid_manager.is_area_free(cell, rsz)
	if _is_valid and not _is_no_road_building(data):
		_is_valid = _grid_manager.is_area_adjacent_to_road(cell, rsz)

	_preview = _build_preview_mesh(data)
	add_child(_preview)
	var wp := _grid_manager.cell_to_world(cell)
	wp.x += rsz.x * GridManager.CELL_SIZE * 0.5
	wp.z += rsz.y * GridManager.CELL_SIZE * 0.5
	_preview.position = wp
	_preview.rotation_degrees.y = _rotation * 90.0
	var mat := _mat_valid if _is_valid else _mat_invalid
	for child in _preview.get_children():
		if child is MeshInstance3D:
			child.material_override = mat

	touch_cell_locked.emit(_is_valid)

func confirm_place() -> void:
	if _is_valid:
		_do_place()
	_touch_locked = false
	_current_cell = Vector2i(-999, -999)
	touch_cell_unlocked.emit()

func _unhandled_input(event: InputEvent) -> void:
	if _game_manager == null:
		return

	# --- Touch: separate from mouse to prevent double-input on mobile ---
	if event is InputEventScreenTouch:
		if event.pressed:
			_has_active_touch = true
			_touch_press_pos = event.position
		else:
			_has_active_touch = false
			if _game_manager.is_placing() and \
			   event.position.distance_to(_touch_press_pos) < TOUCH_TAP_THRESHOLD:
				_touch_lock_cell(event.position)
			_touch_press_pos = Vector2(-9999, -9999)
		return

	# Skip mouse events while a finger is down (prevents emulated-mouse double-placement)
	if _has_active_touch:
		return

	# Press R to rotate building 90° while placing
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).keycode == KEY_R and _game_manager.is_placing():
			_manual_rotation = true
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
					hide_selection()
					var bld: Node = _grid_manager._buildings[cell]
					_game_manager.show_building_info(bld)
				elif _grid_manager.get_terrain(cell) == GridManager.Terrain.WATER:
					hide_selection()
					var pond_origin := _grid_manager.get_pond_at(cell)
					if pond_origin != Vector2i(-1, -1):
						_game_manager.pond_cell_clicked.emit(cell)
				elif _grid_manager.is_cell_valid(cell):
					var terrain := _grid_manager.get_terrain(cell)
					if terrain == GridManager.Terrain.FOREST:
						hide_selection()
						_game_manager.forest_cell_clicked.emit(cell)
					elif _grid_manager.is_road_terrain(terrain):
						show_selection_highlight(cell)
						_game_manager.road_cell_clicked.emit(cell)
					else:
						show_selection_highlight(cell)
						_game_manager.grass_cell_clicked.emit(cell)
				get_viewport().set_input_as_handled()
		_left_press_pos = Vector2(-9999, -9999)
		return
	if _game_manager.is_placing():
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _is_valid:
				_do_place()
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
	elif _game_manager.is_placing_pond():
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_try_place_pond()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_game_manager.cancel_placement()

func _update_preview() -> void:
	if _touch_locked:
		return  # Preview is locked at the touch-selected cell; don't follow mouse
	var data = _game_manager.selected_building_data
	if data == null:
		return

	var cell := _get_hovered_cell()

	# Hide preview when mouse is outside the valid grid area
	if _grid_manager == null or not _grid_manager.is_cell_valid(cell):
		if _preview != null:
			_preview.visible = false
		_is_valid = false
		return
	if _preview != null:
		_preview.visible = true

	# Auto-rotate door toward nearest road; reset override when moving to new cell
	if cell != _current_cell:
		_manual_rotation = false
	if not _manual_rotation and not _is_no_road_building(data) and _grid_manager != null:
		var best := _best_road_facing(cell, data)
		if best != _rotation:
			_rotation = best
			if _preview != null:
				_preview.queue_free()
				_preview = null

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

func _do_place() -> void:
	var data = _game_manager.selected_building_data
	if data == null or _grid_manager == null:
		return
	var rsz := _get_rotated_size(data)
	if not _grid_manager.is_area_free(_current_cell, rsz):
		return
	if not _is_no_road_building(data) and not _grid_manager.is_area_adjacent_to_road(_current_cell, rsz):
		return
	var gold_cost: int = data.build_cost.get("Gold", 0)
	if gold_cost > 0 and not _resource_manager.pay({"Gold": gold_cost}):
		return
	var building := Building.new()
	building.data = data
	building.origin_cell = _current_cell
	building.facing = _rotation
	building.rotation_degrees.y = _rotation * 90.0
	_grid_manager.place_building(building, data, _current_cell, rsz)
	# Stay in placement mode so player can keep placing
	if _preview != null:
		_preview.queue_free()
		_preview = null
	_current_cell = Vector2i(-999, -999)

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

func _try_place_pond() -> void:
	if _grid_manager == null:
		_grid_manager = get_tree().get_first_node_in_group("grid_manager") as GridManager
		if _grid_manager == null:
			return
	var cell := _get_hovered_cell()
	_grid_manager.build_pond(cell, _game_manager.pond_is_big)
	# Stay in pond-placing mode so player can keep placing

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
	"animal_barn", "chicken_coop", "sheep_pen", "pig_pen",
	"well", "small_pond", "large_pond", "wind_pump",
	"garage",
	"builder_house", "farm_house", "woodcutter_house", "ranch_house",
]

func _is_no_road_building(bd) -> bool:
	if bd == null: return false
	if bd.grow_time > 0.0: return true
	return bd.id in _NO_ROAD_CATEGORIES

func _best_road_facing(origin: Vector2i, data: BuildingData) -> int:
	var sz := data.size
	var scores := [0, 0, 0, 0]
	# facing 0: south edge (+z), 1: west (-x), 2: north (-z), 3: east (+x)
	for dx in range(sz.x):
		if _grid_manager.is_road_terrain(_grid_manager.get_terrain(origin + Vector2i(dx, sz.y))):
			scores[0] += 1
	for dz in range(sz.y):
		if _grid_manager.is_road_terrain(_grid_manager.get_terrain(origin + Vector2i(-1, dz))):
			scores[1] += 1
	for dx in range(sz.x):
		if _grid_manager.is_road_terrain(_grid_manager.get_terrain(origin + Vector2i(dx, -1))):
			scores[2] += 1
	for dz in range(sz.y):
		if _grid_manager.is_road_terrain(_grid_manager.get_terrain(origin + Vector2i(sz.x, dz))):
			scores[3] += 1
	var best_f := _rotation
	var best_s := 0
	for f in range(4):
		if scores[f] > best_s:
			best_s = scores[f]
			best_f = f
	return best_f

func show_selection_highlight(cell: Vector2i) -> void:
	if _grid_manager == null:
		_grid_manager = get_tree().get_first_node_in_group("grid_manager") as GridManager
	if _grid_manager == null:
		return
	if _selection_highlight == null:
		_selection_highlight = Node3D.new()
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(GridManager.CELL_SIZE * 0.90, 0.10, GridManager.CELL_SIZE * 0.90)
		mi.mesh = box
		mi.material_override = _mat_highlight
		_selection_highlight.add_child(mi)
		add_child(_selection_highlight)
	var wp := _grid_manager.cell_to_world(cell)
	_selection_highlight.position = Vector3(
		wp.x + GridManager.CELL_SIZE * 0.5, 0.05, wp.z + GridManager.CELL_SIZE * 0.5
	)
	_selection_highlight.scale = Vector3.ONE
	_selection_highlight.visible = true
	if _highlight_tween != null:
		_highlight_tween.kill()
	_highlight_tween = create_tween()
	_highlight_tween.set_loops()
	_highlight_tween.tween_property(_selection_highlight, "scale", Vector3(1.06, 1.0, 1.06), 0.65).set_ease(Tween.EASE_IN_OUT)
	_highlight_tween.tween_property(_selection_highlight, "scale", Vector3(0.94, 1.0, 0.94), 0.65).set_ease(Tween.EASE_IN_OUT)

func hide_selection() -> void:
	if _selection_highlight != null and is_instance_valid(_selection_highlight):
		_selection_highlight.visible = false
	if _highlight_tween != null:
		_highlight_tween.kill()
		_highlight_tween = null

func _on_state_changed(_new_state) -> void:
	_manual_rotation = false
	_touch_locked = false
	_has_active_touch = false
	touch_cell_unlocked.emit()
	hide_selection()
	if _game_manager == null or not _game_manager.is_placing():
		if _preview != null:
			_preview.queue_free()
			_preview = null
