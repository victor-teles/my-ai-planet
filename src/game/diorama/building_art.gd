class_name BuildingArt
extends RefCounted
## What each building looks like. Tents, sheds, workbenches, barrels and fences come from
## Kenney's kits (see Kit); round huts, longhouses and the raised storehouse are built here from
## simple shapes in the art bible's colors: daub walls and thatch roofs tinted toward the tribe.
## Every model stands on its origin with its door facing +Z.
## Later ages build in stone, brick, concrete and steel, still in the painted palette: warm and
## lived-in for homes, schools and temples, colder and greyer for the buildings of control
## (barracks, watchtower, prison, statue, surveillance mast). Those models are drawn with Shapes,
## which merges all of a building's parts into one mesh, so a city of them stays cheap.

const DAUB := Color(0.80, 0.64, 0.48)
const THATCH := Color(0.86, 0.62, 0.36)
const TIMBER := Color(0.50, 0.34, 0.24)
const SOIL := Color(0.50, 0.36, 0.30)
const DOORWAY := Color(0.24, 0.16, 0.20)
const OUTLINE := 0.012
## Later ages' materials.
const STONE := Color(0.78, 0.71, 0.70)
const STONE_DARK := Color(0.58, 0.51, 0.55)
const MARBLE := Color(0.92, 0.87, 0.82)
const COLD_STONE := Color(0.62, 0.64, 0.70)
const COLD_DARK := Color(0.40, 0.42, 0.50)
const BRICK := Color(0.76, 0.42, 0.33)
const BRICK_DARK := Color(0.56, 0.31, 0.29)
const PLASTER := Color(0.94, 0.86, 0.72)
const CONCRETE := Color(0.80, 0.78, 0.77)
const TILE := Color(0.82, 0.46, 0.35)
const SLATE := Color(0.42, 0.40, 0.54)
const STEEL := Color(0.52, 0.54, 0.62)
const IRON := Color(0.28, 0.27, 0.34)
const GOLD := Color(0.98, 0.80, 0.36)
const GLASS_DARK := Color(0.28, 0.26, 0.40)
const SMOKE := Color(0.74, 0.70, 0.76)
## Glows: lamp-lit windows, embers, the warning red, a cold searchlight.
const LAMP := Color(1.0, 0.80, 0.46)
const EMBER := Color(1.0, 0.48, 0.16)
const WARNING := Color(1.0, 0.16, 0.14)
const COLD_LIGHT := Color(0.80, 0.94, 1.0)
const HULL := 0.016 ## outline width on merged models (smoothed corners push out less than flat faces)
## Footprint half-width (x), half-depth (z) and height of each later building, for building
## sites and for clearing the land around it.
const SIZES := {
	"stone_house": Vector3(0.34, 0.28, 0.75), "rowhouse": Vector3(0.53, 0.28, 1.0),
	"apartment": Vector3(0.46, 0.34, 1.75), "mine": Vector3(0.48, 0.5, 0.5),
	"smithy": Vector3(0.44, 0.38, 0.75), "school": Vector3(0.47, 0.34, 0.9),
	"temple": Vector3(0.52, 0.42, 0.95), "great_house": Vector3(0.5, 0.4, 1.15),
	"market": Vector3(0.62, 0.45, 0.45), "barracks": Vector3(0.52, 0.42, 0.75),
	"watchtower": Vector3(0.27, 0.27, 1.75), "statue": Vector3(0.28, 0.28, 1.45),
	"prison": Vector3(0.5, 0.5, 0.75), "factory": Vector3(0.62, 0.62, 2.05),
	"broadcast_tower": Vector3(0.38, 0.38, 3.1), "surveillance_mast": Vector3(0.3, 0.3, 2.3),
}
## Where the prisoners mill about inside the prison's walls, in the model's own space.
const PRISON_YARD := Vector3(0.0, 0.0, 0.2)

static var _bodies: Dictionary = {} ## type|tint|variant -> [body mesh, hull mesh, [[glow mesh, color]]]
static var _arrays: Dictionary = {} ## primitive key -> its surface arrays
static var _materials: Dictionary = {} ## glow color or "beam|color" -> material
static var _smoke_curve: Curve
static var _smoke_puff: SphereMesh
## Crop color and height through the year (month 0 is deep winter): bare, sprouting, green, golden.
const CROP_COLORS: Array[Color] = [
	Color(0.50, 0.36, 0.30), Color(0.50, 0.36, 0.30), Color(0.52, 0.66, 0.34), Color(0.46, 0.70, 0.32),
	Color(0.42, 0.68, 0.30), Color(0.48, 0.70, 0.30), Color(0.62, 0.70, 0.30), Color(0.82, 0.70, 0.30),
	Color(0.92, 0.74, 0.32), Color(0.70, 0.56, 0.32), Color(0.55, 0.42, 0.30), Color(0.50, 0.36, 0.30),
]
const CROP_HEIGHTS: Array[float] = [0.0, 0.0, 0.03, 0.06, 0.1, 0.14, 0.17, 0.19, 0.18, 0.06, 0.02, 0.0]


## A building of a type in the tribe's color. age (the tribe's age, 0 to 4) only changes the
## buildings listed by variant().
static func make(type: String, tint: Color, age: int = 0) -> Node3D:
	if SIZES.has(type):
		return _later(type, tint, variant(type, age))
	var thatch := THATCH.lerp(tint, 0.25)
	match type:
		"tent":
			return Kit.prop(Props.TENTS[0], 0.62, Props.LINEN.lerp(tint, 0.45))
		"hut":
			return _round_hut(0.3, thatch, DAUB)
		"longhouse":
			return _longhouse(thatch)
		"healer_hut":
			var hut := _round_hut(0.27, Color(0.52, 0.62, 0.40).lerp(thatch, 0.3), DAUB.lightened(0.1))
			for i: int in 3:
				var herb := Kit.prop("plant_bush", 0.0)
				herb.scale *= 0.45
				herb.position = Vector3(-0.35 + i * 0.35, 0.0, 0.42)
				hut.add_child(herb)
			var pot := Kit.prop("pot_large", 0.0)
			pot.scale *= 0.5
			pot.position = Vector3(0.38, 0.0, 0.2)
			hut.add_child(pot)
			return hut
		"storehouse":
			return _storehouse(thatch)
		"workshop":
			var shop := Node3D.new()
			var shed := Kit.prop("structure-roof", 0.62)
			shop.add_child(shed)
			var bench := Kit.prop("workbench", 0.22)
			bench.position = Vector3(0.0, 0.0, 0.05)
			shop.add_child(bench)
			var planks := Kit.prop("resource-planks", 0.06)
			planks.position = Vector3(0.42, 0.0, 0.3)
			shop.add_child(planks)
			return shop
		"shrine":
			return _shrine()
		"field":
			return _field()
		"fire":
			return Props.campfire()
	return Kit.prop("signpost", 0.3)


## A daub-walled round hut under a cone of thatch, with a dark doorway facing +Z.
static func _round_hut(radius: float, thatch: Color, walls: Color) -> Node3D:
	var hut := Node3D.new()
	var wall := CylinderMesh.new()
	wall.top_radius = radius * 0.95
	wall.bottom_radius = radius
	wall.height = radius * 0.9
	wall.radial_segments = 10
	wall.rings = 1
	hut.add_child(_part(wall, walls, Vector3(0.0, radius * 0.45, 0.0)))
	var roof := CylinderMesh.new()
	roof.top_radius = 0.0
	roof.bottom_radius = radius * 1.35
	roof.height = radius * 1.2
	roof.radial_segments = 10
	roof.rings = 1
	hut.add_child(_part(roof, thatch, Vector3(0.0, radius * 0.9 + radius * 0.58, 0.0)))
	var door := BoxMesh.new()
	door.size = Vector3(radius * 0.42, radius * 0.6, 0.04)
	hut.add_child(_part(door, DOORWAY, Vector3(0.0, radius * 0.3, radius * 0.97), 0.0))
	return hut


## A long timber hall under a ridged thatch roof, sleeping a whole clan.
static func _longhouse(thatch: Color) -> Node3D:
	var hall := Node3D.new()
	var walls := BoxMesh.new()
	walls.size = Vector3(1.05, 0.3, 0.52)
	hall.add_child(_part(walls, DAUB.darkened(0.05), Vector3(0.0, 0.16, 0.0)))
	var roof := PrismMesh.new()
	roof.size = Vector3(0.72, 0.38, 1.18)
	var top := _part(roof, thatch, Vector3(0.0, 0.3 + 0.19, 0.0))
	top.rotation.y = PI / 2.0
	hall.add_child(top)
	for x: float in [-0.5, 0.5]:
		for z: float in [-0.24, 0.24]:
			var post := CylinderMesh.new()
			post.top_radius = 0.025
			post.bottom_radius = 0.03
			post.height = 0.36
			post.radial_segments = 5
			hall.add_child(_part(post, TIMBER, Vector3(x, 0.18, z), 0.006))
	var door := BoxMesh.new()
	door.size = Vector3(0.16, 0.22, 0.04)
	hall.add_child(_part(door, DOORWAY, Vector3(0.0, 0.11, 0.27), 0.0))
	return hall


