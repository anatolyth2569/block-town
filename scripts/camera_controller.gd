class_name CameraController
extends Camera3D

const PAN_SPEED: float = 22.0
const ZOOM_STEP: float = 3.5
const DIST_MIN: float = 12.0
const DIST_MAX: float = 95.0
const ROTATE_STEP: float = 90.0

const PITCH_MIN: float = 15.0
const PITCH_MAX: float = 75.0

var _target: Vector3 = Vector3(30, 0, 30)
var _yaw: float = 225.0    # left-right rotation (degrees)
var _pitch: float = 42.0   # tilt angle (degrees, higher = more top-down view)
var _dist: float = 50.0    # distance from target

var _right_drag: bool = false
var _mid_drag: bool = false
var _left_drag: bool = false

func _ready() -> void:
	current = true
	projection = Camera3D.PROJECTION_PERSPECTIVE
	fov = 55.0
	_apply_position()

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
		_apply_position()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_Q:
			_yaw -= ROTATE_STEP
			_apply_position()
		elif key.keycode == KEY_E:
			_yaw += ROTATE_STEP
			_apply_position()

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
			_apply_position()
