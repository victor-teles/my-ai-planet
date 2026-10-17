class_name VillagerArt
extends RefCounted
## Builds villager billboards from the hand-drawn layers in art/characters/: a body with two
## walk frames, one of three hair styles, and a feathered headband for chiefs. Layers are
## combined once into a sprite sheet per look and shared by every figure with that look.

const SHADER := preload("res://art/shaders/villager.gdshader")
const BODY: Array[Texture2D] = [
	preload("res://art/characters/villager_body_a.svg"),
	preload("res://art/characters/villager_body_b.svg"),
]
const HAIR: Array[Texture2D] = [
	preload("res://art/characters/villager_hair_1.svg"),
	preload("res://art/characters/villager_hair_2.svg"),
	preload("res://art/characters/villager_hair_3.svg"),
]
const CHIEF := preload("res://art/characters/villager_chief.svg")
const HAIR_COLORS: Array[Color] = [
	Color(0.24, 0.16, 0.14), Color(0.45, 0.27, 0.17), Color(0.62, 0.30, 0.18), Color(0.80, 0.62, 0.38),
]
const SIZE := Vector2(0.48, 0.64) ## world units; the art is 96 x 128

static var _materials: Dictionary = {} ## "hair|chief" -> ShaderMaterial
static var _quad: QuadMesh


## A figure standing on its origin. Colors and the walk frame are per-instance shader parameters.
static func make_sprite(hair_style: int, chief: bool) -> MeshInstance3D:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = SIZE
		_quad.center_offset = Vector3(0.0, SIZE.y / 2.0, 0.0)
	var sprite := MeshInstance3D.new()
	sprite.mesh = _quad
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.material_override = material(hair_style, chief)
	return sprite


static func material(hair_style: int, chief: bool) -> ShaderMaterial:
	var key := "%d|%s" % [hair_style, chief]
	if not _materials.has(key):
		var shader_material := ShaderMaterial.new()
		shader_material.shader = SHADER
		shader_material.set_shader_parameter("sheet", _sheet(hair_style, chief))
		_materials[key] = shader_material
	return _materials[key]


## Both walk frames side by side, with the hair (and headband) painted over each.
static func _sheet(hair_style: int, chief: bool) -> ImageTexture:
	var layers: Array[Texture2D] = [HAIR[hair_style]]
	if chief:
		layers.append(CHIEF)
	var frame_size := BODY[0].get_size()
	var sheet := Image.create_empty(int(frame_size.x) * 2, int(frame_size.y), false, Image.FORMAT_RGBA8)
	for frame: int in BODY.size():
		var offset := Vector2i(int(frame_size.x) * frame, 0)
		for layer: Texture2D in [BODY[frame]] + layers:
			var image := layer.get_image()
			image.convert(Image.FORMAT_RGBA8)
			sheet.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), offset)
	sheet.generate_mipmaps()
	return ImageTexture.create_from_image(sheet)


## A soft ink shadow under a figure's feet, so it sits on the ground instead of floating.
static func make_shadow() -> MeshInstance3D:
	var shadow := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.34, 0.22)
	shadow.mesh = plane
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.material_override = _shadow_material()
	shadow.position.y = 0.02
	return shadow


static func _shadow_material() -> StandardMaterial3D:
	if not _materials.has("shadow"):
		var gradient := Gradient.new()
		gradient.set_color(0, Color(ToonMaterials.INK, 0.45))
		gradient.set_color(1, Color(ToonMaterials.INK, 0.0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(0.5, 0.0)
		var shadow_material := StandardMaterial3D.new()
		shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shadow_material.albedo_texture = texture
		_materials["shadow"] = shadow_material
	return _materials["shadow"]