## A small granary raised on stilts away from damp and mice, with jars and barrels beside it.
static func _storehouse(thatch: Color) -> Node3D:
	var store := Node3D.new()
	for x: float in [-0.2, 0.2]:
		for z: float in [-0.2, 0.2]:
			var stilt := CylinderMesh.new()
			stilt.top_radius = 0.025
			stilt.bottom_radius = 0.03
			stilt.height = 0.2
			stilt.radial_segments = 5
			store.add_child(_part(stilt, TIMBER, Vector3(x, 0.1, z), 0.006))
	var floor := BoxMesh.new()
	floor.size = Vector3(0.55, 0.04, 0.55)
	store.add_child(_part(floor, TIMBER.lightened(0.1), Vector3(0.0, 0.21, 0.0)))
	var hut := _round_hut(0.27, thatch, DAUB.lightened(0.05))
	hut.position.y = 0.23
	store.add_child(hut)
	for spot: Array in [["barrel", Vector3(0.42, 0.0, 0.18), 0.16], ["box-large", Vector3(-0.42, 0.0, 0.22), 0.13], ["pot_large", Vector3(0.36, 0.0, -0.25), 0.0]]:
		var prop := Kit.prop(spot[0], spot[2])
		if float(spot[2]) == 0.0:
			prop.scale *= 0.5
		prop.position = spot[1]
		store.add_child(prop)
	return store


## A ring of standing stones around an altar stone.
static func _shrine() -> Node3D:
	var shrine := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 6:
		var angle := TAU * i / 6.0
		var stone := Kit.prop("rock_tallA", 0.0)
		stone.scale *= rng.randf_range(0.28, 0.38)
		stone.position = Vector3(cos(angle), 0.0, sin(angle)) * 0.45
		stone.rotation.y = rng.randf() * TAU
		shrine.add_child(stone)
	var altar := Kit.prop("stone_smallFlatA", 0.0)
	altar.scale *= 1.6
	shrine.add_child(altar)
	return shrine


## A tilled plot with rows of crops. Call set_season() to grow it through the year.
static func _field() -> Node3D:
	var field := Node3D.new()
	var soil := BoxMesh.new()
	soil.size = Vector3(1.1, 0.04, 0.8)
	field.add_child(_part(soil, SOIL, Vector3(0.0, 0.0, 0.0), 0.0))
	# Rows of little tufts, drawn as one multimesh.
	var tuft := CylinderMesh.new()
	tuft.top_radius = 0.0
	tuft.bottom_radius = 0.035
	tuft.height = 1.0
	tuft.radial_segments = 4
	tuft.rings = 1
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = tuft
	var rows := 5
	var per_row := 9
	many.instance_count = rows * per_row
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for row: int in rows:
		for k: int in per_row:
			var spot := Vector3(-0.44 + k * 0.11 + rng.randf_range(-0.02, 0.02), 0.5, -0.3 + row * 0.15)
			var shape := Basis().scaled(Vector3(1.0, rng.randf_range(0.8, 1.2), 1.0))
			many.set_instance_transform(row * per_row + k, Transform3D(shape, spot))
	var crops := MultiMeshInstance3D.new()
	crops.name = "Crops"
	crops.multimesh = many
	crops.material_override = ToonMaterials.get_material(CROP_COLORS[6], 0.0, true)
	field.add_child(crops)
	return field


## Grows a field's crops for a month of the year.
static func set_season(field: Node3D, month: int) -> void:
	var crops := field.get_node_or_null("Crops") as MultiMeshInstance3D
	if crops == null:
		return
	var height := CROP_HEIGHTS[month]
	crops.visible = height > 0.0
	crops.scale.y = maxf(height, 0.001)
	crops.position.y = 0.02
	crops.material_override = ToonMaterials.get_material(CROP_COLORS[month], 0.0, true)


## Stakes and a pile of materials, shown where something is being built. Stone buildings get a
## pile of stone, and tall ones a scaffold of poles and planks that the building rises inside.
static func building_site(type: String) -> Node3D:
	if SIZES.has(type):
		return _later_site(type)
	var site := Node3D.new()
	var span := 0.5 if type in ["tent", "hut", "healer_hut", "shrine"] else 0.65
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var stake := CylinderMesh.new()
		stake.top_radius = 0.012
		stake.bottom_radius = 0.016
		stake.height = 0.3
		stake.radial_segments = 5
		site.add_child(_part(stake, TIMBER, Vector3(corner.x * span, 0.15, corner.y * span * 0.8), 0.005))
	var pile := Kit.prop("resource-planks" if type != "shrine" else "resource-stone-large", 0.07)
	pile.position = Vector3(span + 0.18, 0.0, 0.1)
	site.add_child(pile)
	return site


static func _later_site(type: String) -> Node3D:
	var size: Vector3 = SIZES[type]
	var tall := size.z > 1.2
	var site := _shaped("site|%s" % type, Color.WHITE, "", 0.008)
	var stone := float(Buildings.TYPES[type]["stone"]) > float(Buildings.TYPES[type]["wood"])
	var pile := Kit.prop("resource-stone-large" if stone else "resource-planks", 0.09 if tall else 0.07)
	pile.position = Vector3(size.x + 0.2, 0.0, size.y * 0.5)
	site.add_child(pile)
	if tall:
		var planks := Kit.prop("resource-planks", 0.06)
		planks.position = Vector3(-size.x - 0.2, 0.0, size.y * 0.3)
		site.add_child(planks)
	return site


## Stakes at the corners of a later building; around a tall one, a scaffold up to most of its height.
static func _draw_site(s: Shapes, type: String) -> void:
	var size: Vector3 = SIZES[type]
	var tall := size.z > 1.2
	var x := size.x + 0.04
	var z := size.y + 0.04
	var height := size.z * 0.85 if tall else 0.3
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		s.cylinder(0.012, 0.016, height, TIMBER, Vector3(corner.x * x, height / 2.0, corner.y * z), 5)
	if not tall:
		return
	var levels := int(height / 0.42)
	for level: int in levels:
		var y := 0.38 + level * 0.42
		s.box(Vector3(x * 2.0 + 0.06, 0.02, 0.06), TIMBER.lightened(0.12), Vector3(0.0, y, z))
		s.box(Vector3(x * 2.0 + 0.06, 0.02, 0.06), TIMBER.lightened(0.12), Vector3(0.0, y, -z))
		s.box(Vector3(0.06, 0.02, z * 2.0 + 0.06), TIMBER.lightened(0.12), Vector3(x, y, 0.0))
		s.box(Vector3(0.06, 0.02, z * 2.0 + 0.06), TIMBER.lightened(0.12), Vector3(-x, y, 0.0))
	s.strut(Vector3(-x, 0.0, z), Vector3(x, minf(height, 0.84), z), 0.01, TIMBER)


## The wall that goes around the whole village: the palisade, or the stone wall that replaces it.
## Each segment is its own child, so the wall can be shown going up piece by piece.
static func wall(type: String, radius: float, tint: Color) -> Node3D:
	return stone_wall(radius, tint) if type == "stone_wall" else palisade(radius)


## The stone wall: crenellated stretches between round towers, with a gatehouse facing +Z
## and the tribe's banner over the gate.
static func stone_wall(radius: float, tint: Color) -> Node3D:
	var wall_node := Node3D.new()
	var segments := 24
	var length := 2.0 * radius * sin(PI / segments) + 0.04
	for i: int in segments:
		var angle := PI / 2.0 + TAU * i / segments
		var kind := "gate" if i == 0 else ("tower" if i % 6 == 3 else "wall")
		var piece := _shaped("stone_wall|%s|%.2f" % [kind, length], tint, kind, HULL)
		piece.position = Vector3(cos(angle), 0.0, sin(angle)) * radius
		piece.rotation.y = -angle + PI / 2.0
		wall_node.add_child(piece)
	return wall_node


static func _draw_wall_piece(s: Shapes, kind: String, length: float, tint: Color) -> void:
	if kind == "gate":
		for side: float in [-1.0, 1.0]:
			s.box(Vector3(0.2, 0.56, 0.2), STONE, Vector3(side * 0.27, 0.28, 0.0))
			s.box(Vector3(0.24, 0.05, 0.24), STONE_DARK, Vector3(side * 0.27, 0.585, 0.0))
			for k: int in 2:
				s.box(Vector3(0.07, 0.07, 0.24), STONE, Vector3(side * 0.27 + (k - 0.5) * 0.14, 0.645, 0.0))
			s.box(Vector3((length - 0.74) / 2.0 + 0.04, 0.36, 0.12), STONE, Vector3(side * (0.37 + (length - 0.74) / 4.0), 0.18, 0.0))
		s.box(Vector3(0.36, 0.12, 0.16), STONE_DARK, Vector3(0.0, 0.47, 0.0))
		s.box(Vector3(0.12, 0.2, 0.012), tint, Vector3(0.0, 0.36, 0.085))
		s.box(Vector3(0.05, 0.05, 0.014), GOLD, Vector3(0.0, 0.39, 0.09))
		return
	s.box(Vector3(length, 0.06, 0.17), STONE_DARK, Vector3(0.0, 0.03, 0.0))
	s.box(Vector3(length, 0.34, 0.12), STONE, Vector3(0.0, 0.2, 0.0))
	for k: int in 3:
		s.box(Vector3(0.09, 0.07, 0.13), STONE, Vector3((k - 1) * length / 3.0, 0.405, 0.0))
	if kind == "tower":
		s.cylinder(0.17, 0.19, 0.6, STONE, Vector3(0.0, 0.3, 0.0), 10)
		s.cylinder(0.2, 0.2, 0.05, STONE_DARK, Vector3(0.0, 0.625, 0.0), 10)
		s.cylinder(0.0, 0.22, 0.26, SLATE.lerp(tint, 0.3), Vector3(0.0, 0.78, 0.0), 10)
		s.box(Vector3(0.04, 0.08, 0.02), LAMP, Vector3(0.0, 0.42, 0.175), Vector3.ZERO, true)


