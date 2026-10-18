class_name EmblemGrammar
extends RefCounted
## Draws emblems without AI, for the offline banners, posters and temple icons: a charge (a sun, a
## tree, an eye...) in palette tokens, bold and simple like a woodcut, varied by a seed (how many
## rays or points, an oak or a pine, a gear or a spoked wheel), optionally over an ordinary (a
## border, a chief, a pale, a bend...) in a second color. The SVG it writes goes through SvgGuard
## like an AI's, so both paths end in the same clean subset.

const CHARGES: Array[String] = ["sun", "moon", "star", "tree", "wave", "eye", "crown", "flame", "hand", "mountain", "wheel", "tower", "fish", "grain"]
const ORDINARIES: Array[String] = ["none", "border", "chief", "pale", "per_pale", "bend", "chevron", "base"]
## Ordinaries that take room from the charge, which is drawn smaller beside them.
const CROWDING := {"chief": "translate(9 15) scale(0.72)", "base": "translate(9 3) scale(0.72)", "border": "translate(6 6) scale(0.81)"}


## An emblem as SVG: the charge in color, details in accent, over an ordinary in accent.
static func emblem(charge: String, color: int, accent: int, seed_value: int, ordinary: String = "none") -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var body := _charge(charge if charge in CHARGES else "star", "p%d" % color, "p%d" % accent, rng)
	if CROWDING.has(ordinary):
		body = '<g transform="%s">%s</g>' % [CROWDING[ordinary], body]
	return '<svg viewBox="0 0 64 64">%s%s</svg>' % [_ordinary(ordinary, "p%d" % accent), body]


## How light a swatch reads, 0 to 1.
static func lightness(index: int) -> float:
	var c := ArtPalette.color(index)
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## A swatch of the group that stands out on this one: one of the three that differ most in lightness.
static func contrasting(index: int, group: String, rng: RandomNumberGenerator, avoid: Array[int] = []) -> int:
	var candidates: Array = (ArtPalette.GROUPS[group] as Array).filter(func(i: int) -> bool: return i != index and i not in avoid)
	candidates.sort_custom(func(a: int, b: int) -> bool:
		var da := absf(lightness(a) - lightness(index))
		var db := absf(lightness(b) - lightness(index))
		return da > db if not is_equal_approx(da, db) else a < b)
	return candidates[rng.randi_range(0, mini(2, candidates.size() - 1))]


## A weighted pick: weights maps choices to how likely each is.
static func pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for choice: String in weights:
		total += maxf(float(weights[choice]), 0.0)
	var roll := rng.randf() * total
	var keys := weights.keys()
	keys.sort()
	for choice: String in keys:
		roll -= maxf(float(weights[choice]), 0.0)
		if roll <= 0.0:
			return choice
	return String(keys[-1])


# --- Ordinaries ---------------------------------------------------------------------

static func _ordinary(kind: String, accent: String) -> String:
	match kind:
		"border":
			return '<rect x="3" y="3" width="58" height="58" fill="none" stroke="%s" stroke-width="5"/>' % accent
		"chief":
			return '<rect x="0" y="0" width="64" height="13" fill="%s"/>' % accent
		"base":
			return '<rect x="0" y="51" width="64" height="13" fill="%s"/>' % accent
		"pale":
			return '<rect x="22" y="0" width="20" height="64" fill="%s"/>' % accent
		"per_pale":
			return '<rect x="32" y="0" width="32" height="64" fill="%s"/>' % accent
		"bend":
			return '<polygon points="0,9 9,0 64,55 55,64" fill="%s"/>' % accent
		"chevron":
			return '<polygon points="0,56 32,30 64,56 64,64 58,64 32,42 6,64 0,64" fill="%s"/>' % accent
	return ""


# --- Charges ------------------------------------------------------------------------

