class_name StyledBuildings
extends RefCounted
## Homes and civic buildings drawn from a tribe's architectural style (StyleKind's "architecture"):
## a roof module (cone, gable, dome, stepped, flat, spire), a wall material with its details (daub
## bands, timber frames, stone quoins, plaster pilasters, brick courses, concrete slabs), the
## palette's wall, roof and trim colors, an ornament (carved, painted, banners, gilded, grim),
## up to two towers and a proportion. BuildingArt merges each model into one mesh with an outline
## hull and caches it by type, tint and style key, so a whole village of them stays cheap.
## Every model stands on its origin with its door facing +Z, inside BuildingArt.SIZES' footprint.

const TYPES: Array[String] = ["hut", "longhouse", "stone_house", "rowhouse", "apartment", "temple", "great_house", "school", "market"]
const HEIGHTS := {"squat": 0.82, "balanced": 1.0, "tall": 1.3} ## wall height, by proportion
const PITCHES := {"squat": 0.85, "balanced": 1.0, "tall": 1.25} ## roof height, by proportion
const OVERHANG := 0.06
## Long buildings (longer than this times their depth) get barrel vaults and gabled spires.
const LONG := 1.6
## Bright swatches (ArtPalette) that painted styles wash their walls in, besides trim and tint.
const WASHES: Array[int] = [24, 29, 25, 28, 18]


## The resolved look of a style: colors from the palette, toward the tribe's tint where it shows.
class Look:
	var roof := "gable"
	var material := "daub"
	var wall := Color.WHITE
	var roof_color := Color.WHITE
	var trim := Color.WHITE
	var ornament := "none"
	var towers := 0
	var height := 1.0
	var pitch := 1.0
	var tint := Color.WHITE

	## From a key written by StyledBuildings.key(). Grim styles keep their greys untinted.
	static func from_key(key: String, tribe_tint: Color) -> Look:
		var parts := key.split(".")
		var look := Look.new()
		look.roof = parts[0]
		look.material = parts[1]
		look.ornament = parts[5]
		look.towers = int(parts[6])
		look.height = float(HEIGHTS.get(parts[7], 1.0))
		look.pitch = float(PITCHES.get(parts[7], 1.0))
		look.tint = tribe_tint
		var warmth := 0.0 if look.ornament == "grim" else 1.0
		look.wall = ArtPalette.color(int(parts[2])).lerp(tribe_tint, 0.06 * warmth)
		look.roof_color = ArtPalette.color(int(parts[3])).lerp(tribe_tint, 0.2 * warmth)
		look.trim = ArtPalette.color(int(parts[4]))
		return look

	## Painted styles wash each kind of building in its own bright color (the trim, the tribe's
	## color or a bright swatch), so a painted village is a patchwork.
	func wash(type: String) -> void:
		if ornament != "painted":
			return
		var colors: Array[Color] = [trim, tint]
		for index: int in WASHES:
			colors.append(ArtPalette.color(index))
		wall = wall.lerp(colors[TYPES.find(type) % colors.size()], 0.55)

	func is_grim() -> bool:
		return ornament == "grim"

	## Gold for gilded styles, else the trim: finials, door frames, bands.
	func accent() -> Color:
		return BuildingArt.GOLD if ornament == "gilded" else trim

	func base() -> Color:
		return wall.darkened(0.3)


static func styles(type: String) -> bool:
	return type in TYPES


## A short, stable key of a style's architecture ("spire.stone.6.17.17.gilded.2.tall"), or "" when
## the type isn't styled or there is no style. Views put it in their building keys, so a new
## style rebuilds the buildings that show it (and only those).
static func key(type: String, style: Dictionary) -> String:
	var a: Dictionary = style.get("architecture", {})
	if a.is_empty() or not styles(type):
		return ""
	return "%s.%s.%d.%d.%d.%s.%d.%s" % [a.get("roof", "gable"), a.get("material", "daub"), int(a.get("wall", 0)), int(a.get("roof_color", 1)),
		int(a.get("trim", 2)), a.get("ornament", "none"), int(a.get("towers", 0)), a.get("proportion", "balanced")]


## Draws a styled building of a type into a BuildingArt.Shapes.
static func draw(s: BuildingArt.Shapes, type: String, tint: Color, style_key: String) -> void:
	var look := Look.from_key(style_key, tint)
	look.wash(type)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([type, style_key])
	match type:
		"hut":
			_hut(s, look, rng)
		"longhouse":
			_longhouse(s, look, rng)
		"stone_house":
			_stone_house(s, look, rng)
		"rowhouse":
			_rowhouse(s, look, rng)
		"apartment":
			_apartment(s, look, rng)
		"temple":
			_temple(s, look, rng)
		"great_house":
			_great_house(s, look, rng)
		"school":
			_school(s, look, rng)
		"market":
			_market(s, look)