## The palisade: sharpened stakes all around the homes, with a gate facing +Z.
static func palisade(radius: float) -> Node3D:
	var wall := Node3D.new()
	var segments := 22
	for i: int in segments:
		var angle := PI / 2.0 + TAU * i / segments
		var fence := Kit.prop("fence-doorway" if i == 0 else "fence-fortified", 0.36)
		fence.position = Vector3(cos(angle), 0.0, sin(angle)) * radius
		fence.rotation.y = -angle + PI / 2.0
		wall.add_child(fence)
	return wall


## A grave: a low mound and a stone (taller for a chief).
static func grave(rng: RandomNumberGenerator, chief: bool) -> Node3D:
	var grave := Node3D.new()
	var mound := SphereMesh.new()
	mound.radius = 0.16
	mound.height = 0.12
	mound.radial_segments = 8
	mound.rings = 4
	var earth := _part(mound, Color(0.46, 0.38, 0.34), Vector3(0.0, 0.0, 0.0), 0.006)
	earth.scale = Vector3(0.8, 0.6, 1.3)
	grave.add_child(earth)
	var stone := Kit.prop("rock_tallA" if chief else "stone_smallFlatA", 0.0)
	stone.scale *= 0.22 if chief else 0.7
	stone.position = Vector3(0.0, 0.0, -0.2)
	stone.rotation.y = rng.randf_range(-0.3, 0.3)
	if not chief:
		stone.rotation.x = -PI / 2.0 + 0.2
		stone.position.y = 0.06
	grave.add_child(stone)
	return grave


static func _part(mesh: Mesh, color: Color, position: Vector3, outline: float = OUTLINE) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = ToonMaterials.get_material(color, outline)
	part.position = position
	return part


# --- Later ages ---------------------------------------------------------------------

## Buildings whose look changes with the age: the watchtower's brazier becomes a searchlight
## once the tribe has steam. "" for everything else, so they never rebuild when the age turns.
static func variant(type: String, age: int) -> String:
	if type == "watchtower":
		return "searchlight" if age >= 3 else "brazier"
	return ""


## Turns a model's lights, smoke and moving parts on (finished) or off (still a building site).
static func set_active(model: Node3D, active: bool) -> void:
	for node: Node in model.find_children("*", "", true, false):
		if node is CPUParticles3D:
			(node as CPUParticles3D).emitting = active
		elif node is Light3D or node is BuildingMotion or node.name == "Beam":
			(node as Node3D).visible = active
			node.set_process(active)


## A later-age building: its merged body, plus kit props, lights, smoke and moving parts.
static func _later(type: String, tint: Color, look: String) -> Node3D:
	var thin := type in ["broadcast_tower", "surveillance_mast", "watchtower"]
	var model := _shaped(type, tint, look, 0.009 if thin else HULL)
	match type:
		"mine":
			_prop(model, "resource-stone-large", 0.12, Vector3(0.34, 0.0, 0.32), 0.6)
			_prop(model, "rock_smallA", 0.0, Vector3(-0.36, 0.0, 0.18), 1.0)
			_prop(model, "rock_largeC", 0.0, Vector3(0.3, 0.0, -0.32), 2.0).scale *= 0.7
		"smithy":
			_prop(model, "workbench-anvil", 0.2, Vector3(0.14, 0.0, 0.1), -0.3)
			_prop(model, "barrel", 0.13, Vector3(0.33, 0.0, 0.24), 0.0)
			_prop(model, "tool-hammer-upgraded", 0.0, Vector3(0.36, 0.02, -0.12), 1.2).rotation.z = PI / 2.0
			var coals := BuildingMotion.make(BuildingMotion.Kind.FLICKER, 0.6)
			coals.position = Vector3(-0.18, 0.205, -0.14)
			var glow := MeshInstance3D.new()
			glow.mesh = _glow_box()
			glow.scale = Vector3(0.22, 0.03, 0.16)
			glow.material_override = _glow(EMBER, 3.0)
			coals.add_child(glow)
			coals.light = _omni(EMBER, 0.8, 1.0)
			coals.light.position.y = 0.15
			coals.add_child(coals.light)
			model.add_child(coals)
		"market":
			_prop(model, "barrel", 0.14, Vector3(0.55, 0.0, 0.3), 0.3)
			_prop(model, "box-large", 0.12, Vector3(-0.56, 0.0, 0.28), 0.4)
			_prop(model, "box", 0.08, Vector3(-0.5, 0.12, 0.27), 1.1)
			_prop(model, "pot_large", 0.0, Vector3(0.18, 0.0, 0.34), 0.0).scale *= 0.45
			_prop(model, "chest", 0.08, Vector3(-0.16, 0.0, 0.36), -0.2)
		"factory":
			_prop(model, "barrel", 0.13, Vector3(0.52, 0.0, 0.5), 0.0)
			_prop(model, "box-large", 0.13, Vector3(0.36, 0.0, 0.52), 0.3)
			model.add_child(_smoke(Vector3(-0.38, 2.04, -0.48)))
		"barracks":
			_prop(model, "box-large", 0.1, Vector3(0.5, 0.0, -0.05), 0.2)
		"watchtower":
			if look == "searchlight":
				model.add_child(_searchlight(Vector3(0.0, 1.27, 0.0), 30.0, 1.9, LAMP.lerp(Color.WHITE, 0.4), BuildingMotion.Kind.SWEEP, 0.35))
			else:
				var fire := BuildingMotion.make(BuildingMotion.Kind.FLICKER, 0.8)
				fire.position = Vector3(0.0, 1.22, 0.0)
				var flame := MeshInstance3D.new()
				flame.mesh = _cone_mesh(0.0, 0.07, 0.16)
				flame.position.y = 0.08
				flame.material_override = _glow(EMBER, 3.0)
				fire.add_child(flame)
				fire.light = _omni(EMBER, 1.2, 2.4)
				fire.light.position.y = 0.2
				fire.add_child(fire.light)
				model.add_child(fire)
		"statue":
			var figure := VillagerArt.statue(ToonMaterials.get_material(COLD_STONE.lightened(0.12), 0.0006), 0.9, COLD_STONE)
			figure.position.y = 0.42
			figure.scale = Vector3.ONE * 1.5
			model.add_child(figure)
		"broadcast_tower":
			var blink := BuildingMotion.make(BuildingMotion.Kind.BLINK, 0.7, 0.45)
			for y: float in [3.08, 1.62]:
				var bulb := MeshInstance3D.new()
				bulb.mesh = _ball_mesh(0.035, 8, 4)
				bulb.position.y = y
				bulb.material_override = _glow(WARNING, 4.0)
				blink.add_child(bulb)
			var red := _omni(WARNING, 1.4, 1.6)
			red.position.y = 3.0
			blink.add_child(red)
			model.add_child(blink)
		"surveillance_mast":
			var eye := _searchlight(Vector3(0.0, 2.16, 0.0), 40.0, 3.3, COLD_LIGHT, BuildingMotion.Kind.SPIN, 0.45)
			# The head the light turns on: a red camera eye stares the other way.
			var head := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.13, 0.11, 0.17)
			head.mesh = box
			head.material_override = ToonMaterials.get_material(IRON, 0.008)
			eye.add_child(head)
			var lens := MeshInstance3D.new()
			lens.mesh = _cone_mesh(0.05, 0.05, 0.02)
			lens.rotation.x = PI / 2.0
			lens.position = Vector3(0.0, 0.0, -0.09)
			lens.material_override = _glow(WARNING, 4.0)
			eye.add_child(lens)
			model.add_child(eye)
			var leds := BuildingMotion.make(BuildingMotion.Kind.BLINK, 1.1, 0.5)
			for k: int in 3:
				var angle := TAU * k / 3.0 + 0.5
				var led := MeshInstance3D.new()
				led.mesh = _ball_mesh(0.014, 6, 3)
				led.position = Vector3(sin(angle) * 0.2, 1.8, cos(angle) * 0.2)
				led.material_override = _glow(WARNING, 4.0)
				leds.add_child(led)
			model.add_child(leds)
	return model


## A model's merged body (built once per type, color and variant, then shared), its outline
## hull and its glowing parts, under a fresh root.
static func _shaped(key: String, tint: Color, look: String, outline: float) -> Node3D:
	var cache_key := "%s|%s|%s" % [key, tint.to_html(), look]
	if not _bodies.has(cache_key):
		var s := Shapes.new()
		var parts := key.split("|")
		match parts[0]:
			"site":
				_draw_site(s, parts[1])
			"stone_wall":
				_draw_wall_piece(s, look, float(parts[2]), tint)
			_:
				_draw(s, key, tint, look)
		var body := s.solid.commit()
		var glows: Array = []
		for color: Color in s.glows:
			glows.append([(s.glows[color] as MeshParts).commit(), color])
		_bodies[cache_key] = [body, Kit.hull(body) if outline > 0.0 else null, glows]
	var cached: Array = _bodies[cache_key]
	var root := Node3D.new()
	var body_node := MeshInstance3D.new()
	body_node.name = "Body"
	body_node.mesh = cached[0]
	body_node.material_override = ToonMaterials.get_material(Color.WHITE, 0.0)
	root.add_child(body_node)
	if cached[1] != null:
		var hull := MeshInstance3D.new()
		hull.mesh = cached[1]
		hull.material_override = ToonMaterials.outline(outline)
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body_node.add_child(hull)
	for glow: Array in cached[2]:
		var lit := MeshInstance3D.new()
		lit.mesh = glow[0]
		lit.material_override = _glow(glow[1], 1.6)
		lit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(lit)
	return root


