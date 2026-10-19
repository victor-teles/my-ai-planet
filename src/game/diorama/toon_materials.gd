class_name ToonMaterials
extends RefCounted
## Shared toon materials, one per color and style, so hundreds of props reuse a few materials.

const TOON_SHADER := preload("res://art/shaders/toon.gdshader")
const OUTLINE_SHADER := preload("res://art/shaders/outline.gdshader")
const CLOUD_SHADER := preload("res://art/shaders/cloud.gdshader")
const BRUSH_STROKES := preload("res://art/textures/brush_strokes.png")
const INK := Color(0.16, 0.10, 0.20)

static var _cache: Dictionary = {}
static var _dryness := 0.0
static var _snow := 0.0
static var _rim := Color(1.0, 0.80, 0.62)


## outline_width 0 means no outline. vegetation materials respond to drought.
static func get_material(tint: Color, outline_width: float = 0.03, vegetation: bool = false, texture: Texture2D = null) -> ShaderMaterial:
	var key := "%s|%s|%s|%s" % [tint.to_html(), outline_width, vegetation, texture.resource_path if texture else ""]
	if _cache.has(key):
		return _cache[key]
	var material := ShaderMaterial.new()
	material.shader = TOON_SHADER
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("brush_strokes", BRUSH_STROKES)
	material.set_shader_parameter("snow", _snow)
	material.set_shader_parameter("rim_color", _rim)
	if texture:
		material.set_shader_parameter("albedo_texture", texture)
	if outline_width > 0.0:
		var outline := ShaderMaterial.new()
		outline.shader = OUTLINE_SHADER
		outline.set_shader_parameter("color", INK)
		outline.set_shader_parameter("width", outline_width)
		material.next_pass = outline
	if vegetation:
		material.set_meta("vegetation", true)
		material.set_shader_parameter("dryness", _dryness)
	_cache[key] = material
	return material


## Just the ink outline, for a separate hull mesh (see Kit): flat-shaded models crack the hull otherwise.
static func outline(width: float) -> ShaderMaterial:
	var key := "outline|%s" % width
	if not _cache.has(key):
		var material := ShaderMaterial.new()
		material.shader = OUTLINE_SHADER
		material.set_shader_parameter("color", INK)
		material.set_shader_parameter("width", width)
		_cache[key] = material
	return _cache[key]


static func cloud() -> ShaderMaterial:
	if not _cache.has("cloud"):
		var material := ShaderMaterial.new()
		material.shader = CLOUD_SHADER
		_cache["cloud"] = material
	return _cache["cloud"]


static func emissive(tint: Color, glow: Color) -> ShaderMaterial:
	var material := get_material(tint, 0.0).duplicate() as ShaderMaterial
	material.set_shader_parameter("emission_color", glow)
	material.set_shader_parameter("snow", 0.0)
	return material


## Sets drought dryness on every vegetation material, including the island's.
static func set_dryness(value: float) -> void:
	if value == _dryness:
		return
	_dryness = value
	for material: ShaderMaterial in _cache.values():
		if material.has_meta("vegetation"):
			material.set_shader_parameter("dryness", value)


## Lays winter snow on every toon surface that faces the sky: ground, leaves, roofs and tents.
static func set_snow(value: float) -> void:
	if value == _snow:
		return
	_snow = value
	for material: ShaderMaterial in _cache.values():
		if material.shader == TOON_SHADER:
			material.set_shader_parameter("snow", value)


## The rim light's color on every toon surface: warm at dusk, cold and grey as the world darkens.
static func set_rim(value: Color) -> void:
	if value == _rim:
		return
	_rim = value
	for material: ShaderMaterial in _cache.values():
		if material.shader == TOON_SHADER:
			material.set_shader_parameter("rim_color", value)
