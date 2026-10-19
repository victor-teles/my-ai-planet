class_name CameraRig
extends Node3D
## Orbiting diorama camera. Drag to orbit, scroll or pinch to zoom (a trackpad's two-finger swipe
## zooms up and down and orbits sideways); drifts slowly when left alone.
## It can follow a point (a person going about their day) and glides back to the island's middle.
## Narrow field of view plus near and far blur gives the miniature (tilt-shift) look.

const MIN_DISTANCE := 5.0
const MAX_DISTANCE := 48.0 ## for an island of radius 10; see fit()
const IDLE_SPIN := 0.04 ## radians per second
const IDLE_AFTER := 4.0 ## seconds without input

var yaw := 0.6
var pitch := -0.42
var distance := 30.0
## The point the camera circles; set every frame to follow something, or leave at the middle.
var focus := Vector3.ZERO
var camera := Camera3D.new()
var max_distance := MAX_DISTANCE

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


## Frames an island of this radius: the starting view and how far out you can zoom grow with it.
func fit(island_radius: float) -> void:
	var scale_by := island_radius / 10.0
	distance *= scale_by
	max_distance = MAX_DISTANCE * maxf(scale_by, 1.0)


func _process(delta: float) -> void:
	_idle_time += delta
	if _idle_time > IDLE_AFTER:
		yaw += IDLE_SPIN * delta
	position = position.lerp(focus, minf(delta * 2.5, 1.0))
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button:
		match button.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_dragging = button.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(0.92)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.08)
		_idle_time = 0.0
	# macOS sends trackpad pinches and two-finger swipes as gestures, not wheel clicks.
	var pinch := event as InputEventMagnifyGesture
	if pinch and pinch.factor > 0.0:
		_zoom(1.0 / pinch.factor)
		_idle_time = 0.0
	var swipe := event as InputEventPanGesture
	if swipe:
		_zoom(pow(1.04, swipe.delta.y))
		yaw -= swipe.delta.x * 0.03
		_idle_time = 0.0
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		yaw -= motion.relative.x * 0.006
		pitch = clampf(pitch - motion.relative.y * 0.004, -1.25, -0.12)
		_idle_time = 0.0


func _zoom(factor: float) -> void:
	distance = clampf(distance * factor, MIN_DISTANCE, max_distance)


func _apply() -> void:
	rotation = Vector3(pitch, yaw, 0.0)
	camera.position = Vector3(0.0, 0.0, distance)
	# Keep what we're looking at sharp and blur what's in front of and behind it. Up close the
	# sharp band narrows, like a real lens near a miniature.
	var band := clampf(distance * 0.4, 3.0, 12.0)
	_attributes.dof_blur_near_distance = maxf(distance - band, 0.5)
	_attributes.dof_blur_near_transition = band * 0.5
	_attributes.dof_blur_far_distance = distance + band
	_attributes.dof_blur_far_transition = band * 2.0