static func _draw(s: Shapes, type: String, tint: Color, look: String) -> void:
	match type:
		"stone_house":
			_draw_stone_house(s, tint)
		"rowhouse":
			_draw_rowhouse(s, tint)
		"apartment":
			_draw_apartment(s, tint)
		"mine":
			_draw_mine(s)
		"smithy":
			_draw_smithy(s, tint)
		"school":
			_draw_school(s, tint)
		"temple":
			_draw_temple(s, tint)
		"great_house":
			_draw_great_house(s, tint)
		"market":
			_draw_market(s, tint)
		"barracks":
			_draw_barracks(s, tint)
		"watchtower":
			_draw_watchtower(s, look)
		"statue":
			_draw_statue_plinth(s)
		"prison":
			_draw_prison(s)
		"factory":
			_draw_factory(s, tint)
		"broadcast_tower":
			_draw_broadcast_tower(s)
		"surveillance_mast":
			_draw_surveillance_mast(s)


## A cottage of rubble stone with dressed corners, a tiled roof and a chimney; the windows glow.
static func _draw_stone_house(s: Shapes, tint: Color) -> void:
	s.box(Vector3(0.68, 0.05, 0.56), STONE_DARK, Vector3(0.0, 0.025, 0.0))
	s.box(Vector3(0.62, 0.34, 0.5), STONE, Vector3(0.0, 0.22, 0.0))
	for x: float in [-0.3, 0.3]:
		for z: float in [-0.24, 0.24]:
			s.box(Vector3(0.07, 0.34, 0.07), MARBLE, Vector3(x, 0.22, z))
	s.prism(Vector3(0.62, 0.28, 0.76), TILE.lerp(tint, 0.2), Vector3(0.0, 0.53, 0.0), PI / 2.0)
	s.box(Vector3(0.09, 0.24, 0.1), STONE_DARK, Vector3(0.2, 0.62, -0.1))
	s.box(Vector3(0.13, 0.2, 0.03), TIMBER, Vector3(0.0, 0.15, 0.255))
	s.box(Vector3(0.18, 0.03, 0.04), STONE_DARK, Vector3(0.0, 0.265, 0.26))
	for x: float in [-0.19, 0.19]:
		s.box(Vector3(0.09, 0.09, 0.03), LAMP, Vector3(x, 0.25, 0.255), Vector3.ZERO, true)
		s.box(Vector3(0.12, 0.025, 0.04), STONE_DARK, Vector3(x, 0.195, 0.26))
	s.box(Vector3(0.03, 0.09, 0.09), GLASS_DARK, Vector3(-0.31, 0.25, 0.0))
	s.box(Vector3(0.03, 0.09, 0.09), LAMP, Vector3(0.31, 0.25, 0.0), Vector3.ZERO, true)


## A brick terrace of three narrow houses, two storeys under a slate roof, chimneys on the ridge.
static func _draw_rowhouse(s: Shapes, tint: Color) -> void:
	s.box(Vector3(1.06, 0.04, 0.54), STONE_DARK, Vector3(0.0, 0.02, 0.0))
	s.box(Vector3(1.0, 0.6, 0.5), BRICK, Vector3(0.0, 0.34, 0.0))
	s.box(Vector3(1.02, 0.025, 0.52), PLASTER, Vector3(0.0, 0.36, 0.0))
	s.box(Vector3(1.04, 0.035, 0.54), PLASTER, Vector3(0.0, 0.645, 0.0))
	s.prism(Vector3(0.56, 0.24, 1.04), SLATE.lerp(tint, 0.12), Vector3(0.0, 0.78, 0.0), PI / 2.0)
	for x: float in [-0.17, 0.17]:
		s.box(Vector3(0.025, 0.6, 0.52), BRICK_DARK, Vector3(x, 0.34, 0.0))
		s.box(Vector3(0.1, 0.28, 0.12), BRICK_DARK, Vector3(x, 0.82, 0.0))
		s.box(Vector3(0.13, 0.03, 0.15), STONE_DARK, Vector3(x, 0.97, 0.0))
		for dx: float in [-0.025, 0.025]:
			s.cylinder(0.014, 0.016, 0.05, TILE, Vector3(x + dx, 1.005, 0.0), 6)
	var doors: Array[Color] = [tint.darkened(0.3), Color(0.30, 0.44, 0.38), Color(0.52, 0.27, 0.25)]
	for k: int in 3:
		var x := -0.34 + k * 0.34
		s.box(Vector3(0.11, 0.2, 0.03), doors[k], Vector3(x - 0.06, 0.14, 0.255))
		s.box(Vector3(0.15, 0.03, 0.07), STONE, Vector3(x - 0.06, 0.015, 0.28))
		s.box(Vector3(0.09, 0.11, 0.03), LAMP if k != 1 else GLASS_DARK, Vector3(x + 0.08, 0.2, 0.255), Vector3.ZERO, k != 1)
		for dx: float in [-0.07, 0.08]:
			var lit := (k + int(dx > 0.0)) % 2 == 0
			s.box(Vector3(0.08, 0.13, 0.03), LAMP if lit else GLASS_DARK, Vector3(x + dx, 0.5, 0.255), Vector3.ZERO, lit)
			s.box(Vector3(0.08, 0.13, 0.03), GLASS_DARK, Vector3(x + dx, 0.5, -0.255))


