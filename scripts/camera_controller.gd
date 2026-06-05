class_name CameraController
extends Camera3D

const PAN_SPEED: float = 22.0
const ZOOM_STEP: float = 3.5
const DIST_MIN: float = 6.0
const DIST_MAX: float = 95.0
const ROTATE_STEP: float = 90.0

const PITCH_MIN: float = 5.0
const PITCH_MAX: float = 85.0

const TARGET_MIN: float = -10.0
const TARGET_MAX: float = 70.0

var _target: Vector3 = Vector3(30, 0, 30)
var _yaw: float = 225.0
var _pitch: float = 42.0
var _dist: float = 35.0
var _target_dist: float = 35.0

var _right_drag: bool = false
var _mid_drag: bool = false
var _left_drag: bool = false

# Touch state machine (Hay Day / Clash of Clans pattern)
# 1 finger = pan only; 2 fingers = pinch-zoom + centroid-pan; strict state gate
var _touches: Dictionary = {}
var _pan_finger: int = -1        # finger index assigned to pan; -1 = none
var _pinch_active: bool = false  # true only while 2 fingers are on screen
var _prev_pinch_dist: float = 0.0
var _prev_pinch_mid: Vector2 = Vector2.ZERO

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
	# Sync drag flags from actual button state
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT): _right_drag = false
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): _left_drag = false
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE): _mid_drag = false

	# Smooth zoom lerp (speed 12 per research: 8–12 range)
	if not is_equal_approx(_dist, _target_dist):
		var prev_dist := _dist
		_dist = lerpf(_dist, _target_dist, minf(delta * 12.0, 1.0))
		if absf(_dist - _target_dist) < 0.05:
			_dist = _target_dist
		if not is_equal_approx(_dist, prev_dist):
			_apply_position()

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
	# --- Keyboard (rotation — desktop only, no mobile rotation per industry standard) ---
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_Q:
			_yaw -= ROTATE_STEP
			_apply_position()
		elif key.keycode == KEY_E:
			_yaw += ROTATE_STEP
			_apply_position()

	# --- Touch state machine ---
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 1:
				# Fresh first finger — assign as pan finger
				_pan_finger = event.index
			elif _touches.size() == 2:
				# Second finger lands — cancel pan, enter pinch mode
				_pan_finger = -1
				_pinch_active = true
				var keys := _touches.keys()
				_prev_pinch_dist = _touches[keys[0]].distance_to(_touches[keys[1]])
				_prev_pinch_mid = (_touches[keys[0]] + _touches[keys[1]]) * 0.5
		else:
			_touches.erase(event.index)
			if _touches.size() < 2:
				# Any finger leaves pinch → cancel pinch; remaining finger is dead until lifted
				_pinch_active = false
			if _touches.size() == 0:
				# All fingers lifted → full reset; next touch can pan
				_pan_finger = -1
		return

	if event is InputEventScreenDrag:
		_touches[event.index] = event.position

		if event.index == _pan_finger and not _pinch_active:
			# Single-finger pan
			var right_pan := -transform.basis.x
			var forward_pan := Vector3(transform.basis.z.x, 0, transform.basis.z.z).normalized()
			var scale: float = _dist * 0.0012
			_target += right_pan * event.relative.x * scale
			_target += forward_pan * event.relative.y * scale * -1.0
			_clamp_target()
			_apply_position()

		elif _pinch_active and _touches.size() == 2:
			# Two-finger: pinch-zoom + centroid pan
			# Positions computed from stored dict (not raw event.relative) to avoid jitter
			var keys := _touches.keys()
			var pos_a: Vector2 = _touches[keys[0]]
			var pos_b: Vector2 = _touches[keys[1]]
			var new_dist := pos_a.distance_to(pos_b)
			var new_mid := (pos_a + pos_b) * 0.5

			# Zoom via distance ratio → feeds smooth lerp in _process
			if _prev_pinch_dist > 8.0 and new_dist > 8.0:
				_target_dist = clampf(_target_dist * (_prev_pinch_dist / new_dist), DIST_MIN, DIST_MAX)

			# Centroid pan — camera follows midpoint translation
			var mid_delta := new_mid - _prev_pinch_mid
			if mid_delta.length() > 1.0:
				var right_pan := -transform.basis.x
				var forward_pan := Vector3(transform.basis.z.x, 0, transform.basis.z.z).normalized()
				var pan_scale: float = _dist * 0.0012
				_target += right_pan * mid_delta.x * pan_scale
				_target += forward_pan * mid_delta.y * pan_scale * -1.0
				_clamp_target()

			_prev_pinch_dist = new_dist
			_prev_pinch_mid = new_mid
			_apply_position()
		return

	# Skip mouse events while any touch is active
	if _touches.size() > 0:
		return

	# --- Mouse (desktop) ---
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if get_viewport().gui_get_hovered_control() != null:
					return
				_target_dist = maxf(DIST_MIN, _target_dist - ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if get_viewport().gui_get_hovered_control() != null:
					return
				_target_dist = minf(DIST_MAX, _target_dist + ZOOM_STEP)
			MOUSE_BUTTON_LEFT:
				_left_drag = mb.pressed
			MOUSE_BUTTON_RIGHT:
				_right_drag = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_mid_drag = mb.pressed

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _left_drag and not _right_drag:
			var right_pan := -transform.basis.x
			var forward_pan := Vector3(transform.basis.z.x, 0, transform.basis.z.z).normalized()
			var scale: float = _dist * 0.0012
			_target += right_pan * mm.relative.x * scale
			_target += forward_pan * mm.relative.y * scale * -1.0
			_clamp_target()
			_apply_position()
		if _right_drag:
			_yaw -= mm.relative.x * 0.4
			_pitch += mm.relative.y * 0.3
			_pitch = clampf(_pitch, PITCH_MIN, PITCH_MAX)
			_apply_position()
		elif _mid_drag:
			var right := -transform.basis.x
			var forward := Vector3(transform.basis.z.x, 0, transform.basis.z.z).normalized()
			var scale: float = _dist * 0.0012
			_target += right * mm.relative.x * scale
			_target += forward * mm.relative.y * scale * -1.0
			_clamp_target()
			_apply_position()
