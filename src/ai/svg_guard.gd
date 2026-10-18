class_name SvgGuard
extends RefCounted
## Cleans an SVG an AI wrote (a banner's emblem, a poster's motif) down to a small, safe subset
## before the game rasterizes it. The input is parsed with XMLParser and a new SVG is written from
## what survives, so nothing of the input passes through as text:
## - elements: svg (the root), g, rect, circle, ellipse, polygon, polyline, path, line. Anything
##   else (text, style, script, image, use, a, foreignObject, defs, filters...) is dropped with
##   everything inside it;
## - attributes: each element's geometry, plus fill, stroke, stroke-width, the opacities, line caps
##   and joins, fill-rule and a transform of translate, rotate and scale only. No style, class,
##   id, href, event handlers or CSS;
## - colors: palette tokens only ("p17" is ArtPalette index 17, clamped onto a group) or "none";
##   a #hex color is snapped to the nearest swatch, anything else is dropped;
## - size: the input's length, the number of elements, points, path commands and numbers are
##   bounded, and every number is clamped into the 64 by 64 viewBox;
## - a DOCTYPE or ENTITY anywhere rejects the whole input.
## The clean SVG keeps the palette tokens (so cleaning it again changes nothing); renderable()
## turns them into colors for Image.load_svg_from_string. "" means nothing usable was left.

const VIEW := 64.0
const MAX_CHARS := 6000
const MAX_ELEMENTS := 32 ## groups and shapes
const MAX_DEPTH := 4 ## groups inside groups
const MAX_POINTS := 40 ## per polygon or polyline
const MAX_PATH_COMMANDS := 48 ## per path
const MAX_NUMBERS := 900 ## in the whole SVG
const MAX_TRANSFORMS := 4 ## steps in one transform
const MAX_STROKE := 6.0
const HEAD := '<svg viewBox="0 0 64 64" width="64" height="64">'
const TAIL := "</svg>"
const INK_HEX := "#291a33" ## what an unpainted shape is filled with when drawn

## element -> its geometry attributes and what kind of number each takes.
const GEOMETRY := {
	"g": {},
	"rect": {"x": "coord", "y": "coord", "width": "length", "height": "length", "rx": "length", "ry": "length"},
	"circle": {"cx": "coord", "cy": "coord", "r": "length"},
	"ellipse": {"cx": "coord", "cy": "coord", "rx": "length", "ry": "length"},
	"line": {"x1": "coord", "y1": "coord", "x2": "coord", "y2": "coord"},
	"polygon": {"points": "points"},
	"polyline": {"points": "points"},
	"path": {"d": "path"},
}
## Presentation attributes every element may have, in the order they are written.
const PAINT: Array[String] = ["fill", "stroke"]
const AMOUNTS := {"stroke-width": [0.0, MAX_STROKE], "opacity": [0.0, 1.0], "fill-opacity": [0.0, 1.0], "stroke-opacity": [0.0, 1.0]}
const KEYWORDS := {
	"stroke-linecap": ["butt", "round", "square"],
	"stroke-linejoin": ["miter", "round", "bevel"],
	"fill-rule": ["nonzero", "evenodd"],
}
## Path command -> how many numbers each repeat takes.
const PATH_ARGS := {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7, "Z": 0}

static var _number: RegEx
static var _token: RegEx
static var _step: RegEx
static var _token_color: RegEx


## The clean SVG, or "" if nothing usable is left. group limits the colors to an ArtPalette group.
static func sanitize(svg: String, group: String = "") -> String:
	if svg.length() > MAX_CHARS or svg.strip_edges().is_empty():
		return ""
	var lower := svg.to_lower()
	if lower.contains("<!doctype") or lower.contains("<!entity"):
		return ""
	var parser := XMLParser.new()
	if parser.open_buffer(svg.to_utf8_buffer()) != OK:
		return ""
	var budget := {"elements": 0, "numbers": 0}
	var root := {}
	var stack: Array[Dictionary] = [] # open elements we keep
	var skipping := 0 # how deep inside a dropped element we are
	while parser.read() == OK:
		var type := parser.get_node_type()
		if type == XMLParser.NODE_ELEMENT:
			var tag := parser.get_node_name()
			var empty := parser.is_empty()
			if skipping > 0:
				skipping += 0 if empty else 1
				continue
			if root.is_empty():
				if tag != "svg":
					return ""
				root = {"tag": "g", "attrs": _presentation(_attributes(parser), group, budget), "children": []}
				if empty:
					break
				stack.append(root)
				continue
			if stack.is_empty():
				break # a second root: ignore the rest
			var node := {}
			if GEOMETRY.has(tag) and stack.size() <= MAX_DEPTH and int(budget["elements"]) < MAX_ELEMENTS:
				node = _element(tag, _attributes(parser), group, budget)
			if node.is_empty():
				skipping = 0 if empty else 1
				continue
			budget["elements"] = int(budget["elements"]) + 1
			(stack.back()["children"] as Array).append(node)
			if not empty:
				if tag == "g":
					stack.append(node)
				else:
					skipping = 1 # a shape's children (titles, animations) are dropped
		elif type == XMLParser.NODE_ELEMENT_END:
			if skipping > 0:
				skipping -= 1
			elif not stack.is_empty():
				stack.pop_back()
				if stack.is_empty():
					break
	if root.is_empty() or not _prune(root):
		return ""
	if not (root["attrs"] as PackedStringArray).is_empty():
		return HEAD + _write(root) + TAIL
	# The root's own colors become a group around everything; with none, there is no group.
	var body := PackedStringArray()
	for child: Dictionary in root["children"]:
		body.append(_write(child))
	return HEAD + "".join(body) + TAIL


