extends TestCase

## Tests that take over 15 seconds; scripts/test.sh --quick skips them.
const SLOW := ["test_a_century_of_play_paces_its_dilemmas"]

const YEAR := WorldState.DAYS_PER_YEAR

var _next_id := 0


func _drama(cycle_years: int = 50) -> DramaManager:
	var drama := DramaManager.new()
	drama.begin(0, -1)
	drama.set_cycle(0, cycle_years * YEAR)
	return drama


func _event(type: String, tribe: String = "Kolu", data: Dictionary = {}) -> Dictionary:
	var full := data.duplicate()
	full["tribe"] = tribe
	_next_id += 1
	return {"id": _next_id, "tick": 0, "type": type, "data": full}


## Steps day by day, calling each_day(drama, day) first, until a card is due; returns the day.
func _days_until_due(drama: DramaManager, each_day: Callable, from_day: int = 1) -> int:
	for day: int in range(from_day, from_day + 30 * YEAR):
		drama.advance_to(day)
		each_day.call(drama, day)
		if drama.is_due():
			return day
	return from_day + 30 * YEAR


func test_tension_rises_with_drama_and_decays() -> void:
	var drama := _drama()
	assert_eq(drama.tension(), 0.0)
	drama.feel(_event("birth"))
	assert_true(drama.tension() == 0.0, "a birth is no drama")
	drama.feel(_event("war"))
	var after_war := drama.tension()
	assert_true(after_war >= 20.0, "a war raises tension: %s" % after_war)
	drama.feel(_event("famine"))
	assert_true(drama.tension() > after_war, "more drama, more tension")
	var peak := drama.tension()
	drama.advance_to(roundi(DramaManager.HALF_LIFE_YEARS * YEAR))
	assert_true(absf(drama.tension() - peak / 2.0) < 0.01, "halves over a calm half-life: %s" % drama.tension())
	drama.advance_to(10 * YEAR)
	assert_true(drama.tension() < 2.0, "calm years let it fade: %s" % drama.tension())
	for k: int in 30:
		drama.feel(_event("revolution"))
	assert_true(drama.tension() <= DramaManager.MAX_TENSION, "tension saturates")
	drama.feel(_event("drought_ended"))
	assert_true(drama.tension() < DramaManager.MAX_TENSION, "relief lowers it")


func test_target_builds_to_the_deadline_and_releases_after_a_reveal() -> void:
	var drama := _drama(40)
	var start := drama.target()
	drama.advance_to(20 * YEAR)
	var middle := drama.target()
	drama.advance_to(40 * YEAR)
	var deadline := drama.target()
	assert_true(start < middle and middle < deadline, "builds: %s %s %s" % [start, middle, deadline])
	assert_eq(deadline, DramaManager.PEAK_TARGET)
	drama.note_reveal()
	drama.set_cycle(40 * YEAR, 80 * YEAR)
	assert_true(drama.target() < start, "released after the reveal: %s" % drama.target())
	assert_eq(drama.pacing_hint(), "the story just peaked; let it breathe")


func test_pacing_hint_follows_the_gap() -> void:
	var drama := _drama()
	drama.advance_to(40 * YEAR)
	assert_eq(drama.pacing_hint(), "raise the stakes")
	for k: int in 8:
		drama.feel(_event("revolution"))
	assert_eq(drama.pacing_hint(), "the story needs calm")


func test_a_flat_story_brings_a_card_sooner_than_a_busy_one() -> void:
	var flat := _days_until_due(_drama(), func(_d: DramaManager, _day: int) -> void: pass)
	# A god who keeps casting miracles keeps the story busy (and the god's deeds never hook a card).
	var busy := _days_until_due(_drama(), func(d: DramaManager, day: int) -> void:
		if day % WorldState.DAYS_PER_MONTH == 0:
			d.feel(_event("miracle")))
	assert_true(flat < busy, "flat %d days, busy %d days" % [flat, busy])
	assert_true(flat >= roundi(DramaManager.SHORTEST_GAP_YEARS * YEAR), "never sooner than the shortest gap")


