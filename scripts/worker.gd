class_name Worker
extends Node3D

enum State { IDLE, WALKING_OUT, WORKING, WALKING_BACK }

const WALK_SPEED: float = 2.1
const WORK_BOB_SPEED: float = 5.0
const ROAD_SPEED_MULT: float = 2.0
const _GM_ROAD: int = 3   # = GridManager.Terrain.ROAD — avoids circular compile dep

const _ALL_MODELS: Array = [
	"res://assets/mini-characters/Models/GLB format/character-male-a.glb",
	"res://assets/mini-characters/Models/GLB format/character-male-b.glb",
	"res://assets/mini-characters/Models/GLB format/character-male-c.glb",
	"res://assets/mini-characters/Models/GLB format/character-male-d.glb",
	"res://assets/mini-characters/Models/GLB format/character-male-e.glb",
	"res://assets/mini-characters/Models/GLB format/character-male-f.glb",
	"res://assets/mini-characters/Models/GLB format/character-female-a.glb",
	"res://assets/mini-characters/Models/GLB format/character-female-b.glb",
	"res://assets/mini-characters/Models/GLB format/character-female-c.glb",
	"res://assets/mini-characters/Models/GLB format/character-female-d.glb",
	"res://assets/mini-characters/Models/GLB format/character-female-e.glb",
	"res://assets/mini-characters/Models/GLB format/character-female-f.glb",
]

# Display label for each worker state per job type
# job_id -> [idle, walking_out, working, walking_back]
func get_job_labels(job_id: String) -> Array:
	var lm = get_node_or_null("/root/LocaleManager")
	if lm != null:
		var states = lm.worker_states(job_id)
		if not states.is_empty():
			return states
	return ["💤", "🏃", "⚙️", "📦"]

# Color of resource being carried
const JOB_CARRY_COLOR: Dictionary = {
	"lumberyard": Color(0.45, 0.25, 0.05),
	"farm":       Color(0.85, 0.78, 0.10),
	"farm_house": Color(0.85, 0.78, 0.10),
	"mill":       Color(0.92, 0.88, 0.70),
	"bakery":     Color(0.88, 0.60, 0.25),
	"market":     Color(1.0, 0.82, 0.10),
	"well":       Color(0.18, 0.50, 0.80),
	"oil_pump":        Color(0.22, 0.14, 0.05),
	"sugarcane_field": Color(0.25, 0.75, 0.25),
	"cotton_field":    Color(0.95, 0.95, 0.88),
	"pumpkin_patch":   Color(0.92, 0.55, 0.08),
	"corn_field":      Color(0.98, 0.82, 0.10),
	"tomato_field":    Color(0.85, 0.15, 0.10),
	"tree_farm":       Color(0.45, 0.25, 0.05),
	"wind_pump":       Color(0.18, 0.50, 0.82),
	"water_facility":  Color(0.18, 0.50, 0.82),
	"sugar_mill":      Color(0.92, 0.82, 0.50),
	"animal_barn":     Color(0.95, 0.92, 0.82),
	"chicken_coop":    Color(0.95, 0.90, 0.70),
	"dairy":           Color(0.96, 0.88, 0.60),
	"power_plant":     Color(0.95, 0.90, 0.20),
	"factory":         Color(0.55, 0.55, 0.60),
	"refinery":        Color(0.18, 0.18, 0.22),
	"garage":          Color(1.0, 0.82, 0.10),
	"advanced_bakery": Color(0.88, 0.60, 0.25),
	"cake_bakery":     Color(0.92, 0.65, 0.45),
	"dairy_bakery":    Color(0.95, 0.88, 0.65),
	"pie_shop":        Color(0.88, 0.55, 0.18),
	"cookie_chain":    Color(0.82, 0.62, 0.35),
	"salt_field":      Color(0.92, 0.90, 0.85),
	"feed_mill":       Color(0.72, 0.58, 0.28),
	"sheep_pen":       Color(0.90, 0.88, 0.85),
}

signal one_shot_done
signal arrived_home

var one_shot: bool = false
var paused: bool = false

var _state: int = State.IDLE
var _home: Vector3 = Vector3.ZERO
var _work_target: Vector3 = Vector3.ZERO
var _bob_t: float = 0.0
var _idle_timer: float = 0.0
var _work_timer: float = 0.0
var _work_total: float = 1.0
var production_time: float = 5.0
var job_id: String = ""

var _waypoints: Array = []
var _wp_idx: int = 0
var _cycle_callback: Callable

# A* navigation path (world positions of intermediate cells to walk through)
var _nav_path: Array = []
var _nav_idx: int = 0
var _nav_computed: bool = false

func set_waypoints(wps: Array) -> void:
	_waypoints = wps.duplicate()
	_wp_idx = 0

func redirect(wps: Array) -> void:
	_waypoints = wps.duplicate()
	_wp_idx = 0
	_nav_path = []
	_nav_idx = 0
	_nav_computed = false
	_state = State.WALKING_OUT
	_update_label()

func _reset_nav() -> void:
	_nav_path = []
	_nav_idx = 0
	_nav_computed = false

func _compute_nav_path(from: Vector3, to: Vector3) -> void:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null:
		return
	var fc: Vector2i = gm.world_to_cell(from)
	var tc: Vector2i = gm.world_to_cell(to)
	if fc == tc:
		return
	var cells: Array = AStarGrid.find_path(fc, tc, gm)
	# Skip first cell (current position); last cell handled by direct movement
	_nav_path = []
	for i in range(1, cells.size() - 1):
		var w: Vector3 = gm.cell_to_world(cells[i])
		w.x += GridManager.CELL_SIZE * 0.5
		w.z += GridManager.CELL_SIZE * 0.5
		_nav_path.append(w)
	_nav_idx = 0

func set_cycle_callback(cb: Callable) -> void:
	_cycle_callback = cb

var _status_label: Label3D
var _carry_mesh: MeshInstance3D
var _bar_bg: MeshInstance3D
var _bar_fill: MeshInstance3D
var _bar_fill_mat: StandardMaterial3D

const BAR_WIDTH: float = 0.55
const BAR_HEIGHT: float = 0.07
const BAR_Y: float = 2.0

func setup(home_pos: Vector3, work_pos: Vector3, prod_time: float, job: String = "", fixed_model: String = "") -> void:
	_home = home_pos
	_work_target = work_pos
	production_time = prod_time
	job_id = job
	position = _home
	_idle_timer = randf_range(0.2, 2.5)
	_load_model(fixed_model)
	_create_status_label()
	_create_carry_mesh()
	_create_progress_bar()
	_update_label()

func update_work_target(pos: Vector3) -> void:
	_work_target = pos

func _load_model(override: String = "") -> void:
	var path: String = override if override != "" else _ALL_MODELS[randi() % _ALL_MODELS.size()]
	if not ResourceLoader.exists(path):
		_make_fallback_body()
		return
	var scene := load(path) as PackedScene
	if scene == null:
		_make_fallback_body()
		return
	var inst = scene.instantiate()
	inst.scale = Vector3.ONE * 0.77
	inst.rotation_degrees.y = 180.0
	add_child(inst)

func _make_fallback_body() -> void:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.22
	cap.height = 0.8
	mi.mesh = cap
	mi.position = Vector3(0, 0.4, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.75, 0.55)
	mi.material_override = mat
	add_child(mi)

func _create_status_label() -> void:
	_status_label = Label3D.new()
	_status_label.font_size = 36
	_status_label.position = Vector3(0, 1.8, 0)
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.modulate = Color.WHITE
	_status_label.outline_modulate = Color.BLACK
	_status_label.outline_size = 10
	_status_label.no_depth_test = true
	add_child(_status_label)

func _create_carry_mesh() -> void:
	_carry_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.28, 0.20, 0.20)
	_carry_mesh.mesh = box
	_carry_mesh.position = Vector3(0.2, 1.1, 0)
	var mat := StandardMaterial3D.new()
	var col: Color = JOB_CARRY_COLOR.get(job_id, Color(0.6, 0.6, 0.6))
	mat.albedo_color = col
	_carry_mesh.material_override = mat
	_carry_mesh.visible = false
	add_child(_carry_mesh)