static func _charge(charge: String, c: String, a: String, rng: RandomNumberGenerator) -> String:
	match charge:
		"sun":
			var rays: int = [8, 10, 12, 16][rng.randi_range(0, 3)]
			var core := '<circle cx="32" cy="32" r="12" fill="%s"/>' % c
			if rng.randf() < 0.5:
				core += '<circle cx="32" cy="32" r="6" fill="%s"/>' % a
			return '<polygon points="%s" fill="%s"/>%s' % [_star_points(rays, 27.0, 14.0, rng.randf() * 0.3), c, core]
		"moon":
			var moon := '<path d="M 40 11.5 A 22 22 0 1 0 40 52.5 A 24 24 0 0 1 40 11.5 Z" fill="%s"/>' % c
			for k: int in rng.randi_range(0, 3):
				moon += '<polygon points="%s" fill="%s" transform="translate(%d %d) scale(0.18)"/>' % [_star_points(5, 24.0, 10.0, 0.0), c, 40 + k * 7, 26 + (k % 2) * 10]
			return moon
		"star":
			var points: int = [5, 6, 7, 8][rng.randi_range(0, 3)]
			var star := '<polygon points="%s" fill="%s"/>' % [_star_points(points, 27.0, 11.0 if points == 5 else 13.0, 0.0), c]
			if rng.randf() < 0.4:
				star += '<circle cx="32" cy="32" r="5" fill="%s"/>' % a
			return star
		"tree":
			if rng.randf() < 0.5:
				return ('<polygon points="22,59 29,46 29,34 35,34 35,46 42,59" fill="%s"/><circle cx="32" cy="17" r="11" fill="%s"/>' \
					+ '<circle cx="19" cy="25" r="10" fill="%s"/><circle cx="45" cy="25" r="10" fill="%s"/>' \
					+ '<circle cx="24" cy="36" r="8" fill="%s"/><circle cx="40" cy="36" r="8" fill="%s"/>') % [c, c, c, c, c, c]
			return ('<rect x="29" y="46" width="6" height="12" fill="%s"/><polygon points="32,5 48,24 16,24" fill="%s"/>' \
				+ '<polygon points="32,14 53,36 11,36" fill="%s"/><polygon points="32,24 57,48 7,48" fill="%s"/>') % [c, c, c, c]
		"wave":
			var rows: Array = [22, 34, 46] if rng.randf() < 0.6 else [27, 41]
			var waves := ""
			for y: int in rows:
				waves += '<path d="M 5 %d Q 13 %d 21 %d T 37 %d T 53 %d T 61 %d" fill="none" stroke="%s" stroke-width="5" stroke-linecap="round"/>' % [y, y - 8, y, y, y, y - 4, c]
			return waves
		"eye":
			var eye := ('<path d="M 5 32 Q 32 7 59 32 Q 32 57 5 32 Z" fill="%s"/><circle cx="32" cy="32" r="11" fill="%s"/>' \
				+ '<circle cx="32" cy="32" r="5" fill="%s"/>') % [c, a, c]
			if rng.randf() < 0.5:
				for k: int in 5:
					eye += '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="3" stroke-linecap="round"/>' % [16 + k * 8, 14 - absi(k - 2), 14 + k * 9, 7 - absi(k - 2) * 2, c]
			return eye
		"crown":
			var crown := ('<polygon points="10,46 10,19 21,32 32,13 43,32 54,19 54,46" fill="%s"/><rect x="9" y="45" width="46" height="9" fill="%s"/>' \
				+ '<circle cx="10" cy="19" r="4" fill="%s"/><circle cx="32" cy="13" r="4" fill="%s"/><circle cx="54" cy="19" r="4" fill="%s"/>') % [c, c, c, c, c]
			return crown + '<circle cx="32" cy="49.5" r="3" fill="%s"/><circle cx="20" cy="49.5" r="2" fill="%s"/><circle cx="44" cy="49.5" r="2" fill="%s"/>' % [a, a, a]
		"flame":
			var flame := '<path d="M 32 5 C 45 19 51 30 47 44 C 44 53 38 58 32 58 C 26 58 20 53 17 44 C 13 31 21 21 25 12 C 28 20 30 22 32 24 C 34 17 35 11 32 5 Z" fill="%s"/>' % c
			return flame + '<path d="M 32 28 C 38 35 40 41 38 46 C 36 51 34 52 32 52 C 30 52 28 51 26 46 C 24 40 27 35 32 28 Z" fill="%s"/>' % a
		"hand":
			return ('<rect x="20" y="29" width="25" height="24" rx="6" fill="%s"/><rect x="20" y="12" width="5.5" height="24" rx="2.75" fill="%s"/>' \
				+ '<rect x="26.5" y="8" width="5.5" height="26" rx="2.75" fill="%s"/><rect x="33" y="10" width="5.5" height="24" rx="2.75" fill="%s"/>' \
				+ '<rect x="39.5" y="15" width="5.5" height="20" rx="2.75" fill="%s"/><rect x="8" y="31" width="15" height="6" rx="3" fill="%s" transform="rotate(-35 21 34)"/>' \
				+ '<rect x="24" y="50" width="17" height="10" fill="%s"/>') % [c, c, c, c, c, c, c]
		"mountain":
			var mountain := '<polygon points="38,12 60,54 16,54" fill="%s"/><polygon points="21,24 40,54 3,54" fill="%s"/>' % [c, c]
			return mountain + '<polygon points="38,12 43.5,22.5 39,20 35,24 32,23" fill="%s"/>' % a
		"wheel":
			if rng.randf() < 0.5:
				var teeth: int = [8, 9, 10][rng.randi_range(0, 2)] # four points a tooth, within SvgGuard.MAX_POINTS
				return '<polygon points="%s" fill="%s"/><circle cx="32" cy="32" r="9" fill="%s"/>' % [_gear_points(teeth), c, a]
			var spokes: int = [6, 8][rng.randi_range(0, 1)]
			var wheel := '<circle cx="32" cy="32" r="23" fill="none" stroke="%s" stroke-width="6"/><circle cx="32" cy="32" r="6" fill="%s"/>' % [c, c]
			for k: int in spokes:
				var angle := TAU * k / spokes
				wheel += '<line x1="32" y1="32" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="3.5"/>' % [32.0 + cos(angle) * 22.0, 32.0 + sin(angle) * 22.0, c]
			return wheel
		"tower":
			var tower := ('<rect x="16" y="17" width="32" height="7" fill="%s"/><rect x="16" y="9" width="7" height="9" fill="%s"/>' \
				+ '<rect x="28.5" y="9" width="7" height="9" fill="%s"/><rect x="41" y="9" width="7" height="9" fill="%s"/>' \
				+ '<rect x="20" y="23" width="24" height="35" fill="%s"/>') % [c, c, c, c, c]
			return tower + '<rect x="27" y="43" width="10" height="15" rx="5" fill="%s"/><rect x="30" y="29" width="4" height="8" fill="%s"/>' % [a, a]
		"fish":
			return ('<ellipse cx="29" cy="33" rx="19" ry="11" fill="%s"/><polygon points="44,33 59,20 59,46" fill="%s"/>' \
				+ '<polygon points="25,24 35,14 38,25" fill="%s"/><circle cx="19" cy="30" r="2.5" fill="%s"/>') % [c, c, c, a]
		"grain":
			var grain := '<line x1="32" y1="60" x2="32" y2="14" stroke="%s" stroke-width="3" stroke-linecap="round"/><ellipse cx="32" cy="11" rx="3.5" ry="6.5" fill="%s"/>' % [c, c]
			for k: int in 4:
				var y := 20 + k * 8
				grain += '<ellipse cx="26" cy="%d" rx="3.5" ry="6.5" fill="%s" transform="rotate(-35 26 %d)"/>' % [y, c, y]
				grain += '<ellipse cx="38" cy="%d" rx="3.5" ry="6.5" fill="%s" transform="rotate(35 38 %d)"/>' % [y, c, y]
			return grain
	return ""


## Points of a star (or a sun's rays) around the middle: n points, outer and inner radius.
static func _star_points(n: int, outer: float, inner: float, turn: float) -> String:
	var points := PackedStringArray()
	for k: int in n * 2:
		var angle := -PI / 2.0 + turn + PI * k / n
		var radius := outer if k % 2 == 0 else inner
		points.append("%.1f,%.1f" % [32.0 + cos(angle) * radius, 32.0 + sin(angle) * radius])
	return " ".join(points)


## A cog: teeth flat-topped around a ring.
static func _gear_points(teeth: int) -> String:
	var points := PackedStringArray()
	var step := TAU / teeth
	for k: int in teeth:
		var base := step * k
		for part: Array in [[0.0, 19.0], [0.18, 26.0], [0.5, 26.0], [0.68, 19.0]]:
			var angle := base + step * float(part[0])
			points.append("%.1f,%.1f" % [32.0 + cos(angle) * float(part[1]), 32.0 + sin(angle) * float(part[1])])
	return " ".join(points)
