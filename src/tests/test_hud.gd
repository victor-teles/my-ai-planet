extends TestCase
## The HUD's pieces: the prophecy in plain words, the miracle bar's reasons, the icons, and the
## top bar fitting the smallest screen (1152x648) without its groups running into each other.


func test_every_prophecy_reads_as_a_plain_goal() -> void:
	for metric: String in Prophecy.METRICS:
		for op: String in Prophecy.OPERATORS:
			var prophecy := Prophecy.new()
			prophecy.metric = metric
			prophecy.op = op
			prophecy.target = 2
			prophecy.deadline_year = 135
			var goal := ProphecyCard.goal_text(prophecy)
			assert_true(goal.ends_with("before year 135"), "%s %s: %s" % [metric, op, goal])
			assert_true(not goal.contains("_"), "%s %s reads as words: %s" % [metric, op, goal])
			assert_true(not ProphecyCard.amount_text(metric, 2).contains("_"), metric)


func test_population_goal_says_the_number() -> void:
	var prophecy := Prophecy.new()
	prophecy.metric = "total_population"
	prophecy.op = "<="
	prophecy.target = 286
	prophecy.deadline_year = 135
	assert_eq(ProphecyCard.goal_text(prophecy), "Fall to 286 people or fewer before year 135")
	prophecy.metric = "highest_age"
	prophecy.op = ">="
	prophecy.target = 1
	assert_eq(ProphecyCard.goal_text(prophecy), "Reach the Age of Bronze before year 135")


func test_miracle_bar_says_why_a_miracle_cannot_be_cast() -> void:
	var state := Simulation.create(7).state
	var bar := MiracleBar.new()
	state.influence = 10.0
	bar.show_state(state, "", true, 0.0)
	assert_eq(bar.reason_for("rain"), "", "rain falls on the whole island")
	assert_true(bar.reason_for("harvest").begins_with("Choose a tribe first"), bar.reason_for("harvest"))
	bar.show_state(state, state.tribe_names[0], true, 0.0)
	assert_eq(bar.reason_for("harvest"), "", "a tribe is chosen")
	state.influence = 1.0
	bar.show_state(state, state.tribe_names[0], true, 0.0)
	assert_true(bar.reason_for("harvest").begins_with("Not enough Influence: it costs 2"), bar.reason_for("harvest"))
	bar.show_state(state, state.tribe_names[0], false, 0.0)
	assert_true(not bar.reason_for("rain").is_empty(), "nothing is cast while time waits")
	bar.free()


func test_every_icon_rasterizes_crisp() -> void:
	for icon_name: String in UiIcons.SHAPES:
		var texture := UiIcons.texture(icon_name, 20)
		assert_eq(texture.get_height(), 20, "%s reports its logical size" % icon_name)
		var image := Image.new()
		assert_eq(image.load_svg_from_string(UiIcons.svg(icon_name), UiIcons.OVERSAMPLE), OK, "%s is valid SVG" % icon_name)
		assert_true(not image.is_empty() and not image.is_invisible(), "%s has something drawn" % icon_name)


func test_top_bar_fits_the_smallest_screen() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var state := Simulation.create(7).state
	var bar := TopBar.new()
	bar.theme = UiStyle.theme()
	bar.speeds = [2.0, 6.0, 20.0, 60.0, 180.0]
	tree.root.add_child(bar)
	bar.show_time(state, false, 1, "")
	bar.show_island(state, "Age of Bronze", [])
	var view := Vector2(1152, 648)
	for frame: int in 3:
		bar.arrange(view, 12.0)
		await tree.process_frame
	var rects := bar.plaque_rects()
	for rect: Rect2 in rects:
		assert_true(rect.position.x >= 0.0 and rect.end.x <= view.x, "inside the screen: %s" % rect)
	assert_true(rects[0].end.x <= rects[1].position.x, "time and island apart: %s %s" % [rects[0], rects[1]])
	assert_true(rects[1].end.x <= rects[2].position.x, "island and buttons apart: %s %s" % [rects[1], rects[2]])
	bar.queue_free()
