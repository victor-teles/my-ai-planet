class_name UiIcons
extends RefCounted
## The HUD's ink-stamp icons: small two-tone drawings (an ink line over a painted fill) on a
## 24-unit grid, kept here as SVG and rasterized when first used. Each texture is drawn several
## times larger than it reports itself (a size override), so it stays crisp when the window
## scales the canvas up (1080p, retina).

const OVERSAMPLE := 4.0
const INK := "#291a33"
const LINE := "stroke='#291a33' stroke-width='1.7' stroke-linejoin='round' stroke-linecap='round'"

## name -> the SVG body on a 24x24 grid.
const SHAPES := {
	# Miracles
	"rain": "<path d='M6.5 14.5h11a3.6 3.6 0 0 0 .2-7.2A5.2 5.2 0 0 0 7.8 6.4 4.1 4.1 0 0 0 6.5 14.5z' fill='#e4ecf8' %s/><path d='M8.3 17.6l-1 2.6M12.3 17.6l-1 2.6M16.3 17.6l-1 2.6' stroke='#3f73c4' stroke-width='2' stroke-linecap='round'/>",
	"harvest": "<path d='M12 21.5V8.5' %s fill='none'/><g fill='#eab64c' %s><ellipse cx='12' cy='5.2' rx='1.7' ry='2.6'/><ellipse cx='9.3' cy='9' rx='1.6' ry='2.6' transform='rotate(-32 9.3 9)'/><ellipse cx='14.7' cy='9' rx='1.6' ry='2.6' transform='rotate(32 14.7 9)'/><ellipse cx='9.3' cy='13' rx='1.6' ry='2.6' transform='rotate(-32 9.3 13)'/><ellipse cx='14.7' cy='13' rx='1.6' ry='2.6' transform='rotate(32 14.7 13)'/></g><path d='M12 18.5l-3.5 2.5M12 18.5l3.5 2.5' %s fill='none'/>",
	"drought": "<circle cx='12' cy='12' r='4.3' fill='#f2a33a' %s/><path d='M12 2.6v2.6M12 18.8v2.6M2.6 12h2.6M18.8 12h2.6M5.4 5.4l1.8 1.8M16.8 16.8l1.8 1.8M5.4 18.6l1.8-1.8M16.8 7.2l1.8-1.8' %s fill='none'/>",
	"plague": "<path d='M12 3.3a7.3 7.3 0 0 0-7.3 7.3c0 2.7 1.4 4.5 3.2 5.4v3.4h8.2V16c1.8-.9 3.2-2.7 3.2-5.4A7.3 7.3 0 0 0 12 3.3z' fill='#d3e3b2' %s/><circle cx='9.3' cy='10.8' r='1.7' fill='#291a33'/><circle cx='14.7' cy='10.8' r='1.7' fill='#291a33'/><path d='M10.6 19.4v-2.2M13.4 19.4v-2.2' %s fill='none'/>",
	"muse": "<path d='M11 3.2l1.9 6.4 6.4 1.9-6.4 1.9-1.9 6.4-1.9-6.4-6.4-1.9 6.4-1.9z' fill='#bfa8f2' %s/><path d='M18.5 2.8l.7 2.1 2.1.7-2.1.7-.7 2.1-.7-2.1-2.1-.7 2.1-.7z' fill='#f2c14e' stroke='#291a33' stroke-width='1.1' stroke-linejoin='round'/>",
	"smite": "<path d='M13.8 2.4L5.2 13.6h5.6l-1.6 8 9.1-11.8h-5.8z' fill='#f6d24a' %s/>",
	"awaken": "<path d='M2.4 12s3.6-6.6 9.6-6.6 9.6 6.6 9.6 6.6-3.6 6.6-9.6 6.6S2.4 12 2.4 12z' fill='#fffaf0' %s/><circle cx='12' cy='12' r='3.4' fill='#5f97c6' %s/><circle cx='12' cy='12' r='1.3' fill='#291a33'/>",
	"sanctify": "<ellipse cx='12' cy='4' rx='5.2' ry='1.7' fill='none' stroke='#e2a72e' stroke-width='1.9'/><path d='M4 19.5l1.4-9.2 4 3.8L12 8l2.6 6.1 4-3.8 1.4 9.2z' fill='#f2c14e' %s/>",
	# Navigation and actions
	"feed": "<path d='M3 5.6c3-1.1 6-1 9 .9 3-1.9 6-2 9-.9v13c-3-1.1-6-1-9 .9-3-1.9-6-2-9-.9z' fill='#fffaf0' %s/><path d='M12 6.5v13.3M6 9.4c1.3-.3 2.6-.2 3.8.3M6 12.4c1.3-.3 2.6-.2 3.8.3M14.2 9.7c1.2-.5 2.5-.6 3.8-.3M14.2 12.7c1.2-.5 2.5-.6 3.8-.3' %s fill='none'/>",
	"genes": "<path d='M7 2.8c0 5.2 10 4.4 10 9.2s-10 4-10 9.2' fill='none' stroke='#c2504a' stroke-width='2' stroke-linecap='round'/><path d='M17 2.8c0 5.2-10 4.4-10 9.2s10 4 10 9.2' fill='none' stroke='#3f73c4' stroke-width='2' stroke-linecap='round'/><path d='M9 6.4h6M9 17.6h6M10.3 12h3.4' %s fill='none'/>",
	"society": "<path d='M2.8 9.2L12 3.6l9.2 5.6z' fill='#f2c14e' %s/><path d='M5.6 11.2v6.6M9.9 11.2v6.6M14.1 11.2v6.6M18.4 11.2v6.6' %s fill='none'/><path d='M3 20.4h18' %s fill='none'/>",
	"oracle": "<circle cx='12' cy='10.2' r='7' fill='#c9b6f2' %s/><path d='M9.6 6.8l.7 1.7 1.7.7-1.7.7-.7 1.7-.7-1.7-1.7-.7 1.7-.7z' fill='#fffaf0'/><path d='M6.6 21h10.8l-1.6-3.6H8.2z' fill='#c49a6c' %s/>",
	"help": "<circle cx='12' cy='12' r='9.2' fill='#fffaf0' %s/><path d='M9.4 9.6a2.7 2.7 0 1 1 3.8 2.5c-.8.4-1.2 1-1.2 1.8v.6' %s fill='none'/><circle cx='12' cy='17.3' r='1.1' fill='#291a33'/>",
	"close": "<path d='M6.5 6.5l11 11M17.5 6.5l-11 11' stroke='#291a33' stroke-width='2.2' stroke-linecap='round'/>",
	"pause": "<rect x='6.4' y='5' width='3.9' height='14' rx='1.2' fill='#291a33'/><rect x='13.7' y='5' width='3.9' height='14' rx='1.2' fill='#291a33'/>",
	"play": "<path d='M7.5 4.8v14.4c0 .7.8 1.1 1.4.7l10.4-7.2c.5-.4.5-1.1 0-1.4L8.9 4.1c-.6-.4-1.4 0-1.4.7z' fill='#291a33'/>",
	"filter": "<path d='M3.6 5h16.8l-6.4 7.6v6.2l-4-2v-4.2z' fill='#fffaf0' %s/>",
	"chevron_down": "<path d='M6.5 9.5l5.5 5.5 5.5-5.5' fill='none' stroke='#291a33' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'/>",
	"chevron_up": "<path d='M6.5 14.5L12 9l5.5 5.5' fill='none' stroke='#291a33' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'/>",
	"expand": "<path d='M5 9.5L12 4l7 5.5M5 14.5L12 20l7-5.5' fill='none' stroke='#291a33' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/>",
	"compact": "<path d='M5 4.5L12 10l7-5.5M5 19.5L12 14l7 5.5' fill='none' stroke='#291a33' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/>",
	"hourglass": "<path d='M6.5 3h11M6.5 21h11' %s fill='none'/><path d='M8 3.2v1.6c0 3 4 4.6 4 7.2s-4 4.2-4 7.2v1.6h8v-1.6c0-3-4-4.6-4-7.2s4-4.2 4-7.2V3.2z' fill='#fffaf0' %s/><path d='M9.6 19.4c.5-1.6 2.4-2.6 2.4-2.6s1.9 1 2.4 2.6z' fill='#eab64c'/>",
	"person": "<circle cx='12' cy='7.4' r='3.6' fill='#f2c7a0' %s/><path d='M4.8 20.6c0-4.2 3.2-6.8 7.2-6.8s7.2 2.6 7.2 6.8z' fill='#d9825b' %s/>",
	"target": "<circle cx='12' cy='12' r='7.4' fill='#fffaf0' %s/><circle cx='12' cy='12' r='2.6' fill='#e0533f' %s/><path d='M12 1.8v3.4M12 18.8v3.4M1.8 12h3.4M18.8 12h3.4' %s fill='none'/>",
	"star": "<path d='M12 2.4l2.5 7.1 7.1 2.5-7.1 2.5-2.5 7.1-2.5-7.1L2.4 12l7.1-2.5z' fill='#f2b53e' %s/>",
	"flag": "<path d='M6 21.2V3.4' %s fill='none'/><path d='M6 4h11.5l-2.6 4.2 2.6 4.2H6z' fill='#e0533f' %s/>",
	"omen": "<path d='M12 3.2L21.4 19.6H2.6z' fill='#f6d24a' %s/><path d='M12 9v5' stroke='#291a33' stroke-width='2.2' stroke-linecap='round'/><circle cx='12' cy='16.9' r='1.2' fill='#291a33'/>",
	"skull": "<path d='M12 3.3a7.3 7.3 0 0 0-7.3 7.3c0 2.7 1.4 4.5 3.2 5.4v3.4h8.2V16c1.8-.9 3.2-2.7 3.2-5.4A7.3 7.3 0 0 0 12 3.3z' fill='#e9dfe6' %s/><circle cx='9.3' cy='10.8' r='1.7' fill='#291a33'/><circle cx='14.7' cy='10.8' r='1.7' fill='#291a33'/>",
	"bloom": "<g fill='#f2a0b4' %s><circle cx='12' cy='6.6' r='3.2'/><circle cx='17.1' cy='10.4' r='3.2'/><circle cx='15.2' cy='16.4' r='3.2'/><circle cx='8.8' cy='16.4' r='3.2'/><circle cx='6.9' cy='10.4' r='3.2'/></g><circle cx='12' cy='12' r='2.6' fill='#f2c14e' %s/>",
	"drop": "<path d='M12 3.2c3.4 4.4 6 7.6 6 10.8a6 6 0 0 1-12 0c0-3.2 2.6-6.4 6-10.8z' fill='#f2a33a' %s/>",
	"smog": "<path d='M4 11.5h10a3 3 0 0 0 0-6 4.3 4.3 0 0 0-8 .9A2.6 2.6 0 0 0 4 11.5zM8 18.5h10a3 3 0 0 0 0-6' fill='#b9b1b8' %s/>",
	"keyboard": "<rect x='2.6' y='6' width='18.8' height='12' rx='2.4' fill='#fffaf0' %s/><path d='M6 9.6h.1M9.4 9.6h.1M12.8 9.6h.1M16.2 9.6h.1M6 12.4h.1M9.4 12.4h.1M12.8 12.4h.1M16.2 12.4h.1M8 15.2h8' stroke='#291a33' stroke-width='1.9' stroke-linecap='round'/>",
	"check_off": "<rect x='3.5' y='3.5' width='17' height='17' rx='4.5' fill='#fffaf0' stroke='#6f6170' stroke-width='1.6'/>",
	"check_on": "<rect x='3.5' y='3.5' width='17' height='17' rx='4.5' fill='#3d2b4a' stroke='#291a33' stroke-width='1.6'/><path d='M7.6 12.3l3 3 5.8-6.4' fill='none' stroke='#fff6e6' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'/>",
	"switch_off": "<rect x='1' y='5.5' width='38' height='21' rx='10.5' fill='#e3d3b6' stroke='#6f6170' stroke-width='1.6'/><circle cx='11.5' cy='16' r='7.2' fill='#fffaf0' stroke='#6f6170' stroke-width='1.6'/>",
	"switch_on": "<rect x='1' y='5.5' width='38' height='21' rx='10.5' fill='#3d2b4a' stroke='#291a33' stroke-width='1.6'/><circle cx='28.5' cy='16' r='7.2' fill='#f2c14e' stroke='#291a33' stroke-width='1.6'/>",
}
## Shapes on a wider grid than 24x24 (width, height).
const WIDE := {"switch_off": Vector2(40, 32), "switch_on": Vector2(40, 32)}

