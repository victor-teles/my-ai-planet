class_name Props
extends RefCounted
## The island's props: trees, rocks, undergrowth, tents and campfires from Kenney's kits
## (see Kit), plus painted clouds and the fire's flame and light.

const LINEN := Color(0.90, 0.84, 0.72)
const PINES: Array[String] = ["tree_pineRoundA", "tree_pineRoundC", "tree_pineRoundE", "tree_pineTallA_detailed", "tree_pineTallC_detailed"]
const LEAFY: Array[String] = ["tree_oak", "tree_default", "tree_detailed", "tree_fat", "tree_oak_dark", "tree_default_dark"]
const ROCKS: Array[String] = ["rock_largeA", "rock_largeC", "rock_largeE", "rock_smallA", "rock_smallC", "rock_tallA"]
const UNDERGROWTH: Array[String] = [
	"plant_bush", "plant_bushLarge", "plant_bushDetailed", "grass_large", "grass", "grass_large",
	"flower_redA", "flower_yellowA", "flower_purpleA", "mushroom_redGroup", "mushroom_tanGroup", "log", "stump_round",
]
const STONES: Array[String] = ["stone_smallA", "stone_smallB", "stone_smallC", "stone_smallFlatA"]
const TENTS: Array[String] = ["tent_detailedOpen", "tent_smallOpen"]
const CAMP_CLUTTER: Array[String] = ["log_stack", "pot_large", "pot_small", "bedroll", "campfire-stand", "resource-wood", "stump_round"]


static func pine(rng: RandomNumberGenerator) -> Node3D:
	return Kit.prop(PINES[rng.randi_range(0, PINES.size() - 1)], rng.randf_range(1.5, 2.3))


static func leafy_tree(rng: RandomNumberGenerator) -> Node3D:
	return Kit.prop(LEAFY[rng.randi_range(0, LEAFY.size() - 1)], rng.randf_range(1.3, 1.9))


static func rock(rng: RandomNumberGenerator) -> Node3D:
	var model := ROCKS[rng.randi_range(0, ROCKS.size() - 1)]
	var node := Kit.prop(model)
	node.scale *= rng.randf_range(0.8, 1.3)
	return node


static func undergrowth(rng: RandomNumberGenerator) -> Node3D:
	var model := UNDERGROWTH[rng.randi_range(0, UNDERGROWTH.size() - 1)]
	var node := Kit.prop(model)
	node.scale *= rng.randf_range(0.6, 0.8) if model in ["log", "stump_round"] else rng.randf_range(0.9, 1.4)
	return node


static func stone(rng: RandomNumberGenerator) -> Node3D:
	var node := Kit.prop(STONES[rng.randi_range(0, STONES.size() - 1)])
	node.scale *= rng.randf_range(0.6, 0.9)
	return node


## A tent with its canvas in the tribe's color. variant picks the model.
static func tent(variant: int, canvas: Color) -> Node3D:
	return Kit.prop(TENTS[posmod(variant, TENTS.size())], 0.78, canvas)


static func camp_clutter(rng: RandomNumberGenerator) -> Node3D:
	var node := Kit.prop(CAMP_CLUTTER[rng.randi_range(0, CAMP_CLUTTER.size() - 1)])
	node.scale *= 0.8
	return node


## A cotton-ball cloud made of overlapping spheres.
static func cloud(rng: RandomNumberGenerator, size: float) -> Node3D:
	var root := Node3D.new()
	var material := ToonMaterials.cloud()
	var puffs := rng.randi_range(4, 7)
	for i: int in puffs:
		var radius := size * rng.randf_range(0.45, 0.9)
		var offset := Vector3(rng.randf_range(-1.2, 1.2) * size, rng.randf_range(-0.1, 0.35) * size, rng.randf_range(-0.6, 0.6) * size)
		root.add_child(_part(_sphere(radius, 24, 12), material, offset))
	return root


## A ring of stones around crossed logs, with a low-poly flame (three tongues) and its light.
static func campfire() -> Node3D:
	var root := Node3D.new()
	root.add_child(Kit.prop("campfire_stones", 0.0))
	root.add_child(Kit.prop("campfire_logs", 0.0))
	var flame := Node3D.new()
	flame.name = "Flame"
	flame.position.y = 0.04
	var fire := ToonMaterials.emissive(Color(1.0, 0.62, 0.2), Color(1.0, 0.45, 0.1) * 2.5)
	var core := ToonMaterials.emissive(Color(1.0, 0.9, 0.5), Color(1.0, 0.8, 0.3) * 2.5)
	for tongue: Array in [[Vector3(0.0, 0.0, 0.0), 0.11, 0.34, fire], [Vector3(0.06, 0.0, 0.03), 0.07, 0.22, fire], [Vector3(-0.05, 0.0, -0.03), 0.07, 0.25, fire], [Vector3(0.0, 0.0, 0.0), 0.05, 0.18, core]]:
		var cone := _part(_cylinder(0.0, tongue[1], tongue[2]), tongue[3], tongue[0] + Vector3(0.0, tongue[2] / 2.0, 0.0))
		(cone.mesh as CylinderMesh).radial_segments = 5
		flame.add_child(cone)
	root.add_child(flame)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.62, 0.32)
	light.light_energy = 1.6
	light.omni_range = 3.2
	light.position = Vector3(0, 0.5, 0)
	root.add_child(light)
	return root


static func _part(mesh: Mesh, material: Material, position: Vector3, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.scale = scale
	return instance


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	return mesh


static func _sphere(radius: float, segments: int = 16, rings: int = 8) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh
