class_name EmblemArt
extends RefCounted
## Turns AI-authored (or offline) emblems into pictures: banners, propaganda posters and temple
## plaques are composed as SVG from clean parts (see SvgGuard), in palette tokens, and rasterized
## with Image.load_svg_from_string. Textures are cached by content, so a banner seen on the island
## and in the tribe panel is drawn once. The pictures go on toon materials, so they take the
## island's light and brush strokes like everything else.

const SCALE := 2.0 ## pixels per SVG unit
const MAX_CACHED := 96
const INK := 31
const GOLD := 17

static var _textures: Dictionary = {} ## hash of the SVG -> ImageTexture
static var _materials: Dictionary = {} ## texture instance id -> ShaderMaterial


## A composed or clean SVG (palette tokens and all) as a texture, cached by content.
static func texture(svg: String, scale: float = SCALE) -> ImageTexture:
	var key := hash([svg, scale])
	if _textures.has(key):
		return _textures[key]
	var image := Image.new()
	if svg.is_empty() or image.load_svg_from_string(SvgGuard.renderable(svg), scale) != OK or image.is_empty():
		image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(ArtPalette.color(INK))
	image.generate_mipmaps()
	if _textures.size() >= MAX_CACHED:
		_textures.clear() # what is on screen keeps its own reference
		_materials.clear()
	_textures[key] = ImageTexture.create_from_image(image)
	return _textures[key]


## A banner hanging from a crossbar: the field, a gold trim, the emblem, and a band of the
## emblem's own colors at the foot. 64 by 80 units.
static func banner_svg(spec: Dictionary) -> String:
	var field := int(spec.get("field", INK))
	var trim := GOLD if EmblemGrammar.lightness(field) < 0.6 else INK
	return ('<svg viewBox="0 0 64 80" width="64" height="80"><rect x="0" y="0" width="64" height="80" fill="p%d"/>' \
		+ '<g fill="p%d" transform="translate(7 8) scale(0.78)">%s</g>' \
		+ '<rect x="3" y="3" width="58" height="74" fill="none" stroke="p%d" stroke-width="2.5"/>' \
		+ '<polygon points="3,66 32,74 61,66 61,77 3,77" fill="p%d"/></svg>') % [field, INK, SvgGuard.inner(String(spec.get("emblem", ""))), trim, _second_color(spec, field)]


## A propaganda poster: the paper, a frame, the motif, and a band of print at the foot where the
## slogan is lettered (the view letters it, so it stays readable). 64 by 88 units.
static func poster_svg(spec: Dictionary) -> String:
	var ground := int(spec.get("ground", 22))
	var ink := int(spec.get("ink", 30))
	return ('<svg viewBox="0 0 64 88" width="64" height="88"><rect x="0" y="0" width="64" height="88" fill="p%d"/>' \
		+ '<rect x="3" y="3" width="58" height="82" fill="none" stroke="p%d" stroke-width="2"/>' \
		+ '<g fill="p%d" transform="translate(8 7) scale(0.75)">%s</g>' \
		+ '<rect x="3" y="58" width="58" height="27" fill="p%d"/></svg>') % [ground, ink, ink, SvgGuard.inner(String(spec.get("emblem", ""))), ink]


## A temple's plaque: its holy sign in gold on a dark roundel, 64 by 64 units.
static func plaque_svg(icon: String) -> String:
	var emblem := SvgGuard.sanitize(EmblemGrammar.emblem(icon, GOLD, 30, hash(icon)))
	return ('<svg viewBox="0 0 64 64" width="64" height="64"><rect x="0" y="0" width="64" height="64" fill="p%d"/>' \
		+ '<circle cx="32" cy="32" r="29" fill="p27" stroke="p%d" stroke-width="3"/>' \
		+ '<g transform="translate(13 13) scale(0.6)">%s</g></svg>') % [22, GOLD, SvgGuard.inner(emblem)]


static func banner_texture(spec: Dictionary) -> ImageTexture:
	return texture(banner_svg(spec))


static func poster_texture(spec: Dictionary) -> ImageTexture:
	return texture(poster_svg(spec))


## A toon material showing a texture (one per texture; banners and posters don't gather snow).
static func material(picture: Texture2D) -> ShaderMaterial:
	var key := picture.get_instance_id()
	if not _materials.has(key):
		var painted := ToonMaterials.get_material(Color.WHITE, 0.0).duplicate() as ShaderMaterial
		painted.set_shader_parameter("albedo_texture", picture)
		painted.set_shader_parameter("snow", 0.0)
		_materials[key] = painted
	return _materials[key]


## The emblem's most used color other than the field, for the banner's foot.
static func _second_color(spec: Dictionary, field: int) -> int:
	var counts := {}
	for found: RegExMatch in RegEx.create_from_string('"p(\\d+)"').search_all(String(spec.get("emblem", ""))):
		var index := found.get_string(1).to_int()
		if index != field:
			counts[index] = int(counts.get(index, 0)) + 1
	var best := GOLD if field != GOLD else INK
	var most := 0
	for index: int in counts:
		if int(counts[index]) > most:
			best = index
			most = counts[index]
	return best