# --- Buildings ----------------------------------------------------------------------

## A round hut under a cone, a spire or a dome, or a square one under the other roofs.
static func _hut(s: BuildingArt.Shapes, look: Look, rng: RandomNumberGenerator) -> void:
	if look.roof not in ["cone", "spire", "dome"]:
		var h := 0.27 * look.height
		_block(s, look, 0.52, 0.46, h, 1, [0.0], rng)
		var top := _roof(s, look, 0.52, 0.46, 0.05 + h, true)
		_ornament(s, look, 0.52, 0.46, 0.05 + h, top)
		return
	var r := 0.3
	var h := r * 0.9 * look.height
	s.cylinder(r * 0.95, r, h, look.wall, Vector3(0.0, h / 2.0, 0.0), 10)
	match look.material:
		"timber":
			for k: int in 6:
				var angle := TAU * (k + 0.5) / 6.0
				s.box(Vector3(0.035, h, 0.035), BuildingArt.TIMBER, Vector3(sin(angle) * r * 0.98, h / 2.0, cos(angle) * r * 0.98), Vector3(0.0, angle, 0.0))
		"daub":
			s.cylinder(r * 1.01, r * 1.03, 0.05, look.base(), Vector3(0.0, 0.025, 0.0), 10)
		_:
			s.cylinder(r * 1.0, r * 1.04, 0.06, look.wall.darkened(0.2), Vector3(0.0, 0.03, 0.0), 10)
	match look.ornament:
		"carved", "gilded", "grim":
			var band := look.accent() if look.ornament != "grim" else BuildingArt.IRON
			s.cylinder(r * 0.97, r * 0.98, 0.035, band, Vector3(0.0, h - 0.03, 0.0), 10)
		"painted":
			for k: int in 10:
				var angle := TAU * k / 10.0
				var color := look.trim if k % 2 == 0 else look.tint
				s.box(Vector3(0.05, 0.05, 0.012), color, Vector3(sin(angle) * r * 0.985, h * 0.55, cos(angle) * r * 0.985), Vector3(0.0, angle, 0.0))
		"banners":
			s.box(Vector3(0.07, 0.15, 0.012), look.tint, Vector3(r * 0.55, h * 0.55, r * 0.86), Vector3(0.0, 0.55, 0.0))
	var top := h
	match look.roof:
		"cone":
			var cone := r * 1.2 * look.pitch
			s.cylinder(0.0, r * 1.35, cone, look.roof_color, Vector3(0.0, h + cone / 2.0, 0.0), 10)
			top = h + cone
		"spire":
			var spire := r * 2.4 * look.pitch
			s.cylinder(0.0, r * 1.25, spire, look.roof_color, Vector3(0.0, h + spire / 2.0, 0.0), 10)
			top = h + spire
		"dome":
			s.sphere(r * 1.04, look.roof_color, Vector3(0.0, h, 0.0), Vector3(1.0, 0.8 * look.pitch, 1.0))
			top = h + r * 0.83 * look.pitch
	if look.ornament in ["gilded", "carved"] or look.roof == "spire":
		_finial(s, look, top)
	s.box(Vector3(r * 0.42, r * 0.6, 0.04), BuildingArt.DOORWAY, Vector3(0.0, r * 0.3, r * 0.97))


## A long hall for a whole clan: corner posts, the door in the middle of the long side.
static func _longhouse(s: BuildingArt.Shapes, look: Look, rng: RandomNumberGenerator) -> void:
	var h := 0.3 * look.height
	_block(s, look, 1.05, 0.52, h, 1, [0.0], rng)
	if look.material in ["daub", "timber"]:
		for x: float in [-0.5, 0.5]:
			for z: float in [-0.24, 0.24]:
				s.cylinder(0.025, 0.03, h + 0.06, BuildingArt.TIMBER, Vector3(x, (h + 0.06) / 2.0, z), 5)
	var top := _roof(s, look, 1.05, 0.52, 0.05 + h, true)
	_ornament(s, look, 1.05, 0.52, 0.05 + h, top)


## A cottage with a chimney.
static func _stone_house(s: BuildingArt.Shapes, look: Look, rng: RandomNumberGenerator) -> void:
	var h := 0.34 * look.height
	_block(s, look, 0.62, 0.5, h, 1, [0.0], rng)
	var eave := 0.05 + h
	s.box(Vector3(0.09, 0.24 * look.pitch + 0.1, 0.1), look.wall.darkened(0.25), Vector3(0.2, eave + 0.12 * look.pitch, -0.1))
	var top := _roof(s, look, 0.62, 0.5, eave, true)
	_ornament(s, look, 0.62, 0.5, eave, top)