## What's inside the clean SVG's root, to compose it into a larger picture.
static func inner(clean: String) -> String:
	if not clean.begins_with(HEAD) or not clean.ends_with(TAIL):
		return ""
	return clean.substr(HEAD.length(), clean.length() - HEAD.length() - TAIL.length())


## A clean SVG (or a picture composed of clean parts) with its palette tokens turned into
## colors, ready for Image.load_svg_from_string. Unpainted shapes are filled with ink.
static func renderable(clean: String) -> String:
	if _token_color == null:
		_token_color = RegEx.create_from_string('(fill|stroke)="p(\\d{1,3})"')
	var parts := PackedStringArray()
	var from := 0
	for found: RegExMatch in _token_color.search_all(clean):
		parts.append(clean.substr(from, found.get_start() - from))
		parts.append('%s="#%s"' % [found.get_string(1), ArtPalette.color(found.get_string(2).to_int()).to_html(false)])
		from = found.get_end()
	parts.append(clean.substr(from))
	var text := "".join(parts)
	return text.replace(HEAD, HEAD.trim_suffix(">") + ' fill="%s">' % INK_HEX)


## Number of drawn shapes (not groups) in a clean SVG.
static func shape_count(clean: String) -> int:
	var count := 0
	for tag: String in GEOMETRY:
		if tag != "g":
			count += clean.count("<%s " % tag)
	return count


# --- Elements -----------------------------------------------------------------------

static func _attributes(parser: XMLParser) -> Dictionary:
	var found := {}
	for i: int in parser.get_attribute_count():
		var key := parser.get_attribute_name(i)
		if not found.has(key):
			found[key] = parser.get_attribute_value(i)
	return found


## A kept element: {"tag", "attrs": PackedStringArray of written attributes, "children"}, or {}
## if its geometry is missing, broken or draws nothing.
static func _element(tag: String, attrs: Dictionary, group: String, budget: Dictionary) -> Dictionary:
	var written := PackedStringArray()
	var geometry: Dictionary = GEOMETRY[tag]
	var values := {}
	for key: String in geometry:
		if not attrs.has(key):
			continue
		var kind := String(geometry[key])
		var value := ""
		match kind:
			"coord", "length":
				var number: Variant = _parse_number(String(attrs[key]))
				if number == null:
					continue
				values[key] = clampf(number, 0.0, VIEW)
				value = _num(values[key])
				budget["numbers"] = int(budget["numbers"]) + 1
			"points":
				value = _points(String(attrs[key]), tag == "polygon", budget)
			"path":
				value = _path(String(attrs[key]), budget)
		if value.is_empty():
			continue
		written.append('%s="%s"' % [key, value])
	if int(budget["numbers"]) > MAX_NUMBERS:
		return {}
	match tag:
		"rect":
			if float(values.get("width", 0.0)) <= 0.0 or float(values.get("height", 0.0)) <= 0.0:
				return {}
		"circle":
			if float(values.get("r", 0.0)) <= 0.0:
				return {}
		"ellipse":
			if float(values.get("rx", 0.0)) <= 0.0 or float(values.get("ry", 0.0)) <= 0.0:
				return {}
		"polygon", "polyline", "path":
			if written.is_empty():
				return {}
	written.append_array(_presentation(attrs, group, budget))
	return {"tag": tag, "attrs": written, "children": []}


