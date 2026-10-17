extends SceneTree
## Paints the villager skins for Kenney's animated character (art/characters/kenney/) from its
## UV layout: a knee-length tunic with collar and belt, bare forearms, linen leggings with wraps,
## leather shoes. The face and hair come from Kenney's skater skins.
##   godot --headless --path Godot -s res://tools/paint_villager_skins.gd
## Each skin has a mask: red = tunic (tribe color), green = hair, blue = skin tone. Masked areas
## hold only brightness; the villager shader multiplies in the colors.

const SOURCES := {"male": "res://art/characters/kenney/skaterMaleA.png", "female": "res://art/characters/kenney/skaterFemaleA.png"}
const OUT_DIR := "res://art/characters/"
const SIZE := 1024
# UV regions, in pixels of the 1024 texture (found by painting each region a flat color).
const HEAD := Rect2i(0, 0, 640, 490)
const TORSO := Rect2i(0, 490, 640, 534) ## wraps around the chest and upper arms; the waist is at the bottom
const FOREARMS: Array[Rect2i] = [Rect2i(0, 490, 150, 534), Rect2i(490, 490, 150, 534)]
const SHOES := Rect2i(640, 136, 180, 388)
const HANDS: Array[Rect2i] = [Rect2i(820, 136, 204, 388), Rect2i(640, 524, 384, 236)] ## hands and fingers
const LEGS := Rect2i(610, 760, 414, 264) ## the waist is at the top
const SKIRT_END := 835 ## the tunic hangs down over the top of the legs to here

const INK := Color(0.16, 0.10, 0.20)
const LEATHER := Color(0.42, 0.27, 0.18)
const LINEN := Color(0.80, 0.72, 0.58)
const WRAP := Color(0.55, 0.42, 0.30)
const PEACH := Color(0.96, 0.60, 0.47) ## the source skins' average skin color


func _initialize() -> void:
	for look: String in SOURCES:
		var source := (load(SOURCES[look]) as Texture2D).get_image()
		source.convert(Image.FORMAT_RGBA8)
		var skin := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
		var mask := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
		for y: int in SIZE:
			for x: int in SIZE:
				var painted := _paint(source, x, y)
				skin.set_pixel(x, y, painted[0])
				mask.set_pixel(x, y, painted[1])
		skin.save_png(OUT_DIR + "villager_%s_skin.png" % look)
		mask.save_png(OUT_DIR + "villager_%s_mask.png" % look)
		print("Painted ", look)
	quit()


## [color, mask] for one pixel.
func _paint(source: Image, x: int, y: int) -> Array[Color]:
	var at := Vector2i(x, y)
	var original := source.get_pixel(x, y)
	if HEAD.has_point(at):
		return _head(original)
	if FOREARMS[0].has_point(at) or FOREARMS[1].has_point(at) or HANDS[0].has_point(at) or HANDS[1].has_point(at):
		return _skin(1.0)
	if TORSO.has_point(at):
		return _tunic(x, y)
	if SHOES.has_point(at):
		# Keep the shoe's drawn shapes as light and dark leather.
		return [LEATHER * (0.75 + 0.4 * original.get_luminance()), Color.BLACK]
	if LEGS.has_point(at):
		return _legs(x, y)
	return _tunic(x, y)


func _head(original: Color) -> Array[Color]:
	var hue_distance := absf(original.r - PEACH.r) + absf(original.g - PEACH.g) + absf(original.b - PEACH.b)
	if hue_distance < 0.35:
		return _skin(original.get_luminance() / PEACH.get_luminance())
	var accessory := original.g > original.r + 0.15 # the skater's teal hair clip becomes hair
	if accessory or (original.get_luminance() < 0.2 and original.r > original.b):
		# Hair: dark brown or black. Brightness only, normalized so the average hair is ~0.8.
		return [Color.WHITE * clampf(0.55 + original.get_luminance() * 3.0, 0.0, 1.0), Color(0, 1, 0)]
	return [original, Color.BLACK] # eyes, brows, mouth


func _skin(brightness: float) -> Array[Color]:
	return [Color.WHITE * clampf(0.9 * brightness, 0.0, 1.0), Color(0, 0, 1)]


func _tunic(x: int, y: int) -> Array[Color]:
	var tunic: Array[Color] = [Color.WHITE * 0.9, Color(1, 0, 0)]
	if y < TORSO.position.y + 18:
		return [LINEN.darkened(0.15), Color.BLACK] # collar
	if y > TORSO.end.y - 66 and y < TORSO.end.y - 40:
		return [LINEN if absi(x - 320) < 16 else LEATHER, Color.BLACK] # belt and buckle
	# A soft vertical fold every so often, so the cloth doesn't read as plastic.
	tunic[0] *= 0.94 + 0.06 * cos(x * TAU / 80.0)
	return tunic


func _legs(x: int, y: int) -> Array[Color]:
	if y < SKIRT_END - 8:
		return _tunic(x, y)
	if y < SKIRT_END:
		return [Color.WHITE * 0.7, Color(1, 0, 0)] # darker hem
	# Leggings with leather wraps crossing below the knee.
	if y > 880 and posmod(y + (x % 207) / 4, 34) < 7:
		return [WRAP, Color.BLACK]
	return [LINEN * (0.95 + 0.05 * cos(x * TAU / 60.0)), Color.BLACK]