## A terrace of three narrow houses, two storeys, a door each and chimneys on the party walls.
static func _rowhouse(s: BuildingArt.Shapes, look: Look, rng: RandomNumberGenerator) -> void:
	var h := 0.6 * look.height
	_block(s, look, 1.0, 0.5, h, 2, [-0.4, -0.06, 0.28], rng)
	var eave := 0.05 + h
	for x: float in [-0.17, 0.17]:
		s.box(Vector3(0.025, h, 0.52), look.wall.darkened(0.15), Vector3(x, 0.05 + h / 2.0, 0.0))
		s.box(Vector3(0.1, 0.3 * look.pitch + 0.08, 0.12), look.wall.darkened(0.25), Vector3(x, eave + 0.15 * look.pitch, 0.0))
	var top := _roof(s, look, 1.0, 0.5, eave, true)
	_ornament(s, look, 1.0, 0.5, eave, top)


## A five-storey block: a shop floor, rows of windows, balconies unless the style is grim.
static func _apartment(s: BuildingArt.Shapes, look: Look, rng: RandomNumberGenerator) -> void:
	var h := 1.5 * look.height
	_block(s, look, 0.86, 0.58, h, 5, [0.0], rng)
	var eave := 0.05 + h
	if not look.is_grim():
		for floor: int in range(1, 5):
			var y := 0.05 + h * floor / 5.0
			for x: float in [-0.3, 0.3]:
				s.box(Vector3(0.17, 0.025, 0.09), look.wall.lightened(0.2), Vector3(x, y + 0.01, 0.335))
				s.box(Vector3(0.17, 0.06, 0.012), look.trim, Vector3(x, y + 0.04, 0.378))
	s.box(Vector3(0.28, 0.025, 0.12), look.trim.darkened(0.2), Vector3(0.0, 0.05 + h / 5.0 * 0.8, 0.35))
	var top := 0.0
	if look.roof == "spire":
		# A block's spire is a slender one on a flat roof, or it would outgrow the temple.
		_roof(s, look, 0.86, 0.58, eave, true, Vector3.ZERO, "flat")
		top = _roof(s, look, 0.34, 0.34, eave + 0.05, true)
	else:
		top = _roof(s, look, 0.86, 0.58, eave, true)
	if look.roof == "flat":
		s.cylinder(0.07, 0.07, 0.13, BuildingArt.TIMBER, Vector3(-0.22, eave + 0.15, 0.05), 8)
		s.cylinder(0.005, 0.007, 0.3, BuildingArt.IRON, Vector3(0.3, eave + 0.2, -0.16), 4)
	_ornament(s, look, 0.86, 0.58, eave, top)


## A temple on three steps: a sanctuary with fire in its door behind a row of columns, under
## the style's roof, with towers at the back corners and braziers by the steps.
static func _temple(s: BuildingArt.Shapes, look: Look, _rng: RandomNumberGenerator) -> void:
	var stone := look.wall.lightened(0.12)
	for step: int in 3:
		s.box(Vector3(1.0 - step * 0.08, 0.06, 0.8 - step * 0.08), stone.darkened(0.06 * (2 - step)), Vector3(0.0, 0.03 + step * 0.06, 0.0))
	var h := 0.45 * look.height
	s.box(Vector3(0.5, h, 0.36), look.wall, Vector3(0.0, 0.18 + h / 2.0, -0.04))
	s.box(Vector3(0.13, minf(0.24, h * 0.6), 0.02), BuildingArt.EMBER.lerp(BuildingArt.LAMP, 0.4), Vector3(0.0, 0.18 + minf(0.12, h * 0.3), 0.145), Vector3.ZERO, true)
	var square := look.material in ["brick", "concrete"]
	for x: float in [-0.33, -0.11, 0.11, 0.33]:
		for z: float in [0.26, -0.26]:
			if square:
				s.box(Vector3(0.06, h, 0.06), stone, Vector3(x, 0.18 + h / 2.0, z))
			else:
				s.cylinder(0.032, 0.038, h, stone, Vector3(x, 0.18 + h / 2.0, z), 8)
	var eave := 0.18 + h
	s.box(Vector3(0.82, 0.07, 0.62), stone, Vector3(0.0, eave + 0.035, 0.0))
	s.box(Vector3(0.83, 0.025, 0.63), look.accent(), Vector3(0.0, eave + 0.02, 0.0))
	var top := _roof(s, look, 0.82, 0.62, eave + 0.07, false)
	_ornament(s, look, 0.5, 0.36, eave, top, Vector3(0.0, 0.0, -0.04))
	for k: int in look.towers:
		var side := -1.0 if k == 0 else 1.0
		_tower(s, look, Vector3(side * 0.4, 0.18, -0.3), 0.09, (0.75 + 0.3 * look.pitch) * look.height)
	for side: float in [-0.44, 0.44]:
		s.cylinder(0.014, 0.018, 0.2, BuildingArt.IRON, Vector3(side, 0.1, 0.36), 5)
		s.cylinder(0.05, 0.03, 0.04, BuildingArt.IRON, Vector3(side, 0.22, 0.36), 8)
		s.cylinder(0.0, 0.035, 0.08, BuildingArt.EMBER, Vector3(side, 0.28, 0.36), 5, Vector3.ZERO, true)