func test_fresh_drama_brings_a_card_early_but_not_before_the_cooldown() -> void:
	var calm := _days_until_due(_drama(), func(_d: DramaManager, _day: int) -> void: pass)
	var war_day := 2 * YEAR + 200
	var stirred := _days_until_due(_drama(), func(d: DramaManager, day: int) -> void:
		if day == war_day:
			d.feel(_event("war")))
	assert_eq(stirred, roundi(DramaManager.HOOK_MIN_GAP_YEARS * YEAR), "the war brings the card at the drama cooldown")
	assert_true(stirred < calm, "sooner than a calm story: %d vs %d" % [stirred, calm])
	var at_once := _days_until_due(_drama(), func(d: DramaManager, day: int) -> void:
		if day == 10:
			d.feel(_event("war")))
	assert_true(at_once > 10 + roundi(DramaManager.HOOK_FRESH_YEARS * YEAR), "a stale hook doesn't fire: %d" % at_once)


func test_hard_cooldowns_hold() -> void:
	var drama := _drama()
	drama.advance_to(5 * YEAR)
	drama.note_card()
	# Even a world on fire waits for the minimum gap.
	var next := _days_until_due(drama, func(d: DramaManager, day: int) -> void:
		if day % 90 == 0:
			d.feel(_event("revolution", "Tribe%d" % day)), 5 * YEAR + 1)
	assert_true(next - 5 * YEAR >= roundi(DramaManager.MIN_GAP_YEARS * YEAR), "min gap held: %d days" % (next - 5 * YEAR))
	# No card right after a reveal or a destiny chapter.
	for quiet: Array in [["reveal", DramaManager.REVEAL_QUIET_YEARS], ["destiny", DramaManager.DESTINY_QUIET_YEARS]]:
		var after := _drama()
		after.advance_to(20 * YEAR)
		assert_true(after.is_due(), "due before the %s" % quiet[0])
		if quiet[0] == "reveal":
			after.note_reveal()
		else:
			after.note_destiny()
		assert_true(not after.is_due(), "not due right after the %s" % quiet[0])
		after.advance_to(20 * YEAR + roundi(float(quiet[1]) * YEAR))
		assert_true(after.is_due(), "due again after the %s's quiet" % quiet[0])
	# At most MAX_CARDS_PER_WINDOW cards in any window, even when the story wants more.
	var window := _drama(1)
	var cards: Array[int] = []
	for day: int in range(1, 40 * YEAR):
		window.advance_to(day)
		if day % 120 == 0:
			window.feel(_event(["war", "famine", "revolution", "tribe_split", "disaster"][posmod(day, 600) / 120], "T%d" % day))
		if window.is_due():
			window.note_card()
			cards.append(day)
	assert_true(cards.size() >= 4, "cards still come: %s" % [cards])
	for k: int in range(DramaManager.MAX_CARDS_PER_WINDOW, cards.size()):
		var span := cards[k] - cards[k - DramaManager.MAX_CARDS_PER_WINDOW]
		assert_true(span >= roundi(DramaManager.WINDOW_YEARS * YEAR), "window held: %s" % [cards])


func test_the_same_kind_of_drama_does_not_bring_cards_back_to_back() -> void:
	var drama := _drama()
	drama.advance_to(3 * YEAR)
	drama.feel(_event("famine"))
	assert_true(drama.is_due(), "a famine brings a card")
	drama.note_card()
	drama.advance_to(6 * YEAR)
	drama.feel(_event("drought_started"))
	assert_true(not drama.is_due(), "another hardship of the world so soon doesn't")
	drama.feel(_event("war"))
	assert_true(drama.is_due(), "a war is a new kind of drama")


