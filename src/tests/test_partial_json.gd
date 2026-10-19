extends TestCase

const FULL := "{\"title\": \"The \\\"text\\\" War\", \"text\": \"Line one,\\nthe \\\"Magavik\\\" said \\\\o/ caf\\u00e9 \\ud83d\\ude00 end.\", \"causes\": [\"a\"]}"
const STORY := "Line one,\nthe \"Magavik\" said \\o/ café 😀 end."


func test_reads_a_whole_reply() -> void:
	assert_eq(JSON.parse_string(FULL)["text"], STORY, "the fixture itself is valid JSON")
	assert_eq(PartialJson.string_field(FULL, "text"), STORY)
	assert_eq(PartialJson.string_field(FULL, "title"), "The \"text\" War")


func test_every_truncation_is_a_clean_prefix() -> void:
	var longest := ""
	for n: int in FULL.length() + 1:
		var story := PartialJson.string_field(FULL.left(n), "text")
		assert_true(STORY.begins_with(story), "cut at %d: '%s'" % [n, story])
		assert_true(story.length() >= longest.length(), "never shrinks (cut at %d)" % n)
		longest = story
	assert_eq(longest, STORY)


func test_truncated_escapes_wait_for_the_rest() -> void:
	assert_eq(PartialJson.string_field("{\"text\": \"a\\", "text"), "a")
	assert_eq(PartialJson.string_field("{\"text\": \"a\\u00", "text"), "a")
	assert_eq(PartialJson.string_field("{\"text\": \"a\\u00e9", "text"), "aé")
	assert_eq(PartialJson.string_field("{\"text\": \"a\\ud83d", "text"), "a", "half a surrogate pair")
	assert_eq(PartialJson.string_field("{\"text\": \"a\\ud83d\\ude", "text"), "a")


func test_before_the_field_there_is_nothing() -> void:
	for raw: String in ["", "```json\n", "{", "{\"tit", "{\"title\": \"The te", "{\"title\": \"A\", \"te", "{\"title\": \"A\", \"text\"", "{\"title\": \"A\", \"text\":  "]:
		assert_eq(PartialJson.string_field(raw, "text"), "", raw)


func test_only_the_top_level_field_counts() -> void:
	assert_eq(PartialJson.string_field("{\"causes\": [{\"text\": \"no\"}], \"text\": \"yes\"}", "text"), "yes")
	assert_eq(PartialJson.string_field("{\"causes\": [{\"text\": \"no\"}]}", "text"), "")
	assert_eq(PartialJson.string_field("{\"title\": \"text\", \"text\": \"yes\"}", "text"), "yes", "a value that looks like the key")
	assert_eq(PartialJson.string_field("Sure! ```json\n{\"text\": \"fenced", "text"), "fenced")
	assert_eq(PartialJson.string_field("{\"text\": 42}", "text"), "", "not a string")