## The ruler's seat: a hall under the style's roof with banners in the tribe's color, between two
## towers (or behind one tall keep, or alone and wider when the style has no towers).
static func _great_house(s: BuildingArt.Shapes, look: Look, rng: RandomNumberGenerator) -> void:
	var width := 0.86 if look.towers == 0 else 0.6
	var h := 0.5 * look.height
	_block(s, look, width, 0.56, h, 2, [0.0], rng, Vector3(0.0, 0.0, -0.04))
	var eave := 0.05 + h
	var top := _roof(s, look, width, 0.56, eave, true, Vector3(0.0, 0.0, -0.04))
	_ornament(s, look, width, 0.56, eave, top, Vector3(0.0, 0.0, -0.04))
	match look.towers:
		1:
			_tower(s, look, Vector3(0.0, 0.0, -0.3), 0.13, h * 1.7 + 0.2)
		2:
			for side: float in [-0.38, 0.38]:
				_tower(s, look, Vector3(side, 0.0, 0.0), 0.125, h * 1.45 + 0.05)
	for side: float in [-0.19, 0.19]:
		var banner := look.tint if not look.is_grim() else look.tint.darkened(0.25)
		s.box(Vector3(0.09, minf(0.26, h * 0.6), 0.012), banner, Vector3(side * width / 0.6 * 0.9, 0.05 + h * 0.6, 0.25))
		s.box(Vector3(0.04, 0.04, 0.016), look.accent(), Vector3(side * width / 0.6 * 0.9, 0.05 + h * 0.66, 0.255))
	s.box(Vector3(0.32, 0.04, 0.12), look.base(), Vector3(0.0, 0.08, 0.34))
	s.cylinder(0.008, 0.008, 0.3, BuildingArt.IRON, Vector3(0.0, top + 0.12, -0.04), 4)
	s.box(Vector3(0.15, 0.09, 0.008), look.tint, Vector3(0.075, top + 0.22, -0.04))


## A schoolhouse with tall windows, a book over the door and a bell: in a belfry on the ridge,
## or in towers beside it.
static func _school(s: BuildingArt.Shapes, look: Look, rng: RandomNumberGenerator) -> void:
	var h := 0.36 * look.height
	_block(s, look, 0.86, 0.56, h, 1, [0.0], rng)
	var eave := 0.05 + h
	var top := _roof(s, look, 0.86, 0.56, eave, true)
	_ornament(s, look, 0.86, 0.56, eave, top)
	s.box(Vector3(0.07, 0.05, 0.01), BuildingArt.MARBLE, Vector3(-0.034, eave - 0.05, 0.29), Vector3(0.0, 0.3, 0.0))
	s.box(Vector3(0.07, 0.05, 0.01), BuildingArt.MARBLE, Vector3(0.034, eave - 0.05, 0.29), Vector3(0.0, -0.3, 0.0))
	if look.towers == 0:
		var y := top if look.roof in ["flat", "stepped", "dome"] else eave + 0.04
		for x: float in [-0.065, 0.065]:
			for z: float in [-0.065, 0.065]:
				s.box(Vector3(0.025, 0.13, 0.025), BuildingArt.TIMBER, Vector3(x, y + 0.065, z))
		s.cylinder(0.022, 0.045, 0.07, BuildingArt.GOLD, Vector3(0.0, y + 0.07, 0.0), 8)
		s.cylinder(0.0, 0.13, 0.14 * look.pitch, look.roof_color.darkened(0.15), Vector3(0.0, y + 0.13 + 0.07 * look.pitch, 0.0), 4, Vector3(0.0, PI / 4.0, 0.0))
		return
	for k: int in look.towers:
		_tower(s, look, Vector3(-0.36 if k == 0 else 0.36, 0.0, -0.18), 0.1, h + 0.45 * look.pitch)


