extends SceneTree

func _initialize() -> void:
	var sim := Simulation.create(42)
	var state := sim.state
	print("pop %d tribes %d prey %d rates %s rain %s" % [state.total_population(), state.tribe_count(), AnimalSystem.prey_count(state), state.world["rates"], state.world["rain"]])
	print("chance1 %s cap18 %s" % [AnimalSystem.typical_hunt_chance(), AnimalSystem.sustainable_hunt_work(18)])
	for day: int in 120:
		var food_before := 0.0
		for t: int in state.tribe_count():
			food_before += state.tribe_food[t]
		var eat := 0.0
		for p: int in state.person_ids.size():
			eat += float(EconomySystem.EATS[People.stage(state, p)])
		if day % 30 == 0:
			var works: Array = []
			for t: int in state.tribe_count():
				works.append(state.tribe_work[t])
			print("day %d pop %d food %.1f eat %.2f prey %d hungry %s work %s" % [day, state.total_population(), food_before, eat, AnimalSystem.prey_count(state), str(Array(state.tribe_hungry_days)), str(works)])
		sim.advance(1)
	quit()
