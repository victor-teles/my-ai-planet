extends TestCase
## Which sim changes drop a villager's current walk. No scene tree: Settlement.interrupts is pure.
## Job and home are not arguments. A job string that is not an activity does not interrupt when
## the activity passed on both sides is unchanged; only the caller would have changed the job.


func test_soft_changes_finish_the_trip() -> void:
	assert_eq(Settlement.interrupts("working", "idle", false, false, 0.0), false, "working to idle")
	assert_eq(Settlement.interrupts("working", "teaching", false, false, 0.0), false, "working to teaching")
	assert_eq(Settlement.interrupts("playing", "mourning", false, false, 0.0), false, "playing to mourning")
	assert_eq(Settlement.interrupts("working", "working", false, false, 0.0), false, "same activity, job would differ outside")
	assert_eq(Settlement.interrupts("woodcutter", "woodcutter", false, false, 0.0), false, "a job string is not an activity")


func test_hard_changes_replan() -> void:
	assert_eq(Settlement.interrupts("working", "sick", false, false, 0.0), true, "becoming sick")
	assert_eq(Settlement.interrupts("working", "infant", false, false, 0.0), true, "becoming an infant")
	assert_eq(Settlement.interrupts("working", "resting", false, false, 0.0), true, "childbirth soon")
	assert_eq(Settlement.interrupts("working", "working", false, true, 0.0), true, "detained flipping on")
	assert_eq(Settlement.interrupts("working", "working", true, false, 0.0), true, "becoming un-detained")
	assert_eq(Settlement.interrupts("working", "working", false, false, 0.1), true, "dying")
	assert_eq(Settlement.interrupts("sick", "working", false, false, 0.0), true, "getting up is a new plan")