## A paved square of three stalls under awnings striped in the style's trim; banners on poles
## when the style flies them.
static func _market(s: BuildingArt.Shapes, look: Look) -> void:
	s.box(Vector3(1.2, 0.02, 0.86), look.wall.lerp(Color(0.82, 0.72, 0.60), 0.6), Vector3(0.0, 0.01, 0.0))
	var stripes: Array[Color] = [look.trim, look.wall.lightened(0.3)]
	if look.is_grim():
		stripes = [BuildingArt.STEEL, BuildingArt.COLD_DARK]
	elif look.ornament == "painted":
		stripes = [look.trim, look.tint]
	var post := BuildingArt.TIMBER if look.material in ["daub", "timber", "stone"] else BuildingArt.IRON
	var goods: Array = [
		[Color(0.90, 0.36, 0.30), Color(0.96, 0.74, 0.30), Color(0.52, 0.76, 0.36)],
		[Color(0.42, 0.56, 0.84), Color(0.90, 0.84, 0.70), Color(0.72, 0.36, 0.56)],
		[Color(0.84, 0.62, 0.38), Color(0.66, 0.42, 0.28), Color(0.92, 0.88, 0.78)],
	]
	for k: int in 3:
		var turn := (1 - k) * 0.4
		s.frame = Transform3D(Basis(Vector3.UP, turn), Vector3((k - 1) * 0.38, 0.0, -0.06 - 0.12 * float(k == 1)))
		s.box(Vector3(0.34, 0.14, 0.13), look.wall.lightened(0.1) if post == BuildingArt.IRON else BuildingArt.TIMBER.lightened(0.15), Vector3(0.0, 0.07, 0.07))
		for x: float in [-0.16, 0.16]:
			s.box(Vector3(0.025, 0.36, 0.025), post, Vector3(x, 0.18, 0.13))
			s.box(Vector3(0.025, 0.42, 0.025), post, Vector3(x, 0.21, -0.12))
		for stripe: int in 4:
			var color: Color = stripes[stripe % 2]
			s.box(Vector3(0.1, 0.018, 0.34), color, Vector3(-0.15 + stripe * 0.1, 0.4, 0.0), Vector3(-0.2, 0.0, 0.0))
			s.box(Vector3(0.1, 0.05, 0.01), color, Vector3(-0.15 + stripe * 0.1, 0.345, 0.17))
		var wares: Array = goods[k]
		for g: int in 5:
			s.sphere(0.028, wares[g % 3], Vector3(-0.12 + g * 0.06, 0.165, 0.07 + 0.02 * (g % 2)))
	s.frame = Transform3D.IDENTITY
	if look.ornament in ["banners", "gilded"]:
		for x: float in [-0.56, 0.56]:
			s.cylinder(0.008, 0.01, 0.6, BuildingArt.IRON, Vector3(x, 0.3, 0.36), 4)
			s.box(Vector3(0.012, 0.18, 0.08), look.tint, Vector3(x, 0.48, 0.32))
			s.sphere(0.018, look.accent(), Vector3(x, 0.61, 0.36))


# --- Modules ------------------------------------------------------------------------

