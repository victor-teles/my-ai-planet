extends TestCase

var schema: Dictionary = AIAssets.schema("prophecy")


func _valid() -> Dictionary:
	return {"text": "The river will split the people.", "metric": "tribe_count", "op": ">=", "value": 2.0, "years_from_now": 40.0}


func test_accepts_valid_reply() -> void:
	assert_eq(JsonSchema.validate(_valid(), schema), PackedStringArray())


func test_rejects_missing_and_extra_keys() -> void:
	var reply := _valid()
	reply.erase("metric")
	reply["mood"] = "dark"
	var errors := JsonSchema.validate(reply, schema)
	assert_eq(errors.size(), 2, str(errors))


func test_rejects_bad_enum_range_and_fraction() -> void:
	var reply := _valid()
	reply["op"] = "=="
	reply["years_from_now"] = 9000.0
	reply["value"] = 2.5
	assert_eq(JsonSchema.validate(reply, schema).size(), 3)


func test_wire_schema_moves_limits_into_description() -> void:
	var wire := JsonSchema.to_wire(schema)
	var years: Dictionary = wire["properties"]["years_from_now"]
	assert_true(not years.has("minimum") and not years.has("maximum"), "limits stripped")
	assert_true(String(years["description"]).contains("minimum 5"), "limits described")
	assert_eq(wire["additionalProperties"], false)
