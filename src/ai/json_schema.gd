class_name JsonSchema
extends RefCounted
## Small JSON Schema validator for the subset our AI schemas use:
## type, properties, required, additionalProperties, items, enum,
## minimum, maximum, minLength, maxLength, minItems, maxItems, description.

## Keywords many providers reject in structured-output schemas. We strip them before
## sending (see to_wire) and still enforce them locally with validate().
const LOCAL_ONLY_KEYWORDS: Array[String] = ["minimum", "maximum", "minLength", "maxLength", "minItems", "maxItems"]


## Returns a list of problems; empty means valid.
static func validate(value: Variant, schema: Dictionary, path: String = "$") -> PackedStringArray:
	var errors := PackedStringArray()
	if schema.has("type") and not _matches_type(value, String(schema["type"])):
		errors.append("%s: expected %s" % [path, schema["type"]])
		return errors
	if schema.has("enum") and value not in schema["enum"]:
		errors.append("%s: %s is not one of %s" % [path, value, schema["enum"]])
	if value is float or value is int:
		if schema.has("minimum") and value < schema["minimum"]:
			errors.append("%s: %s is below %s" % [path, value, schema["minimum"]])
		if schema.has("maximum") and value > schema["maximum"]:
			errors.append("%s: %s is above %s" % [path, value, schema["maximum"]])
	elif value is String:
		var length: int = (value as String).length()
		if schema.has("minLength") and length < schema["minLength"]:
			errors.append("%s: shorter than %s" % [path, schema["minLength"]])
		if schema.has("maxLength") and length > schema["maxLength"]:
			errors.append("%s: longer than %s" % [path, schema["maxLength"]])
	elif value is Dictionary:
		errors.append_array(_validate_object(value, schema, path))
	elif value is Array:
		var items: Array = value
		if schema.has("minItems") and items.size() < schema["minItems"]:
			errors.append("%s: fewer than %s items" % [path, schema["minItems"]])
		if schema.has("maxItems") and items.size() > schema["maxItems"]:
			errors.append("%s: more than %s items" % [path, schema["maxItems"]])
		if schema.has("items"):
			for i: int in items.size():
				errors.append_array(validate(items[i], schema["items"], "%s[%d]" % [path, i]))
	return errors


static func _validate_object(object: Dictionary, schema: Dictionary, path: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var properties: Dictionary = schema.get("properties", {})
	for key: Variant in schema.get("required", []):
		if not object.has(key):
			errors.append("%s: missing '%s'" % [path, key])
	for key: Variant in object:
		if properties.has(key):
			errors.append_array(validate(object[key], properties[key], "%s.%s" % [path, key]))
		elif schema.get("additionalProperties", true) == false:
			errors.append("%s: unexpected '%s'" % [path, key])
	return errors


static func _matches_type(value: Variant, type: String) -> bool:
	match type:
		"object":
			return value is Dictionary
		"array":
			return value is Array
		"string":
			return value is String
		"boolean":
			return value is bool
		"number":
			return value is float or value is int
		"integer":
			# JSON parsing gives floats, so accept whole floats as integers.
			return value is int or (value is float and is_equal_approx(value, roundf(value)))
		"null":
			return value == null
	return false


## Copy of the schema that is safe to send to providers: local-only keywords are removed
## and described in the description instead, so the model still knows the limits.
static func to_wire(schema: Dictionary) -> Dictionary:
	var wire := {}
	var limits := PackedStringArray()
	for key: String in schema:
		var value: Variant = schema[key]
		if key in LOCAL_ONLY_KEYWORDS:
			limits.append("%s %s" % [key, value])
		elif key == "properties":
			var properties := {}
			for property: String in value:
				properties[property] = to_wire(value[property])
			wire[key] = properties
		elif key == "items":
			wire[key] = to_wire(value)
		else:
			wire[key] = value
	if not limits.is_empty():
		var description := String(wire.get("description", ""))
		wire["description"] = (description + " " if description else "") + "(" + ", ".join(limits) + ")"
	return wire


## Wire schema for OpenAI-style strict mode, which needs every object to list all of its
## properties as required and to forbid extra ones. Optional properties become nullable;
## drop_optional_nulls() removes those nulls again before the reply is validated.
static func to_strict_wire(schema: Dictionary) -> Dictionary:
	return _strictify(to_wire(schema))


static func _strictify(wire: Dictionary) -> Dictionary:
	if wire.has("items"):
		wire["items"] = _strictify(wire["items"])
	if not wire.has("properties"):
		return wire
	var properties: Dictionary = wire["properties"]
	var required: Array = wire.get("required", [])
	for key: String in properties:
		var property: Dictionary = _strictify(properties[key])
		if key not in required and property.has("type"):
			property["type"] = [property["type"], "null"]
			if property.has("enum"):
				property["enum"] = (property["enum"] as Array) + [null]
		properties[key] = property
	wire["required"] = properties.keys()
	wire["additionalProperties"] = false
	return wire


## Removes null values the schema doesn't require (the strict-mode stand-in for "left out").
static func drop_optional_nulls(value: Variant, schema: Dictionary) -> Variant:
	if value is Array and schema.has("items"):
		var items: Array = []
		for item: Variant in value:
			items.append(drop_optional_nulls(item, schema["items"]))
		return items
	if not value is Dictionary:
		return value
	var properties: Dictionary = schema.get("properties", {})
	var required: Array = schema.get("required", [])
	var object := {}
	for key: Variant in value:
		if value[key] == null and key not in required:
			continue
		object[key] = drop_optional_nulls(value[key], properties[key]) if properties.has(key) else value[key]
	return object