## Walls of a w by d block h high on a plinth, with the material's details, a row of windows on
## each floor front and back, and doors (x positions) on the front. at shifts the whole block.
static func _block(s: BuildingArt.Shapes, look: Look, w: float, d: float, h: float, floors: int, doors: Array, rng: RandomNumberGenerator, at: Vector3 = Vector3.ZERO) -> void:
	s.box(Vector3(w + 0.06, 0.05, d + 0.06), look.base(), at + Vector3(0.0, 0.025, 0.0))
	s.box(Vector3(w, h, d), look.wall, at + Vector3(0.0, 0.05 + h / 2.0, 0.0))
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	match look.material:
		"daub":
			s.box(Vector3(w + 0.012, 0.06, d + 0.012), look.base().lightened(0.15), at + Vector3(0.0, 0.08, 0.0))
		"timber":
			for corner: Vector2 in corners:
				s.box(Vector3(0.045, h, 0.045), BuildingArt.TIMBER, at + Vector3(corner.x * w / 2.0, 0.05 + h / 2.0, corner.y * d / 2.0))
			for floor: int in range(1, floors + 1):
				s.box(Vector3(w + 0.012, 0.03, d + 0.012), BuildingArt.TIMBER, at + Vector3(0.0, 0.05 + h * floor / floors - 0.015, 0.0))
		"stone":
			for corner: Vector2 in corners:
				var blocks := maxi(roundi(h / 0.09), 2)
				for k: int in blocks:
					var long := k % 2 == 0
					s.box(Vector3(0.09 if long else 0.06, h / blocks * 0.92, 0.06 if long else 0.09), look.wall.lightened(0.16),
						at + Vector3(corner.x * (w / 2.0 - 0.02), 0.05 + h * (k + 0.5) / blocks, corner.y * (d / 2.0 - 0.02)))
		"plaster":
			for corner: Vector2 in corners:
				s.box(Vector3(0.05, h, 0.05), look.wall.lightened(0.14), at + Vector3(corner.x * w / 2.0, 0.05 + h / 2.0, corner.y * d / 2.0))
			s.box(Vector3(w + 0.03, 0.035, d + 0.03), look.wall.lightened(0.18), at + Vector3(0.0, 0.05 + h - 0.0175, 0.0))
		"brick":
			for floor: int in range(1, floors + 1):
				s.box(Vector3(w + 0.012, 0.022, d + 0.012), BuildingArt.PLASTER, at + Vector3(0.0, 0.05 + h * floor / floors - 0.03, 0.0))
		"concrete":
			for floor: int in range(1, floors + 1):
				s.box(Vector3(w + 0.025, 0.03, d + 0.025), look.wall.lightened(0.14), at + Vector3(0.0, 0.05 + h * floor / floors - 0.015, 0.0))
	var lit_share := 0.25 if look.is_grim() else 0.55
	var columns := maxi(int(w / 0.2), 1)
	for floor: int in floors:
		var y := 0.05 + h * (floor + 0.55) / floors
		for c: int in columns:
			var x := -w / 2.0 + w * (c + 0.5) / columns
			var by_door := floor == 0 and doors.any(func(door: float) -> bool: return absf(door - x) < 0.1)
			for side: float in [1.0, -1.0]:
				if by_door and side > 0.0:
					continue
				var lit := rng.randf() < lit_share
				var size := Vector3(0.035, 0.11, 0.02) if look.is_grim() else Vector3(0.08, minf(0.12, h / floors * 0.45), 0.02)
				var spot := at + Vector3(x, y, side * (d / 2.0 + 0.004))
				if look.ornament == "painted" and side > 0.0:
					s.box(size + Vector3(0.03, 0.03, -0.008), look.trim, spot - Vector3(0.0, 0.0, 0.004))
				s.box(size, BuildingArt.LAMP if lit else BuildingArt.GLASS_DARK, spot, Vector3.ZERO, lit)
	var frame := look.accent() if look.ornament in ["carved", "painted", "gilded"] else (BuildingArt.IRON if look.is_grim() else look.base())
	var leaf := look.tint.darkened(0.45)
	if look.is_grim():
		leaf = BuildingArt.DOORWAY
	elif look.ornament == "painted":
		# Painted fronts: doors in the tribe's color and a band of color along the plinth.
		leaf = look.tint.darkened(0.1)
		s.box(Vector3(w + 0.014, 0.035, d + 0.014), look.trim, at + Vector3(0.0, 0.07, 0.0))
	for door: float in doors:
		var door_h := minf(0.2, h / floors * 0.8)
		s.box(Vector3(0.15, door_h + 0.03, 0.02), frame, at + Vector3(door, 0.05 + door_h / 2.0 + 0.008, d / 2.0 + 0.004))
		s.box(Vector3(0.11, door_h, 0.03), leaf, at + Vector3(door, 0.05 + door_h / 2.0, d / 2.0 + 0.008))


