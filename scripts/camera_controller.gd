class_name CameraController
extends Camera3D

const PAN_SPEED: float = 22.0
const ZOOM_STEP: float = 3.5
const DIST_MIN: float = 12.0
const DIST_MAX: float = 95.0
const ROTATE_STEP: float = 90.0

const PITCH_MIN: float = 15.0
const PITCH_MAX: float = 75.0

# Map bounds: grid is 20×20 cells × 3.0 units = 0–60 on X/Z. Allow small margin outside.
const TARGET_MIN: float = -10.0
const TARGET_MAX: float = 70.0

var _target: Vector3 = Vector3(30, 0, 30)
var _yaw: float = 225.0    # left-right rotation (degrees)
var _pitch: float = 42.0   # tilt angle (degrees, higher = more top-down view)
var _dist: float = 50.0    # distance from target

var _right_drag: bool = false
var _mid_drag: bool = false
var _left_drag: bool = false

# Touch tracking: finger index -> current screen position
var _touches: Dictionary = {}

func _ready() -> void:
	current = true
	projection = Camera3D.PROJECTION_PERSPECTIVE
	fov = 55.0
	_apply_position()

func _clamp_target() -> void:
	_target.x = clampf(_target.x, TARGET_MIN, TARGET_MAX)
	_target.z = clampf(_target.z, TARGET_MIN, TARGET_MAX)

func _apply_position() -> void:
	var yaw_rad := deg_to_rad(_yaw)
	var pitch_rad := deg_to_rad(_pitch)
	position = _target + Vector3(
		cos(pitch_rad) * sin(yaw_rad) * _dist,
		sin(pitch_rad) * _dist,
		cos(pitch_rad) * cos(yaw_rad) * _dist
	)
	look_at(_target, Vector3.UP)

func _process(delta: float) -> void:
	# Sync drag flags from actual button state — prevents stuck state when UI consumes release event
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT): _right_drag = false
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): _left_drag = false
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE): _mid_drag = false

	var right := -transform.basis.x
	var forward := Vector3(transform.basis.z.x, 0, transform.basis.z.z).normalized()
	var moved := false

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		_target -= forward * PAN_SPEED * delta
		moved = true
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		_target += forward * PAN_SPEED * delta
		moved = true
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		_target += right * PAN_SPEED * delta
		moved = true
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		_target -= right * PAN_SPEED * delta
		moved = true
	if moved:
		_clamp_target()
		_apply_position()

func _unhandled_input(event: InputEvent) -> void:
	# --- Keyboard ---
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_Q:
			_yaw -= ROTATE_STEP
			_apply_position()
		elif key.keycode == KEY_E:
			_yaw += ROTATE_STEP
			_apply_position()

	# --- Touch (mobile) ---
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		return

	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		_handle_touch_drag(event)
		return

	# Skip mouse events while touch is active (avoid double-panning from emulated mouse)
	if _touches.size() > 0:
		return

	# --- Mouse ---
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if get_viewport().gui_get_hovered_control() != null:
					return
				_dist = maxf(DIST_MIN, _dist - ZOOM_STEP)
				_apply_position()
			MOUSE_BUTTON_WHEEL_DOWN:
				if get_viewport().gui_get_hovered_control() != null:
					return
				_dist = minf(DIST_MAX, _dist + ZOOM_STEP)
				_apply_position()
			MOUSE_BUTTON_LEFT:
				_left_drag = mb.pressed
			MOUSE_BUTTON_RIGHT:
				_right_drag = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_mid_drag = mb.pressed

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _left_drag and not _right_drag:
			# Left hold drag = pan to move view
			var right_pan := -transform.basis.x
			var forward_pan := Vector3(transform.basis.z.x, 0, transform.basis.z.z).normalized()
			var scale: float = _dist * 0.0012
			_target += right_pan * mm.relative.x * scale
			_target += forward_pan * mm.relative.y * scale * -1.0
			_clamp_target()
			_apply_position()
		if _right_drag:
			# drag left-right = rotate around yaw
			_yaw -= mm.relative.x * 0.4
			# drag up-down = adjust pitch
			_pitch += mm.relative.y * 0.3
			_pitch = clampf(_pitch, PITCH_MIN, PITCH_MAX)
			_apply_position()
		elif _mid_drag:
			# Middle click = pan
			var right := -transform.basis.x
			var forward := Vector3(transform.basis.z.x, 0, transform.basis.z.z).normalized()
			var scale: float = _dist * 0.0012
			_target += right * mm.relative.x * scale
			_target += forward * mm.relative.y * scale * -1.0
			_clamp_target()
			_apply_position()

func _handle_touch_drag(event: InputEventScreenDrag) -> void:
	var delta := event.relative

	if _touches.size() == 1:
		# Single finger → pan
		var right_pan := -transform.basis.x
		var forward_pan := Vector3(transform.basis.z.x, 0, transform.basis.z.z).normalized()
		var scale: float = _dist * 0.0012
		_target += right_pan * delta.x * scale
		_target += forward_pan * delta.y * scale * -1.0
		_clamp_target()
		_apply_position()

	elif _touches.size() == 2:
		# Two fingers → pinch to zoom + drag midpoint to orbit
		var keys := _touches.keys()
		var pos_a: Vector2 = _touches[keys[0]]
		var pos_b: Vector2 = _touches[keys[1]]

		# Reconstruct previous position of the moving finger
		var prev_this := event.position - delta
		var other_key: int = keys[0] if event.index == keys[1] else keys[1]
		var pos_other: Vector2 = _touches[other_key]

		var prev_a: Vector2
		var prev_b: Vector2
		if event.index == keys[0]:
			prev_a = prev_this
			prev_b = pos_other
		else:
			prev_a = pos_other
			prev_b = prev_this

		# Pinch zoom
		var old_span := prev_a.distance_to(prev_b)
		var new_span := pos_a.distance_to(pos_b)
		if old_span > 1.0 and new_span > 1.0:
			_dist = clampf(_dist * (old_span / new_span), DIST_MIN, DIST_MAX)

		# Orbit via midpoint movement
		var old_mid := (prev_a + prev_b) * 0.5
		var new_mid := (pos_a + pos_b) * 0.5
		var mid_delta := new_mid - old_mid
		_yaw -= mid_delta.x * 0.4
		_pitch = clampf(_pitch + mid_delta.y * 0.3, PITCH_MIN, PITCH_MAX)

		_apply_position()
