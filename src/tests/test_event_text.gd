extends TestCase
## Every event the core logs reads as a sentence in the life feed, never as the raw fallback.

## One example of every event type the core logs, with the data it logs.
const SAMPLES: Array[Dictionary] = [
	{"type": "birth", "data": {"tribe": "Oru", "id": 9, "name": "Teshu", "sex": "m", "mother": 1, "mother_name": "Mirra", "father": 2, "father_name": "Kael", "named_after": "his late grandfather Bo", "twin": 1}},
	{"type": "death", "data": {"id": 1, "name": "Mirra", "age": 71, "cause": "old age", "tribe": "Oru", "job": "healer", "chief": 1}},
	{"type": "death", "data": {"id": 1, "name": "Mirra", "age": 30, "cause": "childbirth", "tribe": "Oru", "job": ""}},
	{"type": "death", "data": {"id": 1, "name": "Kael", "age": 30, "cause": "war", "tribe": "Oru", "job": "hunter", "enemy": "Vee"}},
	{"type": "death", "data": {"id": 1, "name": "Kael", "age": 30, "cause": "accident", "tribe": "Oru", "job": "hunter", "while": "on the hunt"}},
	{"type": "death", "data": {"id": 1, "name": "Kael", "age": 30, "cause": "a fight", "tribe": "Oru", "job": "hunter", "by": "Bo"}},
	{"type": "death", "data": {"id": 1, "name": "Kael", "age": 3, "cause": "sickness", "tribe": "Oru", "job": ""}},
	{"type": "death", "data": {"id": 1, "name": "Kael", "age": 40, "cause": "hunger", "tribe": "Oru", "job": "forager"}},
	{"type": "death", "data": {"id": 1, "name": "Kael", "age": 40, "cause": "thirst", "tribe": "Oru", "job": "forager"}},
	{"type": "death", "data": {"id": 1, "name": "Kael", "age": 40, "cause": "plague", "tribe": "Oru", "job": "forager"}},
	{"type": "coming_of_age", "data": {"tribe": "Oru", "id": 3, "name": "Lia", "traits": "brave and kind"}},
	{"type": "romance", "data": {"tribe": "Oru", "a": 3, "a_name": "Lia", "b": 4, "b_name": "Rin"}},
	{"type": "marriage", "data": {"a": 3, "a_name": "Lia", "b": 4, "b_name": "Rin", "tribe": "Oru"}},
	{"type": "marriage", "data": {"a": 3, "a_name": "Lia", "b": 4, "b_name": "Rin", "tribe": "Oru", "moved_from": "Vee", "mover": 4, "mover_name": "Rin", "stayer_name": "Lia"}},
	{"type": "proposal_refused", "data": {"tribe": "Oru", "a": 3, "a_name": "Lia", "b": 4, "b_name": "Rin"}},
	{"type": "separation", "data": {"tribe": "Oru", "a": 3, "a_name": "Lia", "b": 4, "b_name": "Rin"}},
	{"type": "fight", "data": {"tribe": "Oru", "a": 3, "a_name": "Lia", "b": 4, "b_name": "Rin"}},
	{"type": "job", "data": {"tribe": "Oru", "id": 3, "name": "Lia", "job": "healer", "first": 1}},
	{"type": "job", "data": {"tribe": "Oru", "id": 3, "name": "Lia", "job": "hunter", "why": "followed her mother and became a hunter"}},
	{"type": "apprentice", "data": {"tribe": "Oru", "id": 3, "name": "Lia", "job": "potter", "teacher": "Mirra"}},
	{"type": "hunt", "data": {"species": "deer", "tribe": "Oru", "meat": "8.5"}},
	{"type": "hunt", "data": {"species": "deer", "tribe": "Oru", "wiped": true}},
	{"type": "adoption", "data": {"tribe": "Oru", "id": 3, "name": "Lia", "by": "Mirra", "by_id": 1}},
	{"type": "building_planned", "data": {"tribe": "Oru", "building": "storehouse", "needs": "12 wood and 4 stone"}},
	{"type": "building_started", "data": {"tribe": "Oru", "building": "healer_hut", "building_id": 5, "rebuild": 0}},
	{"type": "building_done", "data": {"tribe": "Oru", "building": "longhouse", "building_id": 5, "builders": "Lia and Rin"}},
	{"type": "discovery", "data": {"tribe": "Oru", "tech": "agriculture", "id": 3, "name": "Lia"}},
	{"type": "tech_spread", "data": {"tech": "pottery", "from": "Oru", "to": "Vee"}},
	{"type": "new_chief", "data": {"tribe": "Oru", "id": 3, "name": "Lia", "traits": "wise, kind", "reason": "founding", "age": 40}},
	{"type": "new_chief", "data": {"tribe": "Oru", "id": 3, "name": "Lia", "traits": "wise, kind", "reason": "death", "age": 40}},
	{"type": "new_chief", "data": {"tribe": "Oru", "id": 3, "name": "Lia", "traits": "wise, kind", "reason": "council", "age": 40}},
	{"type": "tribe_split", "data": {"from": "Oru", "to": "Vee", "people": 14, "tribe": "Vee", "leader": 3, "leader_name": "Lia"}},
	{"type": "tribe_split", "data": {"from": "Oru", "to": "Vee", "people": 14, "tribe": "Vee"}},
	{"type": "tribes_merged", "data": {"from": "Vee", "into": "Oru", "people": 6, "tribe": "Oru"}},
	{"type": "tribe_extinct", "data": {"tribe": "Vee"}},
	{"type": "tribe_moved", "data": {"tribe": "Oru", "water": "Kaa Spring"}},
	{"type": "newcomers", "data": {"tribe": "Oru", "people": 4}},
	{"type": "gifts", "data": {"from": "Oru", "to": "Vee", "tribe": "Oru", "chief": "Lia", "id": 3}},
	{"type": "war", "data": {"winner": "Oru", "loser": "Vee", "tribe": "Vee", "deaths": 3, "fallen": "Rin, Bo, Kit"}},
	{"type": "incident", "data": {"tribe": "Oru", "other": "Vee", "what": "a quarrel over a deer", "a": 1, "a_name": "Kael", "b": 2, "b_name": "Mirra"}},
	{"type": "raid", "data": {"tribe": "Oru", "victim": "Vee", "days": 9, "id": 4, "chief": "Teshu"}},
	{"type": "famine", "data": {"tribe": "Oru"}},
	{"type": "epidemic", "data": {"tribe": "Oru", "sick": 7}},
	{"type": "drought_started", "data": {"months": 6}},
	{"type": "drought_ended", "data": {}},
	{"type": "water_low", "data": {"water": "the Pond"}},
	{"type": "dilemma", "data": {"title": "The Last Well", "choice": "Make them share the water"}},
	{"type": "prophecy_fulfilled", "data": {}},
	{"type": "prophecy_broken", "data": {}},
	{"type": "miracle", "data": {"miracle": "rain"}},
	{"type": "miracle", "data": {"miracle": "harvest", "tribe": "Oru"}},
	{"type": "miracle", "data": {"miracle": "drought"}},
	{"type": "miracle", "data": {"miracle": "plague", "tribe": "Oru", "deaths": 5}},
	{"type": "miracle", "data": {"miracle": "muse", "tribe": "Oru", "id": 3, "name": "Lia"}},
	{"type": "miracle", "data": {"miracle": "smite", "tribe": "Oru", "id": 3, "name": "Lia"}},
	{"type": "miracle", "data": {"miracle": "awaken", "tribe": "Oru"}},
	{"type": "miracle", "data": {"miracle": "sanctify", "tribe": "Oru", "id": 3, "name": "Lia"}},
	{"type": "death", "data": {"id": 1, "name": "Kael", "age": 40, "cause": "the uprising", "tribe": "Oru", "job": "guard"}},
	{"type": "death", "data": {"id": 1, "name": "Kael", "age": 40, "cause": "exile", "tribe": "Oru", "job": ""}},
	{"type": "death", "data": {"id": 1, "name": "Kael", "age": 60, "cause": "lightning", "tribe": "Oru", "job": "", "chief": 1}},
	{"type": "new_chief", "data": {"tribe": "Oru", "id": 3, "name": "Lia", "traits": "proud, greedy", "reason": "inheritance", "age": 30}},
	{"type": "new_age", "data": {"tribe": "Oru", "age": 1, "name": "Age of Bronze", "first": 1}},
	{"type": "new_age", "data": {"tribe": "Vee", "age": 1, "name": "Age of Bronze", "first": 0}},
	{"type": "disaster", "data": {"kind": "storms", "tribe": "Oru", "building": "hut"}},
	{"type": "disaster", "data": {"kind": "quakes", "tribe": "Oru", "building": "temple"}},
	{"type": "disaster", "data": {"kind": "locusts", "tribe": "Oru", "days": 20}},
	{"type": "disaster", "data": {"kind": "blizzards", "tribe": "Oru"}},
	{"type": "destiny", "data": {"kind": "panopticon", "tribe": "Oru", "name": "The Panopticon"}},
	{"type": "law_passed", "data": {"tribe": "Oru", "law": "secret_police", "id": 3, "name": "Lia", "reason": "after the uprising"}},
	{"type": "law_passed", "data": {"tribe": "Oru", "law": "elder_council"}},
	{"type": "law_repealed", "data": {"tribe": "Oru", "law": "exile", "id": 3, "name": "Lia", "reason": "the people demanded it"}},
	{"type": "law_blocked", "data": {"tribe": "Oru", "law": "bonded_labor", "id": 3, "name": "Lia"}},
	{"type": "law_refused", "data": {"tribe": "Oru", "law": "assembly", "id": 3, "name": "Lia", "faction": "council"}},
	{"type": "new_dynasty", "data": {"tribe": "Oru", "house": "Oruvan", "id": 3, "name": "Lia"}},
	{"type": "protests", "data": {"tribe": "Oru", "id": 3, "name": "Lia", "grievance": "the arrests"}},
	{"type": "protests_faded", "data": {"tribe": "Oru"}},
	{"type": "concession", "data": {"tribe": "Oru", "id": 3, "name": "Lia", "law": "taxation"}},
	{"type": "concession", "data": {"tribe": "Oru", "id": 3, "name": "Lia"}},
	{"type": "crackdown", "data": {"tribe": "Oru", "id": 3, "name": "Lia", "count": 2, "names": "Rin and Bo"}},
	{"type": "crackdown", "data": {"tribe": "Oru", "id": 3, "name": "Lia", "count": 0, "names": ""}},
	{"type": "revolution", "data": {"tribe": "Oru", "leader": 4, "leader_name": "Rin", "deaths": 2, "old": "Lia", "old_id": 3}},
	{"type": "uprising_crushed", "data": {"tribe": "Oru", "deaths": 1, "leader": 4, "leader_name": "Rin"}},
	{"type": "rebels_fled", "data": {"tribe": "Vee", "from": "Oru", "people": 15}},
	{"type": "coup", "data": {"tribe": "Oru", "id": 4, "name": "Rin", "old": "Lia"}},
	{"type": "capture", "data": {"tribe": "Oru", "id": 4, "name": "Rin", "old": "Lia"}},
	{"type": "prophet", "data": {"tribe": "Oru", "id": 4, "name": "Rin"}},
	{"type": "prophet_silenced", "data": {"tribe": "Oru", "id": 4, "name": "Rin"}},
	{"type": "schism", "data": {"tribe": "Vee", "from": "Oru", "id": 4, "name": "Rin", "people": 16}},
	{"type": "reform", "data": {"tribe": "Oru", "id": 4, "name": "Rin"}},
	{"type": "succession_contested", "data": {"tribe": "Oru", "id": 4, "name": "Rin", "heir": "Lia"}},
	{"type": "succession_settled", "data": {"tribe": "Oru", "id": 3, "name": "Lia", "rival": "Rin"}},
	{"type": "succession_split", "data": {"tribe": "Vee", "from": "Oru", "name": "Rin", "people": 15}},
	{"type": "succession_war", "data": {"tribe": "Oru", "id": 4, "name": "Rin", "deaths": 3}},
	{"type": "arrest", "data": {"tribe": "Oru", "id": 4, "name": "Rin", "why": "for heresy", "months": 12}},
	{"type": "exiled", "data": {"tribe": "Oru", "id": 4, "name": "Rin", "why": "for troubling the peace", "to": "Vee"}},
	{"type": "exiled", "data": {"tribe": "Oru", "id": 4, "name": "Rin", "why": "overthrown"}},
	{"type": "election", "data": {"tribe": "Oru", "id": 4, "name": "Rin", "rigged": 1}},
	{"type": "election", "data": {"tribe": "Oru", "id": 4, "name": "Rin", "kept": 1}},
	{"type": "election", "data": {"tribe": "Oru", "id": 4, "name": "Rin", "loser": "Lia"}},
	{"type": "nobles_raised", "data": {"tribe": "Oru", "count": 2, "names": "Rin and Bo"}},
	{"type": "bondage", "data": {"tribe": "Oru", "count": 1, "names": "Kit"}},
	{"type": "freed", "data": {"tribe": "Oru", "count": 3}},
	{"type": "vassal", "data": {"tribe": "Vee", "overlord": "Oru"}},
	{"type": "vassal_revolt", "data": {"tribe": "Vee", "overlord": "Oru", "won": 1}},
	{"type": "vassal_revolt", "data": {"tribe": "Vee", "overlord": "Oru", "won": 0}},
	{"type": "annexed", "data": {"tribe": "Oru", "from": "Vee", "people": 12}},
]