## A roof module over a w by d footprint with its eaves at height y; the ridge runs along x
## (along z when ridge_x is false). shape overrides the style's roof. Returns the height of its top.
static func _roof(s: BuildingArt.Shapes, look: Look, w: float, d: float, y: float, ridge_x: bool, at: Vector3 = Vector3.ZERO, shape: String = "") -> float:
	var long := maxf(w, d) > minf(w, d) * LONG
	var span := d if ridge_x else w
	var length := w if ridge_x else d
	match shape if shape else look.roof:
		"gable":
			var h := span * 0.55 * look.pitch
			s.prism(Vector3(span + OVERHANG, h, length + OVERHANG), look.roof_color, at + Vector3(0.0, y + h / 2.0, 0.0), PI / 2.0 if ridge_x else 0.0)
			return y + h
		"cone":
			var h := maxf(w, d) * 0.42 * look.pitch
			_pyramid(s, look.roof_color, at + Vector3(0.0, y, 0.0), (w + OVERHANG) / 2.0, (d + OVERHANG) / 2.0, h)
			return y + h
		"spire":
			if long:
				# A steep gable with a needle at each end.
				var h := span * 1.1 * look.pitch
				s.prism(Vector3(span + OVERHANG, h, length + OVERHANG), look.roof_color, at + Vector3(0.0, y + h / 2.0, 0.0), PI / 2.0 if ridge_x else 0.0)
				for end: float in [-0.5, 0.5]:
					var tip := at + (Vector3(end * length, 0.0, 0.0) if ridge_x else Vector3(0.0, 0.0, end * length))
					_finial(s, look, y + h, tip, 0.14)
				return y + h + 0.14
			var h := maxf(w, d) * 1.35 * look.pitch
			_pyramid(s, look.roof_color, at + Vector3(0.0, y, 0.0), (w + OVERHANG) / 2.0, (d + OVERHANG) / 2.0, h)
			_finial(s, look, y + h, at, 0.16)
			return y + h + 0.16
		"dome":
			s.box(Vector3(w + OVERHANG, 0.04, d + OVERHANG), look.wall.darkened(0.1), at + Vector3(0.0, y + 0.02, 0.0))
			if long:
				var r := span / 2.0
				s.cylinder(r, r, length - 0.04, look.roof_color, at + Vector3(0.0, y + 0.04, 0.0), 10, Vector3(0.0, 0.0, PI / 2.0) if ridge_x else Vector3(PI / 2.0, 0.0, 0.0))
				return y + 0.04 + r
			var radius := minf(w, d) / 2.0 * 0.92
			s.sphere(radius, look.roof_color, at + Vector3(0.0, y + 0.04, 0.0), Vector3(1.0, 0.9 * look.pitch, 1.0))
			var top := y + 0.04 + radius * 0.9 * look.pitch
			if look.ornament in ["gilded", "carved"]:
				_finial(s, look, top, at, 0.08)
				return top + 0.08
			return top
		"stepped":
			var tier := 0.075 * look.pitch
			for k: int in 3:
				var shrink := 1.0 - 0.27 * k
				s.box(Vector3((w + OVERHANG) * shrink, tier, (d + OVERHANG) * shrink), look.roof_color.darkened(0.06 * k), at + Vector3(0.0, y + tier * (k + 0.5), 0.0))
			return y + tier * 3.0
	# Flat: a slab and a low parapet.
	s.box(Vector3(w + 0.04, 0.05, d + 0.04), look.roof_color, at + Vector3(0.0, y + 0.025, 0.0))
	var rim := look.wall.darkened(0.12)
	for side: float in [-1.0, 1.0]:
		s.box(Vector3(w + 0.04, 0.05, 0.03), rim, at + Vector3(0.0, y + 0.075, side * (d / 2.0 + 0.005)))
		s.box(Vector3(0.03, 0.05, d + 0.04), rim, at + Vector3(side * (w / 2.0 + 0.005), y + 0.075, 0.0))
	return y + 0.1


## Decoration on a block's front (and its eaves): w by d, eaves at height y, roof top at top.
static func _ornament(s: BuildingArt.Shapes, look: Look, w: float, d: float, y: float, top: float, at: Vector3 = Vector3.ZERO) -> void:
	var front := at.z + d / 2.0 + 0.008
	match look.ornament:
		"carved":
			s.box(Vector3(w + 0.02, 0.035, d + 0.02), look.trim, at + Vector3(0.0, y - 0.02, 0.0))
			var count := maxi(int(w / 0.12), 3)
			for k: int in count:
				s.box(Vector3(0.03, 0.04, 0.03), look.trim.darkened(0.15), Vector3(at.x - w / 2.0 + w * (k + 0.5) / count, y - 0.055, front))
		"painted":
			var count := maxi(int(w / 0.085), 4)
			for k: int in count:
				var color := look.trim if k % 2 == 0 else look.tint
				var x := at.x - w / 2.0 + w * (k + 0.5) / count
				s.box(Vector3(w / count * 0.8, 0.04, 0.012), color, Vector3(x, y - 0.035, front))
				s.box(Vector3(w / count * 0.8, 0.04, 0.012), color, Vector3(x, y - 0.035, at.z - d / 2.0 - 0.008))
		"banners":
			var hang := minf(0.26, (y - 0.05) * 0.6)
			for side: float in [-0.3, 0.3]:
				s.box(Vector3(0.09, hang, 0.012), look.tint, Vector3(at.x + side * w, y - 0.02 - hang / 2.0, front))
				s.prism(Vector3(0.09, 0.05, 0.012), look.tint, Vector3(at.x + side * w, y - 0.02 - hang - 0.025, front), 0.0, 0.5, PI)
				s.box(Vector3(0.1, 0.02, 0.016), look.trim, Vector3(at.x + side * w, y - 0.02, front + 0.002))
		"gilded":
			s.box(Vector3(w + 0.02, 0.03, d + 0.02), BuildingArt.GOLD, at + Vector3(0.0, y - 0.018, 0.0))
			s.sphere(0.03, BuildingArt.GOLD, Vector3(at.x, y - 0.07, front + 0.01))
			if top > y + 0.12:
				_finial(s, look, top, at, 0.0)
		"grim":
			s.box(Vector3(w + 0.02, 0.04, d + 0.02), BuildingArt.IRON, at + Vector3(0.0, y - 0.02, 0.0))
			for x: float in [-0.42, 0.42]:
				s.box(Vector3(0.035, (y - 0.05) * 0.85, 0.02), look.wall.darkened(0.3), Vector3(at.x + x * w, 0.05 + (y - 0.05) * 0.45, front))


