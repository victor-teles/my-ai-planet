extends TestCase
## M3.5's exit check: the same island played with two different AIs and once offline. Every
## tribe gets its look in all three, the two AIs' looks differ, the asset calls keep to their
## share of the budget, and the specs never change the sim.

const YEARS := 60
const SEED := 42


## Stands in for a real model: it writes valid specs of its own (the offline writers, salted), at
## the price of a small call, and answers the story's tasks from the offline templates.
class SaltedProvider:
	extends AIProvider
	var id: String
	var salt: int
	var calls := {} ## task -> calls

	func _init(provider_id: String, salt_value: int) -> void:
		id = provider_id
		salt = salt_value

	func get_id() -> String:
		return id

	func is_available() -> bool:
		return true

	func complete(request: AIRequest) -> AIResponse:
		calls[request.task] = int(calls.get(request.task, 0)) + 1
		var kind := AssetKinds.find(request.task)
		var response: AIResponse
		if kind:
			response = AIResponse.success(id, kind.offline(request.context, request.seed_value + salt))
		else:
			response = await OfflineTemplatesProvider.new().complete(request)
			response.provider_id = id
		response.cost_usd = 0.0004
		return response


## Plays the island for YEARS with an AssetDirector on the given provider: [director, state].
func _run(ai: AIProvider) -> Array:
	var sim := Simulation.create(SEED)
	var director := AssetDirector.new(Oracle.new(ai, AICache.new()))
	director.observe(sim.state)
	for day: int in YEARS * WorldState.DAYS_PER_YEAR:
		sim.advance()
		director.observe(sim.state)
	await director.settle(sim.state)
	return [director, sim.state]


## The sim's checksum, leaving the looks out.
func _sim_checksum(state: WorldState) -> String:
	var looks := state.assets
	state.assets = {}
	var checksum := state.checksum()
	state.assets = looks
	return checksum


func test_two_ais_and_offline_give_one_island_three_coherent_looks() -> void:
	var first := SaltedProvider.new("first-ai", 1)
	var second := SaltedProvider.new("second-ai", 2)
	var runs: Array[AssetDirector] = []
	var states: Array[WorldState] = []
	for ai: AIProvider in [first, second, OfflineTemplatesProvider.new()]:
		var run := await _run(ai)
		runs.append(run[0])
		states.append(run[1])
	assert_eq(_sim_checksum(states[0]), _sim_checksum(states[2]), "the looks never change the sim")
	var tribes := Array(states[0].tribe_names)
	assert_eq(tribes, Array(states[1].tribe_names), "the same island, the same peoples")
	var differs := {}
	for r: int in runs.size():
		var state := states[r]
		for kind: AssetKind in AssetKinds.all():
			for subject: String in kind.subjects(state):
				assert_true(not AssetDirector.spec_or_offline(state, kind.task(), subject).is_empty(), "run %d: %s of %s is drawn" % [r, kind.task(), subject])
		for tribe: String in tribes:
			for task: String in ["style", "heraldry", "names"]:
				assert_true(AssetBook.has_spec(state, task, tribe), "run %d: %s of %s is stored" % [r, task, tribe])
				if r == 1 and AssetBook.spec(states[0], task, tribe) != AssetBook.spec(state, task, tribe):
					differs[task] = true
		var used := float(runs[r].oracle.budget.share_of(AssetKinds.tasks()))
		assert_true(used <= AssetDirector.SHARE, "run %d: asset calls used %.3f of the budget" % [r, used])
	# Names are left out: the stand-in writes them like the offline writer, which keeps them stable.
	for task: String in ["style", "heraldry"]:
		assert_true(differs.has(task), "the two AIs write different %s" % task)
	assert_eq(runs[2].written["ai"], 0, "offline writes everything itself")
	assert_true(runs[0].written["ai"] > 0, "the AI wrote some")
	print("        first AI: %s calls %s, offline: %s" % [runs[0].written, first.calls, runs[2].written])
