class_name Props
extends RefCounted
## Builds small toon props from primitive meshes. Placeholder geometry with the final shading,
## so the look can be judged now and painted assets can replace these one by one.

const PINE := Color(0.20, 0.48, 0.44)
const LEAF := Color(0.50, 0.72, 0.34)
const BARK := Color(0.45, 0.30, 0.24)
const THATCH := Color(0.86, 0.62, 0.36)
const HUT_WALL := Color(0.70, 0.50, 0.40)
const SKIN := Color(0.96, 0.78, 0.62)
const STONE := Color(0.62, 0.56, 0.62)


static func pine(scale: float) -> Node3D:
	var root := Node3D.new()
	root.add_child(_part(_cylinder(0.08, 0.1, 0.5), ToonMaterials.get_material(BARK), Vector3(0, 0.25, 0)))
	for layer: int in 3:
		var radius := 0.55 - layer * 0.13
		var cone := _cylinder(0.0, radius, 0.7)
		root.add_child(_part(cone, ToonMaterials.get_material(PINE, 0.025, true), Vector3(0, 0.75 + layer * 0.38, 0)))
	root.scale = Vector3.ONE * scale
	return root


static func round_tree(scale: float) -> Node3D:
	var root := Node3D.new()
	root.add_child(_part(_cylinder(0.07, 0.1, 0.8), ToonMaterials.get_material(BARK), Vector3(0, 0.4, 0)))
	root.add_child(_part(_sphere(0.5), ToonMaterials.get_material(LEAF, 0.025, true), Vector3(0, 1.05, 0)))
	root.add_child(_part(_sphere(0.32), ToonMaterials.get_material(LEAF, 0.025, true), Vector3(0.3, 0.85, 0.15)))
	root.scale = Vector3.ONE * scale
	return root


static func rock(scale: float) -> Node3D:
	var root := Node3D.new()
	var mesh := _sphere(0.4)
	root.add_child(_part(mesh, ToonMaterials.get_material(STONE), Vector3(0, 0.1, 0), Vector3(1.0, 0.6, 0.8)))
	root.scale = Vector3.ONE * scale
	return root


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


static func hut(roof_color: Color) -> Node3D:
	var root := Node3D.new()
	root.add_child(_part(_cylinder(0.32, 0.36, 0.4), ToonMaterials.get_material(HUT_WALL), Vector3(0, 0.2, 0)))
	root.add_child(_part(_cylinder(0.0, 0.52, 0.55), ToonMaterials.get_material(roof_color), Vector3(0, 0.67, 0)))
	return root


static func person(tunic: Color) -> Node3D:
	var root := Node3D.new()
	var body := _part(_capsule(0.09, 0.3), ToonMaterials.get_material(tunic, 0.015), Vector3(0, 0.15, 0))
	body.name = "Body"
	root.add_child(body)
	var head := _part(_sphere(0.085, 16, 8), ToonMaterials.get_material(SKIN, 0.015), Vector3(0, 0.38, 0))
	head.name = "Head"
	root.add_child(head)
	return root


static func campfire() -> Node3D:
	var root := Node3D.new()
	for i: int in 6:
		var angle := TAU * i / 6.0
		root.add_child(_part(_sphere(0.07, 8, 4), ToonMaterials.get_material(STONE, 0.012), Vector3(cos(angle) * 0.2, 0.03, sin(angle) * 0.2)))
	var flame := _part(_cylinder(0.0, 0.13, 0.32), ToonMaterials.emissive(Color(1.0, 0.6, 0.2), Color(1.0, 0.45, 0.1) * 2.5), Vector3(0, 0.16, 0))
	flame.name = "Flame"
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


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 2
	return mesh