func _create_progress_bar() -> void:
	# Background track (dark grey)
	_bar_bg = MeshInstance3D.new()
	var bg_box := BoxMesh.new()
	bg_box.size = Vector3(BAR_WIDTH, BAR_HEIGHT, 0.01)
	_bar_bg.mesh = bg_box
	_bar_bg.position = Vector3(0, BAR_Y, 0)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.15, 0.15, 0.15)
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_bar_bg.material_override = bg_mat
	_bar_bg.visible = false
	add_child(_bar_bg)
	# Fill bar
	_bar_fill = MeshInstance3D.new()
	var fill_box := BoxMesh.new()
	fill_box.size = Vector3(BAR_WIDTH, BAR_HEIGHT, 0.02)
	_bar_fill.mesh = fill_box
	_bar_fill.position = Vector3(-BAR_WIDTH * 0.5, BAR_Y, 0)
	_bar_fill_mat = StandardMaterial3D.new()
	_bar_fill_mat.albedo_color = Color(0.1, 0.85, 0.2)
	_bar_fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_bar_fill.material_override = _bar_fill_mat
	_bar_fill.visible = false
	add_child(_bar_fill)

func _update_progress_bar(fill: float) -> void:
	if _bar_bg == null:
		return
	if fill <= 0.0:
		_bar_bg.visible = false
		_bar_fill.visible = false
		return
	_bar_bg.visible = true
	_bar_fill.visible = true
	var w: float = BAR_WIDTH * clampf(fill, 0.0, 1.0)
	var mesh = _bar_fill.mesh as BoxMesh
	if mesh != null:
		mesh.size = Vector3(w, BAR_HEIGHT, 0.05)
	_bar_fill.position = Vector3(-BAR_WIDTH * 0.5 + w * 0.5, BAR_Y, 0)
	# Colour: green → yellow → red as time runs out
	if fill > 0.5:
		_bar_fill_mat.albedo_color = Color(0.1, 0.85, 0.2)
	elif fill > 0.25:
		_bar_fill_mat.albedo_color = Color(0.95, 0.75, 0.1)
	else:
		_bar_fill_mat.albedo_color = Color(0.9, 0.15, 0.1)

func get_activity_text() -> String:
	if _status_label != null and is_instance_valid(_status_label):
		return _status_label.text
	var labels: Array = get_job_labels(job_id)
	return labels[_state] if _state < labels.size() else ""

func _update_label() -> void:
	if _status_label == null:
		return
	var labels: Array = get_job_labels(job_id)
	match _state:
		State.IDLE:
			_status_label.text = labels[0]
			_status_label.modulate = Color(0.7, 0.7, 0.7, 0.7)
		State.WALKING_OUT:
			_status_label.text = labels[1]
			_status_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
		State.WORKING:
			_status_label.text = labels[2]
			_status_label.modulate = Color(0.4, 1.0, 0.5, 1.0)
		State.WALKING_BACK:
			_status_label.text = labels[3]
			_status_label.modulate = Color(0.8, 0.8, 0.8, 0.85)

