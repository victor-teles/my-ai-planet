class_name CameraRig
extends Node3D
## Orbiting diorama camera. Drag to orbit, scroll to zoom; drifts slowly when left alone.
## Narrow field of view plus near and far blur gives the miniature (tilt-shift) look.

const MIN_DISTANCE := 14.0
const MAX_DISTANCE := 48.0
const IDLE_SPIN := 0.04 ## radians per second
const IDLE_AFTER := 4.0 ## seconds without input

var yaw := 0.6
var pitch := -0.42
var distance := 30.0
var camera := Camera3D.new()

var _attributes := CameraAttributesPractical.new()
var _dragging := false
var _idle_time := IDLE_AFTER


func _ready() -> void:
	camera.fov = 32.0
	camera.far = 400.0
	_attributes.dof_blur_far_enabled = true
	_attributes.dof_blur_near_enabled = true
	_attributes.dof_blur_amount = 0.08
	camera.attributes = _attributes
	add_child(camera)
	_apply()


func _process(delta: float) -> void:
	_idle_time += delta
	if _idle_time > IDLE_AFTER:
		yaw += IDLE_SPIN * delta
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button:
		match button.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_dragging = button.pressed
			MOUSE_BUTTON_WHEEL_UP:
				distance = maxf(distance * 0.92, MIN_DISTANCE)
			MOUSE_BUTTON_WHEEL_DOWN:
				distance = minf(distance * 1.08, MAX_DISTANCE)
		_idle_time = 0.0
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		yaw -= motion.relative.x * 0.006
		pitch = clampf(pitch - motion.relative.y * 0.004, -1.25, -0.12)
		_idle_time = 0.0


func _apply() -> void:
	rotation = Vector3(pitch, yaw, 0.0)
	camera.position = Vector3(0.0, 0.0, distance)
	# Keep the island sharp and blur what's in front of and behind it.
	_attributes.dof_blur_near_distance = distance - 12.0
	_attributes.dof_blur_near_transition = 6.0
	_attributes.dof_blur_far_distance = distance + 10.0
	_attributes.dof_blur_far_transition = 25.0