static var _cache: Dictionary = {}


## The icon as a texture that reports itself as size x size pixels (wide shapes keep their ratio).
static func texture(icon_name: String, size: int = 18) -> Texture2D:
	var key := "%s|%d" % [icon_name, size]
	if _cache.has(key):
		return _cache[key]
	var grid: Vector2 = WIDE.get(icon_name, Vector2(24, 24))
	var image := Image.new()
	var error := image.load_svg_from_string(svg(icon_name), size * OVERSAMPLE / grid.y)
	if error != OK or image.is_empty():
		image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.generate_mipmaps()
	var result := ImageTexture.create_from_image(image)
	result.set_size_override(Vector2i(roundi(size * grid.x / grid.y), size))
	_cache[key] = result
	return result


## The full SVG document for an icon.
static func svg(icon_name: String) -> String:
	var body := String(SHAPES.get(icon_name, SHAPES["help"]))
	var grid: Vector2 = WIDE.get(icon_name, Vector2(24, 24))
	var slots := body.count("%s")
	var fill: Array = []
	for i: int in slots:
		fill.append(LINE)
	return "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='0 0 %d %d'>%s</svg>" % [
		int(grid.x), int(grid.y), int(grid.x), int(grid.y), body % fill if slots > 0 else body]


static func has(icon_name: String) -> bool:
	return SHAPES.has(icon_name)
