class_name SimRng
extends RefCounted
## The only source of randomness inside core/. Never call the global randf()/randi()
## from simulation code, or the same seed stops producing the same world.

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value


func randf() -> float:
	return _rng.randf()


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func chance(probability: float) -> bool:
	return _rng.randf() < probability


## Rounds up with probability equal to the fractional part, so expected value is kept
## (2.3 becomes 3 thirty percent of the time). Keeps small populations from freezing.
func round_stochastic(value: float) -> int:
	var whole := floorf(value)
	return int(whole) + (1 if _rng.randf() < value - whole else 0)


func pick_index(size: int) -> int:
	return _rng.randi_range(0, size - 1)


## Seed and state are 64-bit, which JSON numbers (doubles) can't hold exactly, so they're saved as strings.
func to_dict() -> Dictionary:
	return {"seed": str(_rng.seed), "state": str(_rng.state)}


static func from_dict(data: Dictionary) -> SimRng:
	var rng := SimRng.new()
	rng._rng.seed = String(data["seed"]).to_int()
	rng._rng.state = String(data["state"]).to_int()
	return rng