func _check(event: Dictionary) -> void:
	var line := EventText.text(event)
	var type := String(event["type"])
	assert_true(line.length() > 8, "%s reads as a sentence: '%s'" % [type, line])
	assert_ne(line, type.replace("_", " "), "%s has its own wording" % type)
	assert_true(not line.contains("%s") and not line.contains("%d"), "%s fills every blank: %s" % [type, line])
	assert_true(not line.contains("  ") and not line.contains(" .") and not line.contains(" ,"), "%s has no empty names: '%s'" % [type, line])
	assert_true(EventText.TYPE_CATEGORY.has(type), "%s has a feed category" % type)


func test_every_logged_type_has_words() -> void:
	var types := {}
	for event: Dictionary in SAMPLES:
		types[event["type"]] = true
		_check({"id": 0, "tick": 0, "type": event["type"], "data": event["data"]})
	for type: String in EventText.TYPE_CATEGORY:
		assert_true(types.has(type), "a sample of %s" % type)


func test_a_real_world_reads_well() -> void:
	var sim := Simulation.create(3)
	var seen := -1
	var types := {}
	for year: int in 30:
		sim.advance(WorldState.DAYS_PER_YEAR)
		for event: Dictionary in sim.state.events:
			if int(event["id"]) > seen:
				types[event["type"]] = true
				_check(event)
		seen = sim.state.next_event_id - 1
	assert_true(types.size() >= 10, "a varied history: %s" % str(types.keys()))


func test_major_events_are_the_turns_of_history() -> void:
	assert_true(EventText.is_major({"type": "war", "data": {}}))
	assert_true(not EventText.is_major({"type": "birth", "data": {}}))
	assert_true(EventText.is_major({"type": "death", "data": {"chief": 1, "cause": "old age"}}), "a chief's death")
	assert_true(not EventText.is_major({"type": "death", "data": {"cause": "old age"}}))
	assert_eq(EventText.category({"type": "marriage", "data": {}}), "love")
