class_name VillagerAnimator
extends Node
## Plays one villager's AnimationTree (VillagerClips.tree_root) and keeps the feet honest.
## Settlement says what the person does through VillagerArt (play_action, play_once,
## set_locomotion_speed, set_carry); this node turns that into tree parameters when it updates.
##
## Locomotion follows the distance the figure really moved since the last update: the speed picks
## the gait (idle, walk, jog, run, measured against the body's size, so a child runs where an adult
## walks) and the clip rate is that distance over the gait's measured distance per cycle, so a
## planted foot stays put. An action gives way to walking while the figure is moving, so nobody
## slides along sitting or chopping.
##
## Level of detail: the tree and the skeleton run in manual mode. A villager near the camera
## updates every frame; further out every 2nd or 3rd frame and off screen every 4th, with the
## frames' time added up, so motion keeps its speed. Countdowns start staggered by id, so the
## updates of a crowd spread over the frames instead of landing on the same one.

const NEAR := 10.0 ## camera distance (world units) for an update every frame
const MID := 22.0 ## every 2nd frame up to here, every 3rd beyond
const RATE_NEAR := 1
const RATE_MID := 2
const RATE_FAR := 3
const RATE_HIDDEN := 4 ## off screen
const SMOOTHING := 0.12 ## seconds, for the speed that picks the gait
const MOVING_FROM := 0.02 ## adult speed where the gait starts to show over the idle
const MOVING_FULL := 0.1
const WALK_OVER := 0.16 ## adult speed above which an action gives way to walking
const MAX_CYCLES := 5.0 ## gait cycles a second, at most
const JUMP := 0.6 ## world units in one update: a teleport (a redress, a move), not a walk
const CARRY_FADE := 4.0 ## carry blend per second

var tree: AnimationTree
var skeleton: Skeleton3D
var body := 1.0 ## size against an adult's (height times growth)
var world_per_unit := 0.0 ## world units per skeleton unit
## True: speed is measured from the figure's movement. False (tools, stills): the speed given
## by set_locomotion_speed drives the gait as if the figure moved that fast.
var measure := true
var speed := 0.0 ## the speed Settlement last gave, world units a second
var action := "" ## the action asked for, or "" for standing and walking
var carrying := false
var idle_kind := "idle"
var rate := RATE_NEAR ## frames per update, as last chosen
var fixed_rate := 0 ## frames per update regardless of the camera (tools, tests), or 0

var _pending := 0.0
var _countdown := 0
var _last := Vector3.INF
var _smooth := 0.0
var _carry := 0.0
var _state := ""
var _idle_applied := ""
var _gesture := ""
var _params: Dictionary = {} ## parameter -> value last set, to skip repeated sets
var _cycle_lengths: PackedFloat32Array

static var _frame := -1
static var _camera: Camera3D
static var _planes: Array[Plane] = []
static var _eye := Vector3.ZERO


## seed spreads the first update over RATE_HIDDEN frames, so a crowd made at once stays spread.
func setup(animation_tree: AnimationTree, bones: Skeleton3D, size: float, units: float, seed_value: int) -> void:
	tree = animation_tree
	skeleton = bones
	body = maxf(size, 0.05)
	world_per_unit = units
	_cycle_lengths = VillagerClips.cycle_lengths()
	_countdown = 1 + posmod(seed_value, RATE_HIDDEN)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL


func _process(delta: float) -> void:
	_pending += delta
	_countdown -= 1
	if _countdown > 0:
		return
	rate = fixed_rate if fixed_rate > 0 else _choose_rate()
	_countdown = rate
	update(_pending)
	_pending = 0.0


## Applies what was asked and moves the clips on by dt seconds.
func update(dt: float) -> void:
	var moved := 0.0
	var parent := get_parent() as Node3D
	if measure and parent and parent.is_inside_tree():
		var at := parent.global_position
		if _last != Vector3.INF:
			moved = Vector2(at.x - _last.x, at.z - _last.z).length()
			if moved > JUMP:
				moved = 0.0
		_last = at
	else:
		moved = speed * dt
	var raw := moved / dt if dt > 0.0 else 0.0
	_smooth = lerpf(_smooth, raw, 1.0 - exp(-dt / SMOOTHING)) if dt > 0.0 else raw
	var adult := _smooth / body
	var walking := adult > WALK_OVER
	var state := "move" if action.is_empty() or walking else action
	if state != _state:
		_state = state
		tree.set("parameters/state/transition_request", state)
	if idle_kind != _idle_applied:
		_idle_applied = idle_kind
		tree.set("parameters/idle_kind/transition_request", idle_kind)
	if state == "move":
		_param("parameters/moving/blend_amount", smoothstep(MOVING_FROM, MOVING_FULL, adult))
		_param("parameters/gait/blend_position", adult)
		var cycle := VillagerClips.cycle_length_at(adult) * world_per_unit
		_param("parameters/pace/scale", clampf(raw / cycle, 0.0, MAX_CYCLES) if cycle > 0.0 else 0.0)
		_carry = move_toward(_carry, 1.0 if carrying else 0.0, dt * CARRY_FADE)
		_param("parameters/carry/blend_amount", _carry)
	if not _gesture.is_empty():
		tree.set("parameters/gesture_kind/transition_request", _gesture)
		tree.set("parameters/gesture/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_gesture = ""
	tree.advance(dt)
	skeleton.advance(dt)


## True when this frame's _process will update the clips. Settlement steps the walker's steering
## on the same frames, so a far walker moves and animates at one cadence.
func updates_this_frame() -> bool:
	return _countdown <= 1 or not is_processing()


## A one-shot gesture over the current state on the next update.
func fire(gesture: String) -> void:
	_gesture = gesture


## Which clips are playing, for tests and tools: the state and, while moving, the gait position.
func state() -> String:
	return _state


func _param(path: String, value: float) -> void:
	if is_equal_approx(float(_params.get(path, -999.0)), value):
		return
	_params[path] = value
	tree.set(path, value)


func _choose_rate() -> int:
	var parent := get_parent() as Node3D
	if parent == null or not parent.is_inside_tree():
		return RATE_NEAR
	_refresh_camera(get_viewport())
	if _camera == null:
		return RATE_NEAR
	var at := parent.global_position
	return rate_for(at.distance_to(_eye), _in_view(at + Vector3(0.0, 0.3 * body, 0.0), 0.5 * body))


## Frames per update for a villager this far from the camera, on screen or not.
static func rate_for(distance: float, on_screen: bool) -> int:
	if not on_screen:
		return RATE_HIDDEN
	if distance < NEAR:
		return RATE_NEAR
	if distance < MID:
		return RATE_MID
	return RATE_FAR


## The camera's frustum, read once a frame for every villager.
static func _refresh_camera(viewport: Viewport) -> void:
	var frame := Engine.get_process_frames()
	if frame == _frame:
		return
	_frame = frame
	_camera = viewport.get_camera_3d() if viewport else null
	_planes.clear()
	if _camera:
		_eye = _camera.global_position
		_planes.assign(_camera.get_frustum())


## True when a sphere around the point is at least partly inside the camera's view.
static func _in_view(point: Vector3, radius: float) -> bool:
	for plane: Plane in _planes:
		if plane.distance_to(point) > radius:
			return false
	return true