func _process(delta: float) -> void:
	match _state:
		State.IDLE:
			_idle_timer -= delta
			if _idle_timer > 0.0:
				return
			# Always try callback first — if new work is available, start immediately without waiting
			if _cycle_callback.is_valid():
				var new_wps: Array = _cycle_callback.call()
				if new_wps.size() > 0:
					_waypoints = new_wps
					_wp_idx = 0
					paused = false
					_reset_nav()
					_state = State.WALKING_OUT
					_bob_t = 0.0
					_carry_mesh.visible = false
					_update_label()
					return
			if paused:
				_idle_timer = randf_range(1.0, 2.0)
				return
			_reset_nav()
			_state = State.WALKING_OUT
			_bob_t = 0.0
			_carry_mesh.visible = false
			_update_label()

		State.WALKING_OUT:
			var target: Vector3 = _work_target
			if _waypoints.size() > 0 and _wp_idx < _waypoints.size():
				target = _waypoints[_wp_idx].get("pos", _work_target)
			# Lazily compute A* path for this movement leg
			if not _nav_computed:
				_nav_computed = true
				_compute_nav_path(position, target)
			# Advance past intermediate waypoints when close — no snap, just glide through
			while _nav_idx < _nav_path.size():
				var wp := _nav_path[_nav_idx]
				if Vector2(position.x - wp.x, position.z - wp.z).length() < 0.35:
					_nav_idx += 1
				else:
					break
			if _nav_idx < _nav_path.size():
				_move_toward(_nav_path[_nav_idx], delta)
				return
			# Nav complete — do final approach to exact target
			if _move_toward(target, delta):
				position = Vector3(target.x, 0.0, target.z)
				_reset_nav()
				if _waypoints.size() > 0 and _wp_idx < _waypoints.size():
					var wp: Dictionary = _waypoints[_wp_idx]
					if wp.has("on_arrive"):
						wp["on_arrive"].call()
					_work_timer = wp.get("pause", 1.5)
				else:
					_work_timer = production_time
				_work_total = maxf(_work_timer, 0.001)
				_state = State.WORKING
				_bob_t = 0.0
				_update_label()

		State.WORKING:
			_bob_t += delta * WORK_BOB_SPEED
			position.y = abs(sin(_bob_t)) * 0.18
			_work_timer -= delta
			_update_progress_bar(1.0 - (_work_timer / _work_total))
			if _work_timer <= 0.0:
				position.y = 0.0
				_bob_t = 0.0
				_update_progress_bar(0.0)
				if _waypoints.size() > 0:
					_wp_idx += 1
					if _wp_idx < _waypoints.size():
						_reset_nav()
						_state = State.WALKING_OUT
						_update_label()
					else:
						_wp_idx = 0
						_waypoints = []
						if _cycle_callback.is_valid():
							var new_wps: Array = _cycle_callback.call()
							if new_wps.size() > 0:
								_waypoints = new_wps
								_reset_nav()
								_state = State.WALKING_OUT
								_update_label()
								return
						_reset_nav()
						_state = State.WALKING_BACK
						_update_label()
					return
				_reset_nav()
				_state = State.WALKING_BACK
				_update_label()

		State.WALKING_BACK:
			if not _nav_computed:
				_nav_computed = true
				_compute_nav_path(position, _home)
			while _nav_idx < _nav_path.size():
				var wp := _nav_path[_nav_idx]
				if Vector2(position.x - wp.x, position.z - wp.z).length() < 0.35:
					_nav_idx += 1
				else:
					break
			if _nav_idx < _nav_path.size():
				_move_toward(_nav_path[_nav_idx], delta)
				return
			if _move_toward(_home, delta):
				_reset_nav()
				position = Vector3(_home.x, 0.0, _home.z)
				_carry_mesh.visible = false
				if one_shot:
					one_shot_done.emit()
					queue_free()
					return
				arrived_home.emit()
				_state = State.IDLE
				_idle_timer = randf_range(0.5, 1.5)
				_update_label()

func go_home() -> void:
	_waypoints = []
	_wp_idx = 0
	_reset_nav()
	_state = State.WALKING_BACK
	_update_label()

func set_carrying(visible: bool) -> void:
	if _carry_mesh != null:
		_carry_mesh.visible = visible

func _get_walk_speed() -> float:
	var gm = get_tree().get_first_node_in_group("grid_manager")
	if gm == null:
		return WALK_SPEED
	var cell: Vector2i = gm.world_to_cell(position)
	if gm.get_terrain(cell) == _GM_ROAD:
		return WALK_SPEED * ROAD_SPEED_MULT
	return WALK_SPEED

func _move_toward(target: Vector3, delta: float) -> bool:
	var flat_pos := Vector3(position.x, 0.0, position.z)
	var flat_tgt := Vector3(target.x, 0.0, target.z)
	var dir := flat_tgt - flat_pos
	var dist := dir.length()
	if dist < 0.05:
		return true

	var speed: float = _get_walk_speed()
	var step := minf(dist, speed * delta)
	flat_pos += dir.normalized() * step
	_bob_t += delta * 8.0
	position = Vector3(flat_pos.x, abs(sin(_bob_t)) * 0.05, flat_pos.z)

	# Smooth rotation — หัวค่อยๆ หันตามทิศทาง ไม่กระตุก
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 12.0)
	return false