## The presentation attributes any element may carry, cleaned.
static func _presentation(attrs: Dictionary, group: String, budget: Dictionary) -> PackedStringArray:
	var written := PackedStringArray()
	for key: String in PAINT:
		if attrs.has(key):
			var paint := _paint(String(attrs[key]), group)
			if paint:
				written.append('%s="%s"' % [key, paint])
	for key: String in AMOUNTS:
		if attrs.has(key):
			var number: Variant = _parse_number(String(attrs[key]))
			if number != null:
				var limits: Array = AMOUNTS[key]
				written.append('%s="%s"' % [key, _num(clampf(number, limits[0], limits[1]))])
	for key: String in KEYWORDS:
		if attrs.has(key) and String(attrs[key]).strip_edges() in KEYWORDS[key]:
			written.append('%s="%s"' % [key, String(attrs[key]).strip_edges()])
	if attrs.has("transform"):
		var transform := _transform(String(attrs["transform"]), budget)
		if transform:
			written.append('transform="%s"' % transform)
	return written


## A palette token for a paint, "none", or "" to drop it.
static func _paint(value: String, group: String) -> String:
	value = value.strip_edges()
	if value == "none":
		return "none"
	if value.length() >= 2 and value.length() <= 4 and value[0] == "p" and value.substr(1).is_valid_int():
		return "p%d" % ArtPalette.clamp_index(value.substr(1).to_int(), group)
	if value.begins_with("#") and (value.length() == 4 or value.length() == 7) and value.substr(1).is_valid_hex_number():
		return "p%d" % _nearest(Color.html(value), group)
	return ""


static func _nearest(color: Color, group: String) -> int:
	var indices: Array = ArtPalette.GROUPS[group] if group else range(ArtPalette.size())
	var best: int = indices[0]
	var best_distance := INF
	for index: int in indices:
		var swatch := ArtPalette.color(index)
		var distance := Vector3(swatch.r - color.r, swatch.g - color.g, swatch.b - color.b).length_squared()
		if distance < best_distance:
			best = index
			best_distance = distance
	return best


## Drops groups with nothing drawn in them. False if nothing is drawn at all.
static func _prune(node: Dictionary) -> bool:
	if node["tag"] != "g":
		return true
	var kept: Array = []
	for child: Dictionary in node["children"]:
		if _prune(child):
			kept.append(child)
	node["children"] = kept
	return not kept.is_empty()


static func _write(node: Dictionary) -> String:
	var attrs: PackedStringArray = node["attrs"]
	var open := "<%s%s" % [node["tag"], (" " + " ".join(attrs)) if not attrs.is_empty() else ""]
	var children: Array = node["children"]
	if node["tag"] != "g":
		return open + "/>"
	var body := PackedStringArray()
	for child: Dictionary in children:
		body.append(_write(child))
	return open + ">" + "".join(body) + "</g>"


# --- Numbers ------------------------------------------------------------------------

## A plain number (an optional "px" allowed), or null.
static func _parse_number(text: String) -> Variant:
	text = text.strip_edges().trim_suffix("px")
	if text.is_empty() or text.length() > 24:
		return null
	var numbers := _numbers(text)
	return numbers[0] if numbers.size() == 1 else null


## Every number in a list ("1,2 3.5-4"), or [] if anything else is in it.
static func _numbers(text: String) -> Array[float]:
	var found: Array[float] = []
	if _number == null:
		_number = RegEx.create_from_string("[-+]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?")
	var from := 0
	for match_found: RegExMatch in _number.search_all(text):
		var value := match_found.get_string().to_float()
		if is_nan(value) or is_inf(value) or not _only_separators(text.substr(from, match_found.get_start() - from)):
			return []
		found.append(value)
		from = match_found.get_end()
	if not _only_separators(text.substr(from)):
		return []
	return found


static func _only_separators(text: String) -> bool:
	for c: String in text:
		if c not in [" ", ",", "\t", "\n", "\r"]:
			return false
	return true


## A number as short as it can be written: "12", "-3.5", "0.25".
static func _num(value: float) -> String:
	value = snappedf(value, 0.01)
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return String.num(value, 2)


static func _points(text: String, closed: bool, budget: Dictionary) -> String:
	var numbers := _numbers(text)
	var pairs := mini(numbers.size() / 2, MAX_POINTS)
	if pairs < (3 if closed else 2):
		return ""
	budget["numbers"] = int(budget["numbers"]) + pairs * 2
	var written := PackedStringArray()
	for k: int in pairs:
		written.append("%s,%s" % [_num(clampf(numbers[2 * k], 0.0, VIEW)), _num(clampf(numbers[2 * k + 1], 0.0, VIEW))])
	return " ".join(written)


