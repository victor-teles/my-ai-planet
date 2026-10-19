class_name BuildingMotion
extends Node3D
## A moving part of a building that animates itself: a searchlight that turns or sweeps, a
## warning light that blinks, forge coals that glow and fade. Each is one small node with no
## allocations per frame, so a big village can run dozens of them.

enum Kind { SPIN, SWEEP, BLINK, FLICKER }

var kind := Kind.SPIN
## Radians per second for SPIN and SWEEP; blinks or flickers per second for BLINK and FLICKER.
var speed := 0.5
## SWEEP: how far to each side it turns, in radians. BLINK: the share of each blink it stays lit.
var amount := 0.8
## A light that dims and brightens with the part (BLINK, FLICKER), or null.
var light: Light3D

var _time := 0.0
var _energy := 1.0
var _lit := true


static func make(motion_kind: Kind, motion_speed: float, motion_amount: float = 0.8) -> BuildingMotion:
	var motion := BuildingMotion.new()
	motion.kind = motion_kind
	motion.speed = motion_speed
	motion.amount = motion_amount
	return motion


func _ready() -> void:
	# Visual only: each part starts at its own point so a row of them doesn't move in lockstep.
	_time = randf() * 10.0
	if light:
		_energy = light.light_energy


func _process(delta: float) -> void:
	_time += delta
	match kind:
		Kind.SPIN:
			rotation.y = fposmod(rotation.y + speed * delta, TAU)
		Kind.SWEEP:
			rotation.y = sin(_time * speed) * amount
		Kind.BLINK:
			var lit := fposmod(_time * speed, 1.0) < amount
			if lit != _lit:
				_lit = lit
				for child: Node in get_children():
					if child is Node3D:
						(child as Node3D).visible = lit
		Kind.FLICKER:
			var flicker := 0.85 + 0.1 * sin(_time * speed * 13.0) + 0.05 * sin(_time * speed * 23.0)
			scale = Vector3(1.0, flicker, 1.0)
			if light:
				light.light_energy = _energy * flicker
