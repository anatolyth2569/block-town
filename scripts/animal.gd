class_name Animal
extends Node3D

var _target_pos: Vector3
var _speed: float = 0.45
var _pen_radius: float = 0.65
var _wander_timer: float = 0.0
var _spawn_center: Vector3 = Vector3.ZERO

func setup(animal_type: String, spawn_offset: Vector3 = Vector3.ZERO) -> void:
	position = spawn_offset
	_spawn_center = spawn_offset
	_target_pos = spawn_offset
	_wander_timer = randf_range(0.5, 3.0)
	match animal_type:
		"cow":     _speed = 0.40; _pen_radius = 0.55; _build_cow()
		"chicken": _speed = 0.70; _pen_radius = 0.40; _build_chicken()
		"sheep":   _speed = 0.38; _pen_radius = 0.50; _build_sheep()
		"pig":     _speed = 0.48; _pen_radius = 0.50; _build_pig()

func _process(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_new_target()

	var diff := _target_pos - position
	diff.y = 0.0
	if diff.length() > 0.05:
		var dir := diff.normalized()
		position += dir * _speed * delta
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 5.0)

func _pick_new_target() -> void:
	_wander_timer = randf_range(2.5, 6.0)
	var angle := randf() * TAU
	var dist  := randf_range(0.05, _pen_radius)
	_target_pos = _spawn_center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

func _box(sz: Vector3, pos: Vector3, col: Color) -> void:
	var mi  := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = sz
	mi.mesh = box
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.90
	mi.material_override = mat
	add_child(mi)

# ── วัว ──────────────────────────────────────────────────────────────────────
func _build_cow() -> void:
	var packed := load("res://scenes/animals/cow.tscn") as PackedScene
	if packed:
		add_child(packed.instantiate())
		return
	var body := Color(0.88, 0.84, 0.78)
	var head := Color(0.58, 0.42, 0.28)
	var leg  := Color(0.62, 0.46, 0.30)
	_box(Vector3(0.42, 0.28, 0.26), Vector3(0, 0.20, 0), body)
	_box(Vector3(0.18, 0.18, 0.16), Vector3(0, 0.38, 0.20), head)
	_box(Vector3(0.07, 0.15, 0.07), Vector3(-0.14, 0.055, -0.07), leg)
	_box(Vector3(0.07, 0.15, 0.07), Vector3( 0.14, 0.055, -0.07), leg)
	_box(Vector3(0.07, 0.15, 0.07), Vector3(-0.14, 0.055,  0.07), leg)
	_box(Vector3(0.07, 0.15, 0.07), Vector3( 0.14, 0.055,  0.07), leg)

# ── ไก่ ──────────────────────────────────────────────────────────────────────
func _build_chicken() -> void:
	var is_chick := randf() < 0.35
	var path := "res://scenes/animals/chicken_chick.tscn" if is_chick \
	         else "res://scenes/animals/chicken_adult.tscn"
	var packed := load(path) as PackedScene
	if packed:
		add_child(packed.instantiate())
		if is_chick:
			_speed = 1.0
			_pen_radius = 0.45
		return
	# fallback หาก scene หายไป
	var body := Color(0.92, 0.80, 0.22)
	var head := Color(0.90, 0.74, 0.18)
	var beak := Color(1.00, 0.60, 0.10)
	var leg  := Color(0.95, 0.68, 0.18)
	_box(Vector3(0.14, 0.12, 0.12), Vector3(0, 0.09, 0), body)
	_box(Vector3(0.09, 0.09, 0.08), Vector3(0, 0.19, 0.08), head)
	_box(Vector3(0.04, 0.03, 0.04), Vector3(0, 0.17, 0.15), beak)
	_box(Vector3(0.03, 0.08, 0.03), Vector3(-0.05, 0.01, 0), leg)
	_box(Vector3(0.03, 0.08, 0.03), Vector3( 0.05, 0.01, 0), leg)

# ── แกะ ──────────────────────────────────────────────────────────────────────
func _build_sheep() -> void:
	var packed := load("res://scenes/animals/sheep.tscn") as PackedScene
	if packed:
		add_child(packed.instantiate())
		return
	var wool := Color(0.92, 0.90, 0.86)
	var face := Color(0.52, 0.48, 0.44)
	var leg  := Color(0.50, 0.46, 0.44)
	_box(Vector3(0.38, 0.30, 0.28), Vector3(0, 0.20, 0), wool)
	_box(Vector3(0.15, 0.15, 0.13), Vector3(0, 0.40, 0.20), face)
	_box(Vector3(0.05, 0.10, 0.04), Vector3(-0.09, 0.46, 0.14), face)
	_box(Vector3(0.05, 0.10, 0.04), Vector3( 0.09, 0.46, 0.14), face)
	_box(Vector3(0.06, 0.13, 0.06), Vector3(-0.12, 0.055, -0.08), leg)
	_box(Vector3(0.06, 0.13, 0.06), Vector3( 0.12, 0.055, -0.08), leg)
	_box(Vector3(0.06, 0.13, 0.06), Vector3(-0.12, 0.055,  0.08), leg)
	_box(Vector3(0.06, 0.13, 0.06), Vector3( 0.12, 0.055,  0.08), leg)

# ── หมู ──────────────────────────────────────────────────────────────────────
func _build_pig() -> void:
	var packed := load("res://scenes/animals/pig.tscn") as PackedScene
	if packed:
		add_child(packed.instantiate())
		return
	var body  := Color(0.95, 0.68, 0.68)
	var snout := Color(0.90, 0.58, 0.60)
	var ear   := Color(0.88, 0.58, 0.64)
	var leg   := Color(0.90, 0.64, 0.64)
	_box(Vector3(0.38, 0.26, 0.28), Vector3(0, 0.18, 0), body)
	_box(Vector3(0.20, 0.18, 0.16), Vector3(0, 0.32, 0.20), snout)
	_box(Vector3(0.10, 0.08, 0.06), Vector3(0, 0.29, 0.32), snout)
	_box(Vector3(0.08, 0.09, 0.04), Vector3(-0.09, 0.42, 0.14), ear)
	_box(Vector3(0.08, 0.09, 0.04), Vector3( 0.09, 0.42, 0.14), ear)
	_box(Vector3(0.07, 0.13, 0.07), Vector3(-0.12, 0.055, -0.08), leg)
	_box(Vector3(0.07, 0.13, 0.07), Vector3( 0.12, 0.055, -0.08), leg)
	_box(Vector3(0.07, 0.13, 0.07), Vector3(-0.12, 0.055,  0.08), leg)
	_box(Vector3(0.07, 0.13, 0.07), Vector3( 0.12, 0.055,  0.08), leg)