## A five-storey block in pale painted concrete: a grid of windows, half of them lit, balconies,
## a shop front on the ground floor and a water tank and aerial on the roof.
static func _draw_apartment(s: Shapes, tint: Color) -> void:
	var wall := CONCRETE.lerp(tint, 0.14)
	s.box(Vector3(0.88, 0.3, 0.6), STONE_DARK, Vector3(0.0, 0.15, 0.0))
	s.box(Vector3(0.86, 1.3, 0.58), wall, Vector3(0.0, 0.95, 0.0))
	for i: int in 4:
		s.box(Vector3(0.88, 0.025, 0.6), wall.lightened(0.25), Vector3(0.0, 0.32 + i * 0.32, 0.0))
	s.box(Vector3(0.9, 0.06, 0.62), wall.darkened(0.15), Vector3(0.0, 1.63, 0.0))
	s.box(Vector3(0.22, 0.16, 0.2), wall, Vector3(0.2, 1.74, -0.1))
	for x: float in [-0.27, -0.17]:
		s.cylinder(0.006, 0.006, 0.1, IRON, Vector3(x, 1.71, 0.05), 4)
	s.cylinder(0.08, 0.08, 0.14, TIMBER, Vector3(-0.22, 1.83, 0.05), 8)
	s.cylinder(0.0, 0.085, 0.05, TIMBER.darkened(0.2), Vector3(-0.22, 1.925, 0.05), 8)
	s.cylinder(0.005, 0.007, 0.3, IRON, Vector3(0.3, 1.97, -0.16), 4)
	s.cylinder(0.075, 0.015, 0.03, CONCRETE.lightened(0.1), Vector3(0.14, 1.9, -0.12), 10, Vector3(0.9, 0.0, 0.0))
	# Ground floor: a door under a canopy between two lit shop windows.
	s.box(Vector3(0.15, 0.22, 0.03), GLASS_DARK, Vector3(0.0, 0.11, 0.305))
	s.box(Vector3(0.28, 0.025, 0.12), tint.darkened(0.2), Vector3(0.0, 0.25, 0.35))
	for x: float in [-0.27, 0.27]:
		s.box(Vector3(0.2, 0.13, 0.03), LAMP, Vector3(x, 0.14, 0.305), Vector3.ZERO, true)
		s.box(Vector3(0.24, 0.04, 0.08), tint, Vector3(x, 0.25, 0.33), Vector3(0.4, 0.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for row: int in 4:
		var y := 0.48 + row * 0.32
		for col: int in 4:
			var x := -0.3 + col * 0.2
			for z: float in [0.295, -0.295]:
				var lit := rng.randf() < 0.55
				s.box(Vector3(0.1, 0.14, 0.02), LAMP if lit else GLASS_DARK, Vector3(x, y, z), Vector3.ZERO, lit)
			if col == 0 or col == 3:
				s.box(Vector3(0.17, 0.025, 0.09), wall.lightened(0.2), Vector3(x, y - 0.09, 0.335))
				s.box(Vector3(0.17, 0.06, 0.012), IRON, Vector3(x, y - 0.05, 0.378))
		for side: float in [-0.435, 0.435]:
			for z: float in [-0.13, 0.13]:
				var lit := rng.randf() < 0.5
				s.box(Vector3(0.02, 0.14, 0.1), LAMP if lit else GLASS_DARK, Vector3(side, y, z), Vector3.ZERO, lit)


## A timbered entrance dug into a rocky mound, rails running out to an ore cart, a lantern on a post.
static func _draw_mine(s: Shapes) -> void:
	var earth := Color(0.60, 0.52, 0.54)
	s.sphere(0.56, earth, Vector3(0.0, 0.0, -0.16), Vector3(1.0, 0.8, 0.8))
	s.sphere(0.32, earth.darkened(0.08), Vector3(-0.3, 0.0, -0.06), Vector3(1.0, 0.75, 1.0))
	s.sphere(0.26, earth.lightened(0.05), Vector3(0.3, 0.0, -0.02), Vector3(1.0, 0.7, 1.0))
	s.box(Vector3(0.24, 0.28, 0.24), DOORWAY, Vector3(0.0, 0.14, 0.16))
	for x: float in [-0.14, 0.14]:
		s.box(Vector3(0.05, 0.32, 0.05), TIMBER, Vector3(x, 0.16, 0.28))
		s.box(Vector3(0.04, 0.04, 0.16), TIMBER.darkened(0.1), Vector3(x, 0.3, 0.2))
	s.box(Vector3(0.4, 0.06, 0.08), TIMBER, Vector3(0.0, 0.33, 0.28))
	for side: float in [-0.05, 0.05]:
		s.box(Vector3(0.015, 0.012, 0.5), IRON, Vector3(side, 0.012, 0.47))
	for k: int in 5:
		s.box(Vector3(0.16, 0.012, 0.03), TIMBER, Vector3(0.0, 0.006, 0.28 + k * 0.09))
	# The ore cart, heaped with copper-colored ore.
	s.box(Vector3(0.15, 0.08, 0.2), Color(0.48, 0.36, 0.34), Vector3(0.0, 0.085, 0.52))
	for x: float in [-0.08, 0.08]:
		for z: float in [0.45, 0.59]:
			s.cylinder(0.03, 0.03, 0.015, IRON, Vector3(x, 0.035, z), 8, Vector3(0.0, 0.0, PI / 2.0))
	for spot: Vector3 in [Vector3(-0.03, 0.135, 0.49), Vector3(0.035, 0.135, 0.55), Vector3(0.0, 0.15, 0.52)]:
		s.sphere(0.04, Color(0.82, 0.54, 0.34), spot)
	s.cylinder(0.012, 0.014, 0.36, TIMBER, Vector3(-0.22, 0.18, 0.3), 5)
	s.box(Vector3(0.05, 0.06, 0.05), LAMP, Vector3(-0.22, 0.36, 0.3), Vector3.ZERO, true)
	s.box(Vector3(0.07, 0.015, 0.07), IRON, Vector3(-0.22, 0.4, 0.3))


## An open timber shed over a stone forge and its chimney; the coals and the light are added live.
static func _draw_smithy(s: Shapes, tint: Color) -> void:
	s.box(Vector3(0.82, 0.03, 0.68), STONE_DARK, Vector3(0.0, 0.015, 0.0))
	for x: float in [-0.37, 0.37]:
		for z: float in [-0.3, 0.3]:
			s.box(Vector3(0.05, 0.42, 0.05), TIMBER, Vector3(x, 0.21, z))
	s.box(Vector3(0.78, 0.38, 0.04), STONE, Vector3(0.0, 0.19, -0.31))
	s.box(Vector3(0.04, 0.2, 0.6), TIMBER.lightened(0.1), Vector3(-0.37, 0.1, 0.0))
	s.prism(Vector3(0.82, 0.2, 0.92), SLATE.lerp(tint, 0.15), Vector3(0.0, 0.52, 0.0), PI / 2.0)
	s.box(Vector3(0.32, 0.2, 0.26), STONE, Vector3(-0.18, 0.1, -0.14))
	s.box(Vector3(0.34, 0.03, 0.28), STONE_DARK, Vector3(-0.18, 0.2, -0.14))
	s.box(Vector3(0.2, 0.12, 0.18), STONE_DARK, Vector3(-0.18, 0.36, -0.18))
	s.box(Vector3(0.12, 0.44, 0.12), STONE_DARK, Vector3(-0.18, 0.62, -0.2))
	s.box(Vector3(0.15, 0.03, 0.15), IRON, Vector3(-0.18, 0.85, -0.2))


## A plastered, timber-framed schoolhouse with tall windows and a bell in a belfry on the ridge.
static func _draw_school(s: Shapes, tint: Color) -> void:
	s.box(Vector3(0.92, 0.04, 0.62), STONE_DARK, Vector3(0.0, 0.02, 0.0))
	s.box(Vector3(0.86, 0.36, 0.56), PLASTER, Vector3(0.0, 0.22, 0.0))
	s.box(Vector3(0.88, 0.03, 0.58), TIMBER, Vector3(0.0, 0.39, 0.0))
	for x: float in [-0.43, -0.25, 0.25, 0.43]:
		s.box(Vector3(0.03, 0.36, 0.58), TIMBER, Vector3(x, 0.22, 0.0))
	s.prism(Vector3(0.66, 0.26, 0.96), TILE.lerp(tint, 0.3), Vector3(0.0, 0.53, 0.0), PI / 2.0)
	# Belfry: four posts round a bell under a little spire.
	s.box(Vector3(0.17, 0.05, 0.17), PLASTER, Vector3(0.0, 0.66, 0.0))
	for x: float in [-0.065, 0.065]:
		for z: float in [-0.065, 0.065]:
			s.box(Vector3(0.025, 0.13, 0.025), TIMBER, Vector3(x, 0.745, z))
	s.cylinder(0.022, 0.045, 0.07, GOLD, Vector3(0.0, 0.75, 0.0), 8)
	s.cylinder(0.0, 0.13, 0.14, TILE.lerp(tint, 0.3).darkened(0.15), Vector3(0.0, 0.88, 0.0), 4, Vector3(0.0, PI / 4.0, 0.0))
	# A double door up a step, an open book over it, and lit windows either side.
	s.box(Vector3(0.17, 0.23, 0.03), TIMBER.darkened(0.2), Vector3(0.0, 0.155, 0.285))
	s.box(Vector3(0.26, 0.04, 0.09), STONE, Vector3(0.0, 0.02, 0.33))
	s.box(Vector3(0.07, 0.05, 0.01), MARBLE, Vector3(-0.034, 0.33, 0.29), Vector3(0.0, 0.3, 0.0))
	s.box(Vector3(0.07, 0.05, 0.01), MARBLE, Vector3(0.034, 0.33, 0.29), Vector3(0.0, -0.3, 0.0))
	for x: float in [-0.34, -0.16, 0.16, 0.34]:
		s.box(Vector3(0.08, 0.15, 0.03), LAMP, Vector3(x, 0.23, 0.285), Vector3.ZERO, true)
		s.box(Vector3(0.08, 0.15, 0.03), GLASS_DARK, Vector3(x, 0.23, -0.285))


## A columned stone temple on three steps under a terracotta pediment; fire glows in its doorway.
static func _draw_temple(s: Shapes, tint: Color) -> void:
	for step: int in 3:
		s.box(Vector3(1.0 - step * 0.08, 0.06, 0.8 - step * 0.08), MARBLE.darkened(0.06 * (2 - step)), Vector3(0.0, 0.03 + step * 0.06, 0.0))
	s.box(Vector3(0.5, 0.42, 0.36), STONE, Vector3(0.0, 0.39, -0.04))
	s.box(Vector3(0.13, 0.24, 0.02), EMBER.lerp(LAMP, 0.4), Vector3(0.0, 0.3, 0.145), Vector3.ZERO, true)
	var columns: Array[Vector2] = []
	for x: float in [-0.33, -0.11, 0.11, 0.33]:
		columns.append(Vector2(x, 0.26))
		columns.append(Vector2(x, -0.26))
	columns.append(Vector2(-0.33, 0.0))
	columns.append(Vector2(0.33, 0.0))
	for spot: Vector2 in columns:
		s.box(Vector3(0.09, 0.03, 0.09), MARBLE, Vector3(spot.x, 0.195, spot.y))
		s.cylinder(0.032, 0.038, 0.42, MARBLE, Vector3(spot.x, 0.42, spot.y), 8)
		s.box(Vector3(0.09, 0.03, 0.09), MARBLE, Vector3(spot.x, 0.645, spot.y))
	s.box(Vector3(0.82, 0.07, 0.62), MARBLE, Vector3(0.0, 0.695, 0.0))
	s.box(Vector3(0.83, 0.025, 0.63), tint.lerp(GOLD, 0.25), Vector3(0.0, 0.68, 0.0))
	s.prism(Vector3(0.86, 0.2, 0.66), TILE.lerp(tint, 0.3), Vector3(0.0, 0.83, 0.0))
	s.sphere(0.03, GOLD, Vector3(0.0, 0.94, 0.32))
	for side: float in [-0.44, 0.44]:
		s.cylinder(0.014, 0.018, 0.2, IRON, Vector3(side, 0.1, 0.36), 5)
		s.cylinder(0.05, 0.03, 0.04, IRON, Vector3(side, 0.22, 0.36), 8)
		s.cylinder(0.0, 0.035, 0.08, EMBER, Vector3(side, 0.28, 0.36), 5, Vector3.ZERO, true)


## The ruler's seat: a stone hall between two towers under the tribe's colors, banners on the
## front, a flag on the ridge and gold on the spires.
static func _draw_great_house(s: Shapes, tint: Color) -> void:
	var roof := SLATE.lerp(tint, 0.4)
	s.box(Vector3(1.0, 0.06, 0.8), STONE_DARK, Vector3(0.0, 0.03, 0.0))
	s.box(Vector3(0.6, 0.5, 0.56), STONE, Vector3(0.0, 0.31, -0.04))
	s.prism(Vector3(0.64, 0.32, 0.66), roof, Vector3(0.0, 0.72, -0.04), PI / 2.0)
	for side: float in [-0.38, 0.38]:
		s.box(Vector3(0.25, 0.74, 0.25), STONE, Vector3(side, 0.43, 0.0))
		s.box(Vector3(0.28, 0.04, 0.28), STONE_DARK, Vector3(side, 0.8, 0.0))
		s.cylinder(0.0, 0.21, 0.34, roof, Vector3(side, 0.99, 0.0), 4, Vector3(0.0, PI / 4.0, 0.0))
		s.sphere(0.025, GOLD, Vector3(side, 1.17, 0.0))
		s.box(Vector3(0.05, 0.08, 0.02), LAMP, Vector3(side, 0.66, 0.126), Vector3.ZERO, true)
		s.box(Vector3(0.12, 0.3, 0.012), tint, Vector3(side, 0.38, 0.13))
		s.prism(Vector3(0.12, 0.06, 0.012), tint, Vector3(side, 0.2, 0.13), 0.0, 0.5, PI)
		s.box(Vector3(0.05, 0.05, 0.016), GOLD, Vector3(side, 0.42, 0.135))
		s.box(Vector3(0.15, 0.015, 0.02), TIMBER, Vector3(side, 0.53, 0.135))
	for side: float in [-0.19, 0.19]:
		s.box(Vector3(0.09, 0.26, 0.012), tint.darkened(0.15), Vector3(side, 0.36, 0.245))
		s.box(Vector3(0.04, 0.04, 0.016), GOLD, Vector3(side, 0.4, 0.25))
	s.box(Vector3(0.22, 0.32, 0.02), STONE_DARK, Vector3(0.0, 0.2, 0.24))
	s.box(Vector3(0.15, 0.24, 0.03), DOORWAY, Vector3(0.0, 0.18, 0.25))
	s.cylinder(0.075, 0.075, 0.03, DOORWAY, Vector3(0.0, 0.3, 0.25), 10, Vector3(PI / 2.0, 0.0, 0.0))
	for x: float in [-0.07, 0.07]:
		s.box(Vector3(0.04, 0.07, 0.02), LAMP, Vector3(x, 0.47, 0.245), Vector3.ZERO, true)
	s.box(Vector3(0.32, 0.04, 0.12), STONE_DARK, Vector3(0.0, 0.08, 0.34))
	s.cylinder(0.008, 0.008, 0.3, IRON, Vector3(0.0, 1.02, -0.04), 4)
	s.box(Vector3(0.15, 0.09, 0.008), tint, Vector3(0.075, 1.12, -0.04))


## A paved square of three stalls under striped awnings, each with its own goods.
static func _draw_market(s: Shapes, tint: Color) -> void:
	s.box(Vector3(1.2, 0.02, 0.86), Color(0.82, 0.72, 0.60), Vector3(0.0, 0.01, 0.0))
	var goods: Array = [
		[Color(0.90, 0.36, 0.30), Color(0.96, 0.74, 0.30), Color(0.52, 0.76, 0.36)],
		[Color(0.42, 0.56, 0.84), Color(0.90, 0.84, 0.70), Color(0.72, 0.36, 0.56)],
		[Color(0.84, 0.62, 0.38), Color(0.66, 0.42, 0.28), Color(0.92, 0.88, 0.78)],
	]
	for k: int in 3:
		var turn := (1 - k) * 0.4
		var at := Vector3((k - 1) * 0.38, 0.0, -0.06 - 0.12 * float(k == 1))
		s.frame = Transform3D(Basis(Vector3.UP, turn), at)
		s.box(Vector3(0.34, 0.14, 0.13), TIMBER.lightened(0.15), Vector3(0.0, 0.07, 0.07))
		for x: float in [-0.16, 0.16]:
			s.box(Vector3(0.025, 0.36, 0.025), TIMBER, Vector3(x, 0.18, 0.13))
			s.box(Vector3(0.025, 0.42, 0.025), TIMBER, Vector3(x, 0.21, -0.12))
		for stripe: int in 4:
			var color: Color = tint if stripe % 2 == 0 else Props.LINEN
			s.box(Vector3(0.1, 0.018, 0.34), color, Vector3(-0.15 + stripe * 0.1, 0.4, 0.0), Vector3(-0.2, 0.0, 0.0))
			s.box(Vector3(0.1, 0.05, 0.01), color, Vector3(-0.15 + stripe * 0.1, 0.345, 0.17))
		var wares: Array = goods[k]
		for g: int in 5:
			s.sphere(0.028, wares[g % 3], Vector3(-0.12 + g * 0.06, 0.165, 0.07 + 0.02 * (g % 2)))
	s.frame = Transform3D.IDENTITY


## A long cold-stone barracks: slit windows, a weapons rack of spears, a training dummy and a
## flag on a steel pole.
static func _draw_barracks(s: Shapes, tint: Color) -> void:
	var banner := tint.lerp(COLD_STONE, 0.25)
	s.box(Vector3(1.02, 0.04, 0.58), COLD_DARK, Vector3(0.0, 0.02, -0.08))
	s.box(Vector3(0.96, 0.34, 0.5), COLD_STONE, Vector3(0.0, 0.21, -0.08))
	s.box(Vector3(0.98, 0.03, 0.52), COLD_DARK, Vector3(0.0, 0.39, -0.08))
	s.prism(Vector3(0.58, 0.14, 1.02), SLATE.darkened(0.2), Vector3(0.0, 0.47, -0.08), PI / 2.0)
	s.box(Vector3(0.15, 0.23, 0.03), IRON, Vector3(0.0, 0.155, 0.175))
	s.box(Vector3(0.2, 0.04, 0.05), COLD_DARK, Vector3(0.0, 0.285, 0.18))
	s.box(Vector3(0.08, 0.08, 0.015), banner, Vector3(0.0, 0.34, 0.18), Vector3(0.0, 0.0, PI / 4.0))
	for x: float in [-0.4, -0.29, -0.18, 0.18, 0.29, 0.4]:
		var lit := absf(x) < 0.2
		s.box(Vector3(0.035, 0.12, 0.02), LAMP if lit else DOORWAY, Vector3(x, 0.25, 0.175), Vector3.ZERO, lit)
		s.box(Vector3(0.035, 0.12, 0.02), DOORWAY, Vector3(x, 0.25, -0.335))
	# Spears in a rack.
	s.box(Vector3(0.26, 0.02, 0.02), TIMBER, Vector3(0.34, 0.22, 0.34))
	for x: float in [0.25, 0.31, 0.37, 0.43]:
		s.cylinder(0.007, 0.008, 0.44, TIMBER, Vector3(x, 0.22, 0.33), 4, Vector3(-0.12, 0.0, 0.0))
		s.cylinder(0.0, 0.016, 0.05, STEEL, Vector3(x, 0.46, 0.30), 4)
	# A straw dummy on a post.
	s.cylinder(0.012, 0.012, 0.3, TIMBER, Vector3(-0.18, 0.15, 0.36), 5)
	s.box(Vector3(0.18, 0.02, 0.02), TIMBER, Vector3(-0.18, 0.24, 0.36))
	s.cylinder(0.045, 0.04, 0.13, THATCH, Vector3(-0.18, 0.2, 0.36), 6)
	s.sphere(0.035, THATCH.lightened(0.1), Vector3(-0.18, 0.31, 0.36))
	s.cylinder(0.01, 0.012, 0.8, STEEL, Vector3(-0.44, 0.4, 0.3), 5)
	s.box(Vector3(0.2, 0.12, 0.008), banner, Vector3(-0.34, 0.72, 0.3))
	s.sphere(0.018, GOLD, Vector3(-0.44, 0.81, 0.3))


## A tall, tapering tower of cold stone with a lookout platform under a pointed roof. The light
## on top (a brazier, or a searchlight from the age of steam) is added live.
static func _draw_watchtower(s: Shapes, look: String) -> void:
	var cold := look == "searchlight"
	var stone := COLD_STONE if cold else STONE.lerp(COLD_STONE, 0.5)
	s.cylinder(0.2, 0.27, 1.1, stone, Vector3(0.0, 0.55, 0.0), 4, Vector3(0.0, PI / 4.0, 0.0))
	s.box(Vector3(0.12, 0.2, 0.02), DOORWAY, Vector3(0.0, 0.1, 0.19))
	s.box(Vector3(0.03, 0.09, 0.02), LAMP, Vector3(0.0, 0.7, 0.16), Vector3.ZERO, true)
	s.box(Vector3(0.52, 0.05, 0.52), COLD_DARK if cold else TIMBER, Vector3(0.0, 1.125, 0.0))
	for i: int in 4:
		var turn := Basis(Vector3.UP, i * PI / 2.0)
		s.box(Vector3(0.52, 0.07, 0.02), COLD_DARK if cold else TIMBER, turn * Vector3(0.0, 1.2, 0.25), Vector3(0.0, i * PI / 2.0, 0.0))
	for x: float in [-0.23, 0.23]:
		for z: float in [-0.23, 0.23]:
			s.box(Vector3(0.03, 0.36, 0.03), IRON if cold else TIMBER, Vector3(x, 1.33, z))
	s.cylinder(0.0, 0.38, 0.24, SLATE.darkened(0.15), Vector3(0.0, 1.63, 0.0), 4, Vector3(0.0, PI / 4.0, 0.0))
	if not cold:
		s.cylinder(0.07, 0.045, 0.06, IRON, Vector3(0.0, 1.18, 0.0), 8)


## The statue's plinth: two stone tiers, a cornice and a gold plaque. The figure is added live.
static func _draw_statue_plinth(s: Shapes) -> void:
	s.box(Vector3(0.56, 0.1, 0.56), COLD_DARK, Vector3(0.0, 0.05, 0.0))
	s.box(Vector3(0.42, 0.28, 0.42), COLD_STONE, Vector3(0.0, 0.24, 0.0))
	s.box(Vector3(0.47, 0.04, 0.47), COLD_DARK, Vector3(0.0, 0.4, 0.0))
	s.box(Vector3(0.18, 0.08, 0.012), GOLD, Vector3(0.0, 0.25, 0.214))


## A grim walled yard: a cell block with barred windows, a corner tower and an iron gate.
static func _draw_prison(s: Shapes) -> void:
	s.box(Vector3(0.84, 0.01, 0.44), Color(0.50, 0.49, 0.54), Vector3(0.0, 0.005, 0.2))
	s.box(Vector3(0.98, 0.44, 0.07), COLD_STONE, Vector3(0.0, 0.22, -0.46))
	for side: float in [-0.46, 0.46]:
		s.box(Vector3(0.07, 0.44, 0.98), COLD_STONE, Vector3(side, 0.22, 0.0))
		s.box(Vector3(0.34, 0.44, 0.07), COLD_STONE, Vector3(side * 0.66, 0.22, 0.46))
	for spot: Array in [[Vector3(1.0, 0.03, 0.09), Vector3(0.0, 0.455, -0.46)], [Vector3(0.09, 0.03, 1.0), Vector3(-0.46, 0.455, 0.0)],
			[Vector3(0.09, 0.03, 1.0), Vector3(0.46, 0.455, 0.0)]]:
		s.box(spot[0], COLD_DARK, spot[1])
	for side: float in [-0.66, 0.66]:
		s.box(Vector3(0.36, 0.03, 0.09), COLD_DARK, Vector3(side * 0.46, 0.455, 0.46))
	# The gate: iron bars under a heavy lintel.
	s.box(Vector3(0.3, 0.1, 0.1), COLD_DARK, Vector3(0.0, 0.42, 0.46))
	s.box(Vector3(0.26, 0.025, 0.025), IRON, Vector3(0.0, 0.34, 0.46))
	for k: int in 6:
		s.cylinder(0.007, 0.007, 0.36, IRON, Vector3(-0.11 + k * 0.044, 0.18, 0.46), 4)
	# The cell block, its windows barred and dimly lit.
	s.box(Vector3(0.82, 0.54, 0.34), COLD_STONE.darkened(0.12), Vector3(0.0, 0.27, -0.25))
	s.box(Vector3(0.86, 0.04, 0.38), COLD_DARK, Vector3(0.0, 0.56, -0.25))
	for row: int in 2:
		for k: int in 5:
			var x := -0.3 + k * 0.15
			var y := 0.16 + row * 0.2
			var lit := (k + row) % 3 == 0
			s.box(Vector3(0.08, 0.09, 0.012), LAMP.lerp(COLD_LIGHT, 0.5) if lit else DOORWAY, Vector3(x, y, -0.077), Vector3.ZERO, lit)
			for b: int in 3:
				s.box(Vector3(0.008, 0.1, 0.012), IRON, Vector3(x - 0.025 + b * 0.025, y, -0.07))
	s.box(Vector3(0.17, 0.78, 0.17), COLD_STONE, Vector3(-0.46, 0.39, 0.46))
	s.box(Vector3(0.22, 0.05, 0.22), COLD_DARK, Vector3(-0.46, 0.8, 0.46))
	s.box(Vector3(0.06, 0.05, 0.06), COLD_LIGHT, Vector3(-0.46, 0.85, 0.46), Vector3.ZERO, true)


## A brick mill under a sawtooth roof of glazed north lights, with a tall banded chimney behind.
## The smoke is added live.
static func _draw_factory(s: Shapes, tint: Color) -> void:
	s.box(Vector3(1.22, 0.04, 0.82), STONE_DARK, Vector3(0.0, 0.02, 0.0))
	s.box(Vector3(1.16, 0.42, 0.76), BRICK, Vector3(0.0, 0.25, 0.0))
	s.box(Vector3(1.18, 0.03, 0.78), BRICK_DARK, Vector3(0.0, 0.46, 0.0))
	for k: int in 4:
		var x := -0.435 + k * 0.29
		s.prism(Vector3(0.29, 0.22, 0.78), SLATE.darkened(0.1), Vector3(x, 0.585, 0.0), 0.0, 0.0)
		s.box(Vector3(0.012, 0.17, 0.7), LAMP.lerp(Color(0.7, 0.85, 1.0), 0.3).darkened(0.4), Vector3(x - 0.14, 0.565, 0.0), Vector3.ZERO, true)
	for x: float in [-0.47, -0.31, -0.15, 0.01]:
		s.box(Vector3(0.1, 0.2, 0.02), LAMP, Vector3(x, 0.25, 0.385), Vector3.ZERO, true)
		s.box(Vector3(0.1, 0.2, 0.02), LAMP if x < -0.2 else GLASS_DARK, Vector3(x, 0.25, -0.385), Vector3.ZERO, x < -0.2)
		s.box(Vector3(0.12, 0.03, 0.03), BRICK_DARK, Vector3(x, 0.36, 0.39))
	s.box(Vector3(0.24, 0.3, 0.03), IRON.lightened(0.1), Vector3(0.3, 0.15, 0.385))
	s.box(Vector3(0.28, 0.04, 0.05), tint.darkened(0.2), Vector3(0.3, 0.32, 0.39))
	s.box(Vector3(0.012, 0.3, 0.035), IRON, Vector3(0.3, 0.15, 0.39))
	# The chimney.
	s.box(Vector3(0.26, 0.32, 0.26), BRICK_DARK, Vector3(-0.38, 0.16, -0.48))
	s.cylinder(0.065, 0.1, 1.7, BRICK, Vector3(-0.38, 1.17, -0.48), 10)
	for y: float in [0.85, 1.45]:
		s.cylinder(0.1 - (y - 0.3) * 0.02, 0.1 - (y - 0.3) * 0.02, 0.05, BRICK_DARK, Vector3(-0.38, y, -0.48), 10)
	s.cylinder(0.085, 0.075, 0.07, IRON, Vector3(-0.38, 2.02, -0.48), 10)


## A red-and-white lattice mast on a concrete footing, with a dish, an equipment hut and an
## aerial on top. Its warning lights blink live.
static func _draw_broadcast_tower(s: Shapes) -> void:
	var red := Color(0.90, 0.34, 0.30)
	var white := Color(0.94, 0.92, 0.88)
	s.box(Vector3(0.46, 0.06, 0.46), CONCRETE, Vector3(0.0, 0.03, 0.0))
	s.box(Vector3(0.24, 0.2, 0.18), CONCRETE.darkened(0.08), Vector3(0.24, 0.1, 0.28))
	s.box(Vector3(0.07, 0.13, 0.02), GLASS_DARK, Vector3(0.24, 0.07, 0.375))
	s.box(Vector3(0.28, 0.02, 0.22), IRON, Vector3(0.24, 0.21, 0.28))
	var levels := 7
	var top := 2.6
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for level: int in levels:
		var y0 := 0.06 + (top - 0.06) * level / levels
		var y1 := 0.06 + (top - 0.06) * (level + 1) / levels
		var w0 := lerpf(0.18, 0.035, float(level) / levels)
		var w1 := lerpf(0.18, 0.035, float(level + 1) / levels)
		var color := red if level % 2 == 0 else white
		for c: int in 4:
			var a: Vector2 = corners[c]
			var b: Vector2 = corners[(c + 1) % 4]
			s.strut(Vector3(a.x * w0, y0, a.y * w0), Vector3(a.x * w1, y1, a.y * w1), 0.014, color)
			s.strut(Vector3(a.x * w1, y1, a.y * w1), Vector3(b.x * w1, y1, b.y * w1), 0.007, color)
			var flip := (level + c) % 2 == 0
			s.strut(Vector3((a.x if flip else b.x) * w0, y0, (a.y if flip else b.y) * w0), Vector3((b.x if flip else a.x) * w1, y1, (b.y if flip else a.y) * w1), 0.005, white.darkened(0.1))
	s.box(Vector3(0.14, 0.02, 0.14), IRON, Vector3(0.0, top, 0.0))
	s.cylinder(0.008, 0.014, 0.46, white, Vector3(0.0, top + 0.23, 0.0), 6)
	s.cylinder(0.11, 0.025, 0.05, white, Vector3(0.0, 1.85, 0.11), 10, Vector3(PI / 2.0, 0.0, 0.0))
	s.box(Vector3(0.012, 0.012, 0.08), IRON, Vector3(0.0, 1.85, 0.08))


## A steel pole on a concrete footing, ringed with cameras that stare out over the village; the
## searchlight head that turns on top is added live. The dystopia's signature.
static func _draw_surveillance_mast(s: Shapes) -> void:
	s.cylinder(0.17, 0.21, 0.12, CONCRETE, Vector3(0.0, 0.06, 0.0), 8)
	s.box(Vector3(0.12, 0.18, 0.08), COLD_DARK, Vector3(0.14, 0.2, 0.12))
	s.box(Vector3(0.025, 0.025, 0.01), Color(0.4, 1.0, 0.6), Vector3(0.14, 0.25, 0.162), Vector3.ZERO, true)
	s.cylinder(0.04, 0.06, 2.02, STEEL.darkened(0.15), Vector3(0.0, 1.13, 0.0), 8)
	s.cylinder(0.07, 0.07, 0.03, IRON, Vector3(0.0, 1.85, 0.0), 8)
	s.cylinder(0.06, 0.06, 0.04, IRON, Vector3(0.0, 2.12, 0.0), 8)
	for k: int in 3:
		var angle := TAU * k / 3.0 + 0.5
		s.frame = Transform3D(Basis(Vector3.UP, angle), Vector3(0.0, 1.8, 0.0))
		s.box(Vector3(0.02, 0.02, 0.16), IRON, Vector3(0.0, 0.03, 0.08))
		s.frame = s.frame * Transform3D(Basis(Vector3.RIGHT, 0.45), Vector3(0.0, 0.0, 0.17))
		s.box(Vector3(0.075, 0.065, 0.15), Color(0.88, 0.88, 0.92), Vector3.ZERO)
		s.box(Vector3(0.09, 0.012, 0.17), COLD_DARK, Vector3(0.0, 0.04, 0.01))
		s.cylinder(0.026, 0.026, 0.03, IRON, Vector3(0.0, 0.0, 0.085), 8, Vector3(PI / 2.0, 0.0, 0.0))
		s.cylinder(0.016, 0.016, 0.01, WARNING, Vector3(0.0, 0.0, 0.1), 8, Vector3(PI / 2.0, 0.0, 0.0), true)
	s.frame = Transform3D.IDENTITY


## A lamp housing on a turning (or sweeping) mount, throwing a soft cone of light down onto the
## ground, with a real spotlight inside it.
static func _searchlight(at: Vector3, tilt_degrees: float, reach: float, color: Color, motion: BuildingMotion.Kind, speed: float) -> BuildingMotion:
	var mount := BuildingMotion.make(motion, speed, 1.1)
	mount.position = at
	var down := Vector3(0.0, -sin(deg_to_rad(tilt_degrees)), cos(deg_to_rad(tilt_degrees)))
	var housing := MeshInstance3D.new()
	housing.mesh = _cone_mesh(0.05, 0.065, 0.13)
	housing.basis = Basis.looking_at(down) * Basis(Vector3.RIGHT, -PI / 2.0)
	housing.material_override = ToonMaterials.get_material(IRON, 0.006)
	mount.add_child(housing)
	var face := MeshInstance3D.new()
	face.mesh = _cone_mesh(0.056, 0.056, 0.01)
	face.basis = housing.basis
	face.position = down * 0.066
	face.material_override = _glow(color, 4.0)
	mount.add_child(face)
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	beam.mesh = _beam_mesh(reach)
	beam.basis = Basis.looking_at(down) * Basis(Vector3.RIGHT, PI / 2.0)
	beam.position = down * (reach / 2.0 + 0.06)
	beam.material_override = _beam(color)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mount.add_child(beam)
	var spot := SpotLight3D.new()
	spot.light_color = color
	spot.light_energy = 6.0
	spot.spot_range = reach * 1.5
	spot.spot_angle = 13.0
	spot.basis = Basis.looking_at(down)
	spot.position = down * 0.08
	mount.add_child(spot)
	return mount


## Smoke puffing from a chimney top: a few toon puffs that rise, swell, drift and fade.
static func _smoke(at: Vector3) -> CPUParticles3D:
	if _smoke_curve == null:
		_smoke_curve = Curve.new()
		_smoke_curve.add_point(Vector2(0.0, 0.3))
		_smoke_curve.add_point(Vector2(0.25, 0.9))
		_smoke_curve.add_point(Vector2(0.8, 1.4))
		_smoke_curve.add_point(Vector2(1.0, 0.0))
		_smoke_puff = _ball_mesh(0.11, 7, 4)
	var smoke := CPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.position = at
	smoke.amount = 9
	smoke.lifetime = 5.5
	smoke.preprocess = 5.5
	smoke.local_coords = false
	smoke.mesh = _smoke_puff
	smoke.material_override = ToonMaterials.get_material(SMOKE, 0.01)
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.04
	smoke.direction = Vector3.UP
	smoke.spread = 22.0
	smoke.initial_velocity_min = 0.14
	smoke.initial_velocity_max = 0.22
	smoke.gravity = Vector3(0.09, 0.03, 0.04)
	smoke.scale_amount_min = 0.7
	smoke.scale_amount_max = 1.1
	smoke.scale_amount_curve = _smoke_curve
	return smoke


## An open cone along Y, narrow at the top, its vertex alpha fading from the lamp to the ground.
static func _beam_mesh(reach: float) -> ArrayMesh:
	var key := "beam_mesh|%.2f" % reach
	if _materials.has(key):
		return _materials[key]
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var segments := 16
	for k: int in segments + 1:
		var angle := TAU * k / segments
		var around := Vector3(cos(angle), 0.0, sin(angle))
		vertices.append(around * 0.045 + Vector3(0.0, reach / 2.0, 0.0))
		vertices.append(around * reach * 0.14 - Vector3(0.0, reach / 2.0, 0.0))
		colors.append(Color(1.0, 1.0, 1.0, 1.0))
		colors.append(Color(1.0, 1.0, 1.0, 0.0))
		if k < segments:
			var a := k * 2
			indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 2, a + 1, a + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_materials[key] = mesh
	return mesh


static func _omni(color: Color, energy: float, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	return light


static func _prop(parent: Node3D, model_name: String, height: float, at: Vector3, turn: float) -> Node3D:
	var prop := Kit.prop(model_name, height)
	prop.position = at
	prop.rotation.y = turn
	parent.add_child(prop)
	return prop


static func _cone_mesh(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	return mesh


static func _ball_mesh(radius: float, segments: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh


static func _glow_box() -> BoxMesh:
	if not _materials.has("glow_box"):
		_materials["glow_box"] = BoxMesh.new()
	return _materials["glow_box"]


## A shared glowing toon material: lit windows, embers, warning lights.
static func _glow(color: Color, strength: float) -> ShaderMaterial:
	var key := "%s|%s" % [color.to_html(), strength]
	if not _materials.has(key):
		_materials[key] = ToonMaterials.emissive(color, color * strength)
	return _materials[key]


## A searchlight's beam: soft additive light, seen from both sides, casting nothing.
static func _beam(color: Color) -> StandardMaterial3D:
	var key := "beam|%s" % color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color(color, 0.22)
		_materials[key] = material
	return _materials[key]


## The surface arrays of a primitive, made once: unit box, sphere and prism (scaled per part),
## and cylinders by their shape.
static func _primitive(key: String) -> Array:
	if not _arrays.has(key):
		var parts := key.split("|")
		var mesh: PrimitiveMesh
		match parts[0]:
			"box":
				mesh = BoxMesh.new()
			"sphere":
				var sphere := SphereMesh.new()
				sphere.radius = 0.5
				sphere.height = 1.0
				sphere.radial_segments = 10
				sphere.rings = 5
				mesh = sphere
			"prism":
				var prism := PrismMesh.new()
				prism.left_to_right = float(parts[1])
				mesh = prism
			"cylinder":
				var cylinder := CylinderMesh.new()
				cylinder.top_radius = float(parts[1])
				cylinder.bottom_radius = float(parts[2])
				cylinder.height = 1.0
				cylinder.radial_segments = int(parts[3])
				cylinder.rings = 1
				mesh = cylinder
		_arrays[key] = mesh.surface_get_arrays(0)
	return _arrays[key]


## Collects a model's simple shapes into one mesh, each part's color riding on its vertices, so a
## building is one draw plus its outline however many parts it has. Glowing parts (lit windows,
## embers, warning lights) are merged into one mesh per color.
class Shapes:
	## Applied to every part added while it is set, so a group of parts (a market stall, a camera)
	## can be drawn in its own frame and turned as one.
	var frame := Transform3D.IDENTITY
	var solid := MeshParts.new()
	var glows: Dictionary = {} ## Color -> MeshParts

	## A box of a size, centered on a point, turned by Euler angles.
	func box(size: Vector3, color: Color, at: Vector3, turn: Vector3 = Vector3.ZERO, glow: bool = false) -> void:
		add(BuildingArt._primitive("box"), color, Transform3D(Basis.from_euler(turn) * Basis.from_scale(size), at), glow)

	## A cylinder (a cone with top 0), centered on a point. Radii and height are in world units.
	func cylinder(top: float, bottom: float, height: float, color: Color, at: Vector3, segments: int = 8, turn: Vector3 = Vector3.ZERO, glow: bool = false) -> void:
		var widest := maxf(maxf(top, bottom), 0.0001)
		var key := "cylinder|%.3f|%.3f|%d" % [top / widest, bottom / widest, segments]
		var shape := Basis.from_euler(turn) * Basis.from_scale(Vector3(widest, height, widest))
		add(BuildingArt._primitive(key), color, Transform3D(shape, at), glow)

	## A sphere of a radius, squashed or stretched per axis.
	func sphere(radius: float, color: Color, at: Vector3, squash: Vector3 = Vector3.ONE, glow: bool = false) -> void:
		add(BuildingArt._primitive("sphere"), color, Transform3D(Basis.from_scale(squash * radius * 2.0), at), glow)

	## A roof-like prism: a triangle of size.x by size.y drawn along size.z, its ridge along Z
	## unless turned (turn PI / 2 runs it along X). apex 0 puts the peak over the left edge.
	func prism(size: Vector3, color: Color, at: Vector3, turn: float = 0.0, apex: float = 0.5, roll: float = 0.0) -> void:
		var shape := Basis(Vector3.UP, turn) * Basis(Vector3.BACK, roll) * Basis.from_scale(size)
		add(BuildingArt._primitive("prism|%.2f" % apex), color, Transform3D(shape, at))

	## A thin rod from one point to another: lattice struts, braces, poles.
	func strut(from: Vector3, to: Vector3, radius: float, color: Color, segments: int = 4) -> void:
		var along := to - from
		var up := along.normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.y) > 0.9 else Vector3.UP).normalized()
		var basis := Basis(side, up, side.cross(up)) * Basis.from_scale(Vector3(radius, along.length(), radius))
		add(BuildingArt._primitive("cylinder|1.000|1.000|%d" % segments), color, Transform3D(basis, (from + to) / 2.0))

	func add(arrays: Array, color: Color, transform: Transform3D, glow: bool = false) -> void:
		var parts := solid
		if glow:
			if not glows.has(color):
				glows[color] = MeshParts.new()
			parts = glows[color]
		parts.add(arrays, color, frame * transform)


## Triangles gathered from many primitives, with a color on every vertex.
class MeshParts:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func add(arrays: Array, color: Color, transform: Transform3D) -> void:
		var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base := vertices.size()
		var normal_basis := transform.basis.inverse().transposed()
		# Vertex colors reach the toon shader raw, while its tint is converted from sRGB.
		var linear := color.srgb_to_linear()
		for k: int in source_vertices.size():
			vertices.append(transform * source_vertices[k])
			normals.append((normal_basis * source_normals[k]).normalized())
			colors.append(linear)
		if source_indices.is_empty():
			for k: int in source_vertices.size():
				indices.append(base + k)
		else:
			for index: int in source_indices:
				indices.append(base + index)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		if vertices.is_empty():
			return mesh
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