## A path's commands rewritten as absolute ones, every point clamped into the viewBox. Stops at
## the first thing it can't read (keeping what came before); "" if no shape is left.
static func _path(text: String, budget: Dictionary) -> String:
	if _token == null:
		_token = RegEx.create_from_string("[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?|[^\\s,]")
	var tokens := PackedStringArray()
	for found: RegExMatch in _token.search_all(text):
		tokens.append(found.get_string())
		if tokens.size() > MAX_PATH_COMMANDS * 8:
			break
	var written := PackedStringArray()
	var at := Vector2.ZERO
	var start := Vector2.ZERO
	var command := ""
	var commands := 0
	var drawn := 0
	var i := 0
	while i < tokens.size() and commands < MAX_PATH_COMMANDS:
		var token := tokens[i]
		if PATH_ARGS.has(token.to_upper()):
			command = token
			i += 1
			if written.is_empty() and command.to_upper() != "M":
				return "" # a path starts with a move
			if command.to_upper() == "Z":
				written.append("Z")
				at = start
				commands += 1
				continue
		elif command.is_empty() or command.to_upper() == "Z":
			break # numbers with no command to take them
		var count: int = PATH_ARGS[command.to_upper()]
		if i + count > tokens.size():
			break
		var args: Array[float] = []
		for k: int in count:
			var value: Variant = _parse_number(tokens[i + k])
			if value == null:
				args.clear()
				break
			args.append(value)
		if args.size() != count:
			break
		i += count
		var relative := command == command.to_lower()
		var upper := command.to_upper()
		var base := at if relative else Vector2.ZERO
		var out := PackedStringArray([upper])
		match upper:
			"M", "L", "T":
				at = base + Vector2(args[0], args[1])
				out.append(_pair(at))
				if upper == "M":
					start = at
					command = "l" if relative else "L" # more pairs after a move are lines
			"H":
				at.x = base.x + args[0]
				out.append(_num(clampf(at.x, 0.0, VIEW)))
			"V":
				at.y = base.y + args[0]
				out.append(_num(clampf(at.y, 0.0, VIEW)))
			"C", "S", "Q":
				for k: int in range(0, count, 2):
					out.append(_pair(base + Vector2(args[k], args[k + 1])))
				at = base + Vector2(args[count - 2], args[count - 1])
			"A":
				if not (args[3] in [0.0, 1.0] and args[4] in [0.0, 1.0]):
					break
				out.append_array([_num(clampf(args[0], 0.0, VIEW)), _num(clampf(args[1], 0.0, VIEW)), _num(clampf(args[2], -360.0, 360.0)),
					str(int(args[3])), str(int(args[4]))])
				at = base + Vector2(args[5], args[6])
				out.append(_pair(at))
		written.append(" ".join(out))
		budget["numbers"] = int(budget["numbers"]) + count
		commands += 1
		drawn += 0 if upper == "M" else 1
	return " ".join(written) if drawn > 0 else ""


static func _pair(point: Vector2) -> String:
	return "%s %s" % [_num(clampf(point.x, 0.0, VIEW)), _num(clampf(point.y, 0.0, VIEW))]


## translate(x [y]), rotate(a [cx cy]) and scale(s [sy]) steps, clamped; "" if anything else.
static func _transform(text: String, budget: Dictionary) -> String:
	if _step == null:
		_step = RegEx.create_from_string("(translate|rotate|scale)\\s*\\(([^()]*)\\)")
	var steps := PackedStringArray()
	var from := 0
	for found: RegExMatch in _step.search_all(text):
		if not _only_separators(text.substr(from, found.get_start() - from)):
			return ""
		from = found.get_end()
		var numbers := _numbers(found.get_string(2))
		var kind := found.get_string(1)
		var step := ""
		match kind:
			"translate":
				if numbers.size() in [1, 2]:
					step = "translate(%s %s)" % [_num(clampf(numbers[0], -VIEW, VIEW)), _num(clampf(numbers[1] if numbers.size() == 2 else 0.0, -VIEW, VIEW))]
			"rotate":
				if numbers.size() == 1:
					step = "rotate(%s)" % _num(clampf(numbers[0], -360.0, 360.0))
				elif numbers.size() == 3:
					step = "rotate(%s %s %s)" % [_num(clampf(numbers[0], -360.0, 360.0)), _num(clampf(numbers[1], 0.0, VIEW)), _num(clampf(numbers[2], 0.0, VIEW))]
			"scale":
				if numbers.size() in [1, 2]:
					var sx := _scale(numbers[0])
					step = "scale(%s %s)" % [_num(sx), _num(_scale(numbers[1]) if numbers.size() == 2 else sx)]
		if step.is_empty():
			return ""
		steps.append(step)
		budget["numbers"] = int(budget["numbers"]) + numbers.size()
	if not _only_separators(text.substr(from)) or steps.is_empty() or steps.size() > MAX_TRANSFORMS:
		return ""
	return " ".join(steps)


## A scale factor between 0.05 and 4 either way (a mirror is fine; a vanishing or huge one isn't).
static func _scale(value: float) -> float:
	return signf(value if value != 0.0 else 1.0) * clampf(absf(value), 0.05, 4.0)