## A tower standing at a point: round for daub, stone and plaster, square for the rest, banded in
## the trim, lit by one window, under a small version of the style's roof.
static func _tower(s: BuildingArt.Shapes, look: Look, at: Vector3, radius: float, height: float) -> void:
	var rounded := look.material in ["daub", "stone", "plaster"]
	if rounded:
		s.cylinder(radius * 0.9, radius, height, look.wall, at + Vector3(0.0, height / 2.0, 0.0), 10)
	else:
		s.box(Vector3(radius * 1.8, height, radius * 1.8), look.wall, at + Vector3(0.0, height / 2.0, 0.0))
	var band := look.accent() if not look.is_grim() else BuildingArt.IRON
	if rounded:
		s.cylinder(radius * 1.05, radius * 1.05, 0.04, band, at + Vector3(0.0, height - 0.02, 0.0), 10)
	else:
		s.box(Vector3(radius * 1.9, 0.04, radius * 1.9), band, at + Vector3(0.0, height - 0.02, 0.0))
	s.box(Vector3(0.03, 0.08, 0.02), BuildingArt.LAMP, at + Vector3(0.0, height * 0.7, radius * 0.92), Vector3.ZERO, true)
	var y := at.y + height
	var top := y
	match look.roof:
		"cone":
			s.cylinder(0.0, radius * 1.3, radius * 2.0 * look.pitch, look.roof_color, Vector3(at.x, y + radius * look.pitch, at.z), 10 if rounded else 4, Vector3(0.0, 0.0 if rounded else PI / 4.0, 0.0))
			top = y + radius * 2.0 * look.pitch
		"gable":
			s.cylinder(0.0, radius * 1.35, radius * 1.6 * look.pitch, look.roof_color, Vector3(at.x, y + radius * 0.8 * look.pitch, at.z), 4, Vector3(0.0, PI / 4.0, 0.0))
			top = y + radius * 1.6 * look.pitch
		"spire":
			s.cylinder(0.0, radius * 1.15, radius * 4.5 * look.pitch, look.roof_color, Vector3(at.x, y + radius * 2.25 * look.pitch, at.z), 8 if rounded else 4, Vector3(0.0, 0.0 if rounded else PI / 4.0, 0.0))
			top = y + radius * 4.5 * look.pitch
		"dome":
			s.sphere(radius * 1.05, look.roof_color, Vector3(at.x, y, at.z), Vector3(1.0, 1.0 * look.pitch, 1.0))
			top = y + radius * 1.05 * look.pitch
		"stepped":
			for k: int in 2:
				var width := radius * (2.1 - 0.6 * k)
				s.box(Vector3(width, 0.06, width), look.roof_color.darkened(0.06 * k), Vector3(at.x, y + 0.03 + 0.06 * k, at.z))
			top = y + 0.12
		_:
			for k: int in 4:
				var angle := TAU * k / 4.0 + PI / 4.0
				s.box(Vector3(0.05, 0.06, 0.05), look.wall.darkened(0.12), Vector3(at.x + sin(angle) * radius * 0.8, y + 0.03, at.z + cos(angle) * radius * 0.8))
			top = y + 0.06
	if look.ornament in ["gilded", "carved"] or look.roof == "spire":
		_finial(s, look, top, Vector3(at.x, 0.0, at.z), 0.06)
	elif look.ornament == "banners":
		s.cylinder(0.006, 0.006, 0.2, BuildingArt.IRON, Vector3(at.x, top + 0.1, at.z), 4)
		s.box(Vector3(0.1, 0.06, 0.008), look.tint, Vector3(at.x + 0.05, top + 0.16, at.z))


## A needle and a ball on a roof's tip at height y over a point (x and z of at).
static func _finial(s: BuildingArt.Shapes, look: Look, y: float, at: Vector3 = Vector3.ZERO, needle: float = 0.08) -> void:
	if needle > 0.0:
		s.cylinder(0.006, 0.012, needle, look.accent(), Vector3(at.x, y + needle / 2.0, at.z), 4)
	s.sphere(0.022, look.accent(), Vector3(at.x, y + needle, at.z))


## A hipped (four-sided) roof: a pyramid from a hx by hz base at a point, h high.
static func _pyramid(s: BuildingArt.Shapes, color: Color, base: Vector3, hx: float, hz: float, h: float) -> void:
	var shape := Basis.from_scale(Vector3(hx * sqrt(2.0), h, hz * sqrt(2.0))) * Basis(Vector3.UP, PI / 4.0)
	s.add(BuildingArt._primitive("cylinder|0.000|1.000|4"), color, Transform3D(shape, base + Vector3(0.0, h / 2.0, 0.0)))
