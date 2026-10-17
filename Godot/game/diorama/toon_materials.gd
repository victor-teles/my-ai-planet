class_name ToonMaterials
extends RefCounted
## Shared toon materials, one per color and style, so hundreds of props reuse a few materials.

const TOON_SHADER := preload("res://art/shaders/toon.gdshader")
const OUTLINE_SHADER := preload("res://art/shaders/outline.gdshader")
const CLOUD_SHADER := preload("res://art/shaders/cloud.gdshader")
const BRUSH_STROKES := preload("res://art/textures/brush_strokes.png")
const INK := Color(0.16, 0.10, 0.20)

static var _cache: Dictionary = {}


## outline_width 0 means no outline. vegetation materials respond to drought.
static func get_material(tint: Color, outline_width: float = 0.03, vegetation: bool = false) -> ShaderMaterial:
	var key := "%s|%s|%s" % [tint.to_html(), outline_width, vegetation]
	if _cache.has(key):
		return _cache[key]
	var material := ShaderMaterial.new()
	material.shader = TOON_SHADER
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("brush_strokes", BRUSH_STROKES)
	if outline_width > 0.0:
		var outline := ShaderMaterial.new()
		outline.shader = OUTLINE_SHADER
		outline.set_shader_parameter("color", INK)
		outline.set_shader_parameter("width", outline_width)
		material.next_pass = outline
	if vegetation:
		material.set_meta("vegetation", true)
	_cache[key] = material
	return material


static func cloud() -> ShaderMaterial:
	if not _cache.has("cloud"):
		var material := ShaderMaterial.new()
		material.shader = CLOUD_SHADER
		_cache["cloud"] = material
	return _cache["cloud"]


static func emissive(tint: Color, glow: Color) -> ShaderMaterial:
	var material := get_material(tint, 0.0).duplicate() as ShaderMaterial
	material.set_shader_parameter("emission_color", glow)
	return material


## Sets drought dryness on every vegetation material, including the island's.
static func set_dryness(value: float) -> void:
	for material: ShaderMaterial in _cache.values():
		if material.has_meta("vegetation"):
			material.set_shader_parameter("dryness", value)