func test_deterministic_for_the_same_inputs() -> void:
	var runs: Array[Array] = []
	for run: int in 2:
		var drama := _drama(30)
		var trace: Array = []
		for day: int in range(1, 30 * YEAR):
			drama.advance_to(day)
			if posmod(hash([7, day]), 97) == 0:
				drama.feel(_event(["war", "famine", "death", "birth", "miracle", "drought_ended"][posmod(hash(day), 6)]))
			if drama.is_due():
				drama.note_card()
				trace.append(day)
			if day % YEAR == 0:
				trace.append([drama.tension(), drama.target(), drama.days_until_next(), drama.pacing_hint()])
		runs.append(trace)
	assert_eq(runs[0], runs[1], "same events, same pacing")


func test_observe_reads_only_new_events_from_the_world() -> void:
	var state := WorldState.create(3)
	var drama := DramaManager.new()
	drama.begin(state.tick, state.next_event_id - 1)
	drama.observe(state)
	assert_eq(drama.tension(), 0.0, "history before the start doesn't count")
	state.log_event("war", {"tribe": state.tribe_names[0]})
	drama.observe(state)
	var after := drama.tension()
	assert_true(after > 0.0, "a new war counts")
	drama.observe(state)
	assert_eq(drama.tension(), after, "an event counts once")


func test_pacer_merges_bursts_and_drops_small_ones_first() -> void:
	var pacer := EventPacer.new(0.5, 2.0)
	for k: int in 3:
		pacer.push(_event("birth", "Kolu", {"name": "Baby%d" % k}))
	pacer.push(_event("birth", "Wari", {"name": "Lone"}))
	pacer.push(_event("war", "Kolu", {"enemy": "Wari"}))
	var now := pacer.take(0.0)
	assert_eq(now.size(), 1, "big news comes out at once")
	assert_eq(String(now[0]["event"]["type"]), "war")
	assert_eq(pacer.take(EventPacer.GATHER_SECONDS / 2.0).size(), 0, "small events gather first")
	var later := pacer.take(EventPacer.GATHER_SECONDS / 2.0)
	assert_eq(later.size(), 1, "the budget left after the war covers one line: %s" % [later])
	assert_eq(int(later[0]["count"]), 3, "the biggest burst goes first")
	assert_eq(EventPacer.burst_text(later[0]), "3 children were born to the Kolu.")
	assert_eq(EventPacer.burst_text(later[0], true), "3 born")
	# Big news always gets through, even with the budget spent.
	for k: int in 5:
		pacer.push(_event("famine", "T%d" % k))
	assert_eq(pacer.take(0.0).size(), 5)
	var deaths: Array[Dictionary] = [_event("death", "Kolu", {"chief": 1}), _event("death", "Kolu", {"chief": 1})]
	var chiefs := EventPacer.group(deaths)
	assert_eq(chiefs.size(), 2, "chiefs' deaths stay on their own")


func test_a_century_of_play_paces_its_dilemmas() -> void:
	var session := Session.new(Simulation.create(42), Oracle.new(OfflineTemplatesProvider.new()))
	await session.begin()
	var shown: Array[int] = []
	for month: int in 100 * WorldState.MONTHS_PER_YEAR:
		while session.phase != Session.Phase.PLAYING:
			if session.phase == Session.Phase.DECIDING:
				shown.append(session.sim.state.tick)
				session.choose(0)
			elif session.phase == Session.Phase.REVEAL:
				await session.continue_after_reveal()
			else:
				assert_true(false, "the offline Oracle answers at once, but the session is %s" % Session.Phase.keys()[session.phase])
				return
		session.advance(WorldState.DAYS_PER_MONTH)
	var shortest := 100 * YEAR
	for k: int in range(1, shown.size()):
		shortest = mini(shortest, shown[k] - shown[k - 1])
	print("        100 years, seed 42: %d dilemmas, shortest gap %.1f years" % [shown.size(), shortest / float(YEAR)])
	assert_true(shown.size() >= 8 and shown.size() <= 25, "a sensible number of dilemmas: %d" % shown.size())
	assert_true(shortest >= roundi(DramaManager.MIN_GAP_YEARS * YEAR), "never two close together: %d days" % shortest)
