class_name Kit
extends RefCounted
## Props from Kenney's Nature Kit and Survival Kit (CC0, art/props/kenney/), restyled to match
## the world: every material becomes a toon material in the art bible's palette (looked up by
## the kit's material name), and each model gets an ink outline hull with smoothed normals,
## since the kit's flat-shaded models would crack an ordinary inverted hull.

const DIR := "res://art/props/kenney/"
const OUTLINE_WIDTH := 0.012 ## in the model's own units (about meters)
## Kit material name -> [color, reacts to drought]. Names not listed keep the kit's color.
const PALETTE := {
	"leafsGreen": [Color(0.50, 0.72, 0.34), true],
	"leafsDark": [Color(0.20, 0.48, 0.44), true],
	"grass": [Color(0.42, 0.68, 0.34), true],
	"woodBark": [Color(0.45, 0.30, 0.24), false],
	"woodBarkDark": [Color(0.36, 0.24, 0.20), false],
	"woodInner": [Color(0.86, 0.70, 0.50), false],
	"wood": [Color(0.66, 0.46, 0.30), false],
	"woodDark": [Color(0.48, 0.32, 0.22), false],
	"dirt": [Color(0.62, 0.56, 0.62), false], # rock bodies take the art bible's stone
	"stone": [Color(0.62, 0.56, 0.62), false],
	"colorRed": [Color(0.86, 0.36, 0.32), false],
	"colorRedDark": [Color(0.70, 0.28, 0.26), false],
	"colorYellow": [Color(0.98, 0.82, 0.40), false],
	"colorPurple": [Color(0.72, 0.58, 0.92), false],
	"colorTan": [Color(0.90, 0.76, 0.58), false],
	"_defaultMat": [Color(0.95, 0.92, 0.86), false],
}
## Canvas materials on tents, which take the tribe's color.
const CANVAS: Array[String] = ["colorRed", "colorRedDark"]

static var _templates: Dictionary = {} ## model name -> restyled model, packed so copies are cheap
static var _hulls: Dictionary = {} ## Mesh -> the same mesh with smoothed normals


## A copy of a kit model, restyled. With height > 0 it is scaled to stand that tall.
## canvas recolors tent canvas (a darker shade goes on the shaded panels).
static func prop(model_name: String, height: float = 0.0, canvas: Color = Color.TRANSPARENT) -> Node3D:
	if not _templates.has(model_name):
		var restyled := _restyle((load(DIR + model_name + ".glb") as PackedScene).instantiate() as Node3D)
		var packed := PackedScene.new()
		packed.pack(restyled)
		packed.set_meta("height", restyled.get_meta("height"))
		restyled.free()
		_templates[model_name] = packed
	var copy := (_templates[model_name] as PackedScene).instantiate() as Node3D
	if canvas.a > 0.0:
		_recolor_canvas(copy, canvas)
	if height > 0.0:
		copy.scale = Vector3.ONE * height / maxf(_height_of(model_name), 0.001)
	return copy


static func _height_of(model_name: String) -> float:
	return float((_templates[model_name] as PackedScene).get_meta("height"))


static func _restyle(root: Node3D) -> Node3D:
	var top := -INF
	var bottom := INF
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var mesh := instance.mesh
		for surface: int in mesh.get_surface_count():
			instance.set_surface_override_material(surface, _toon(mesh.surface_get_material(surface)))
		var hull := MeshInstance3D.new()
		hull.mesh = _smoothed(mesh)
		hull.material_override = ToonMaterials.outline(OUTLINE_WIDTH)
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.add_child(hull)
		hull.owner = root # so it is saved when the model is packed
		var box := instance.transform * mesh.get_aabb()
		top = maxf(top, box.end.y)
		bottom = minf(bottom, box.position.y)
	root.set_meta("height", top - bottom)
	return root


static func _toon(source: Material) -> Material:
	var standard := source as BaseMaterial3D
	if standard == null:
		return ToonMaterials.get_material(Color.WHITE, 0.0)
	var entry: Array = PALETTE.get(standard.resource_name, [standard.albedo_color, false])
	var toon := ToonMaterials.get_material(entry[0], 0.0, entry[1], standard.albedo_texture)
	toon.set_meta("kit_name", standard.resource_name)
	return toon


static func _recolor_canvas(root: Node3D, canvas: Color) -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		for surface: int in instance.get_surface_override_material_count():
			var material := instance.get_surface_override_material(surface)
			if material and String(material.get_meta("kit_name", "")) in CANVAS:
				var dark := String(material.get_meta("kit_name")) == "colorRedDark"
				var tint := canvas.darkened(0.18) if dark else canvas
				instance.set_surface_override_material(surface, ToonMaterials.get_material(tint, 0.0))


## The same triangles with every corner's normal averaged over all faces meeting at that point,
## so the outline hull pushes out evenly instead of splitting along hard edges.
static func _smoothed(mesh: Mesh) -> ArrayMesh:
	if _hulls.has(mesh):
		return _hulls[mesh]
	var smooth := ArrayMesh.new()
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var sums := {}
		for v: int in vertices.size():
			var key := vertices[v].snappedf(0.0001)
			sums[key] = sums.get(key, Vector3.ZERO) + normals[v]
		var averaged := PackedVector3Array()
		averaged.resize(vertices.size())
		for v: int in vertices.size():
			averaged[v] = (sums[vertices[v].snappedf(0.0001)] as Vector3).normalized()
		var hull_arrays := []
		hull_arrays.resize(Mesh.ARRAY_MAX)
		hull_arrays[Mesh.ARRAY_VERTEX] = vertices
		hull_arrays[Mesh.ARRAY_NORMAL] = averaged
		hull_arrays[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
		smooth.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, hull_arrays)
	_hulls[mesh] = smooth
	return smooth
