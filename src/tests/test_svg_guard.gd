extends TestCase
## SvgGuard: an AI-written SVG is re-written from scratch as a small, safe subset in palette
## colors, or dropped. Hostile and broken inputs must never reach the rasterizer.


func _clean(svg: String, group: String = "") -> String:
	return SvgGuard.sanitize(svg, group)


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02


func test_keeps_the_whitelisted_shapes_and_rewrites_them() -> void:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">' \
		+ '<rect x="4" y="4" width="56" height="56" rx="6" fill="p22"/>' \
		+ "<circle cx='32' cy='32' r='12' fill='p17' stroke='p31' stroke-width='2'/>" \
		+ '<ellipse cx="32" cy="50" rx="10" ry="4" fill="none" stroke="p31"/>' \
		+ '<polygon points="32,8 40,24 24,24" fill="p30"/>' \
		+ '<polyline points="8 60, 20 52, 32 60" fill="none" stroke="p6"/>' \
		+ '<line x1="0" y1="0" x2="64" y2="64" stroke="p31" stroke-linecap="round"/>' \
		+ '<g transform="rotate(45 32 32)" opacity="0.5"><path d="M 10 10 L 20 10 L 15 20 Z" fill="p28"/></g></svg>'
	var clean := _clean(svg)
	assert_true(clean.begins_with(SvgGuard.HEAD) and clean.ends_with(SvgGuard.TAIL), "one fixed root")
	assert_eq(SvgGuard.shape_count(clean), 7, "every shape survives")
	assert_true(clean.contains('<rect x="4" y="4" width="56" height="56" rx="6" fill="p22"/>'), clean)
	assert_true(clean.contains('<g opacity="0.5" transform="rotate(45 32 32)"><path d="M 10 10 L 20 10 L 15 20 Z" fill="p28"/></g>'), clean)
	assert_true(not clean.contains("http"), "the namespace isn't copied: the output is written, not passed through")
	assert_eq(_clean(clean), clean, "cleaning a clean SVG changes nothing")


func test_drops_scripts_text_styles_links_and_foreign_content() -> void:
	var svg := '<svg viewBox="0 0 64 64" onload="alert(1)">' \
		+ '<script>alert("x")</script>' \
		+ '<style>rect { fill: url(http://evil/x.svg) }</style>' \
		+ '<text x="1" y="10">Obey</text>' \
		+ '<foreignObject width="64" height="64"><div xmlns="http://www.w3.org/1999/xhtml"><rect width="9" height="9"/></div></foreignObject>' \
		+ '<image href="file:///etc/passwd" width="64" height="64"/>' \
		+ '<use xlink:href="#a"/><a href="https://example.com"><circle cx="5" cy="5" r="5"/></a>' \
		+ '<defs><circle id="a" cx="1" cy="1" r="1"/></defs>' \
		+ '<rect width="10" height="10" style="fill:red" class="x" id="y" onclick="z()" href="#q" xlink:href="#q" filter="url(#f)" fill="url(#g)" mask="url(#m)"/>' \
		+ '</svg>'
	var clean := _clean(svg)
	assert_eq(clean, SvgGuard.HEAD + '<rect width="10" height="10"/>' + SvgGuard.TAIL, "only the bare rect is left")
	for bad: String in ["script", "alert", "style", "text", "Obey", "foreign", "div", "image", "passwd", "use", "href", "http", "url", "class", "onclick", "onload", "filter", "mask", "defs", "<a"]:
		assert_true(not clean.contains(bad), "no '%s' in %s" % [bad, clean])


func test_rejects_doctypes_and_entities_outright() -> void:
	var laughs := '<?xml version="1.0"?><!DOCTYPE svg [<!ENTITY lol "lol"><!ENTITY lol2 "&lol;&lol;&lol;">]><svg><rect width="&lol2;" height="5"/></svg>'
	assert_eq(_clean(laughs), "", "billion laughs")
	assert_eq(_clean('<!doctype svg SYSTEM "http://x/y.dtd"><svg><rect width="5" height="5"/></svg>'), "", "external DTD")
	assert_eq(_clean('<svg><!ENTITY x "y"><rect width="5" height="5"/></svg>'), "", "an entity anywhere")


func test_colors_are_palette_tokens_only() -> void:
	var clean := _clean('<svg><rect width="5" height="5" fill="p99"/><rect width="5" height="5" fill="#ff0000"/>' \
		+ '<rect width="5" height="5" fill="red" stroke="currentColor"/><rect width="5" height="5" fill="p-3"/>' \
		+ '<rect width="5" height="5" fill="rgb(1,2,3)" stroke="p017"/></svg>')
	assert_true(clean.contains('fill="p31"'), "an index past the palette is clamped onto it: %s" % clean)
	assert_true(clean.contains('fill="p23"'), "a hex color snaps to the nearest swatch (flame): %s" % clean)
	assert_true(not clean.contains("red") and not clean.contains("rgb") and not clean.contains("currentColor") and not clean.contains("p-3"), clean)
	assert_true(clean.contains('stroke="p17"'), "a zero-padded token is still an index")
	var heraldic := _clean('<svg><rect width="5" height="5" fill="p9"/></svg>', "heraldry")
	var brick := ArtPalette.clamp_index(9, "heraldry")
	assert_true(heraldic.contains('fill="p%d"' % brick) and brick in ArtPalette.GROUPS["heraldry"], "a group clamps onto its own swatches: %s" % heraldic)


func test_numbers_are_clamped_into_the_view_box() -> void:
	var clean := _clean('<svg><rect x="-500" y="1e9" width="100000" height="64.5px" stroke-width="80"/>' \
		+ '<circle cx="32" cy="32" r="1e300" opacity="7"/><polygon points="-10,-10 999,5 30 99999"/>' \
		+ '<g transform="translate(900 -900) scale(1000) rotate(9999 500 -2)"><circle cx="1" cy="1" r="1"/></g></svg>')
	assert_true(clean.contains('<rect x="0" y="64" width="64" height="64" stroke-width="6"/>'), clean)
	assert_true(clean.contains('<circle cx="32" cy="32" r="64" opacity="1"/>'), clean)
	assert_true(clean.contains('points="0,0 64,5 30,64"'), clean)
	assert_true(clean.contains('transform="translate(64 -64) scale(4 4) rotate(360 64 0)"'), clean)
	for bad: String in ["nan", "inf", "e9", "e300", "px"]:
		assert_true(not clean.to_lower().contains(bad), "no '%s' in %s" % [bad, clean])
	assert_eq(_clean('<svg><rect width="nan" height="inf"/><circle r="NaN"/></svg>'), "", "not-numbers draw nothing")


func test_paths_become_absolute_and_bounded() -> void:
	var clean := _clean('<svg><path d="m10 10 l 5 0 5 5 h-20 v 100 c 1 1 2 2 3 3 s 1 1 2 2 q 1 1 2 2 t 4 4 a 5 5 0 0 1 10 0 z"/></svg>')
	assert_true(clean.contains('d="M 10 10 L 15 10 L 20 15 H 0 V 64 C 1 64 2 64 3 64 S 4 64 5 64 Q 6 64 7 64 T 11 64 A 5 5 0 0 1 21 64 Z"'), clean)
	assert_true(not clean.contains(" l ") and not clean.contains(" c ") and clean.contains(" Z"), "commands are absolute: %s" % clean)
	assert_eq(_clean('<svg><path d="L 10 10 L 20 20"/></svg>'), "", "a path must start with a move")
	assert_eq(_clean('<svg><path d="M 10 10"/></svg>'), "", "a lone move draws nothing")
	assert_eq(_clean('<svg><path d="M 10 10 L javascript:alert(1)"/></svg>'), "", "garbage in a path ends it (nothing was drawn before)")
	var cut := _clean('<svg><path d="M 1 1 L 2 2 L 3 x 4 4"/></svg>')
	assert_true(cut.contains('d="M 1 1 L 2 2"'), "a path keeps what came before the garbage: %s" % cut)
	var arcs := _clean('<svg><path d="M 1 1 A 5 5 0 2 1 9 9"/></svg>')
	assert_eq(arcs, "", "arc flags must be 0 or 1")
	var long_path := "M 1 1"
	for k: int in 500:
		long_path += " L %d %d" % [k % 64, (k * 7) % 64]
	var bounded := _clean('<svg><path d="%s"/></svg>' % long_path)
	assert_true(bounded.count(" L ") < SvgGuard.MAX_PATH_COMMANDS, "a path is cut at the command limit")


func test_element_count_and_nesting_are_bounded() -> void:
	var many := "<svg>"
	for k: int in 100:
		many += '<circle cx="%d" cy="%d" r="2"/>' % [k % 64, k % 50]
	many += "</svg>"
	assert_eq(SvgGuard.shape_count(_clean(many)), SvgGuard.MAX_ELEMENTS, "no more than the element limit")
	var deep := "<svg>" + "<g>".repeat(12) + '<rect width="5" height="5"/>' + "</g>".repeat(12) + '<circle cx="5" cy="5" r="3"/></svg>'
	var clean := _clean(deep)
	assert_true(not clean.contains("<rect"), "a shape nested too deep is dropped: %s" % clean)
	assert_true(clean.contains("<circle"), "and its siblings after it still count")
	assert_eq(_clean("<svg><g><g></g></g></svg>"), "", "empty groups are not a picture")


func test_malformed_and_hostile_inputs_never_crash() -> void:
	var inputs: Array[String] = [
		"", "   ", "not xml at all", "<", "<svg", "<svg>", "<svg></svg>", "</svg>", "<rect width='5' height='5'/>",
		"<svg><rect x=1 y=2 width=5 height=5/></svg>", '<svg><rect width="5" height="5"', "<svg><<<>>>",
		'<svg><rect width="5" height="5"/></svg><svg><circle r="9"/></svg>', '<svg><rect width="5" height="5" width="99"/></svg>',
		'<svg><![CDATA[<script>alert(1)</script>]]><rect width="5" height="5"/></svg>',
		'<svg><!-- <script>x</script> --><rect width="5" height="5"/></svg>', "<svg>" + "x".repeat(SvgGuard.MAX_CHARS) + "</svg>",
		'<svg><polygon points="1"/><polyline points=""/><path d=""/><circle r="-4"/><rect width="0" height="9"/></svg>',
		'<SVG><RECT width="5" height="5"/></SVG>', '<svg><rect width="5" height="5" fill="p1&#x22; onload=&#x22;x"/></svg>',
		'<svg:svg><svg:rect width="5" height="5"/></svg:svg>',
	]
	for input: String in inputs:
		var clean := _clean(input)
		if clean.is_empty():
			continue
		assert_true(clean.begins_with(SvgGuard.HEAD) and clean.ends_with(SvgGuard.TAIL), "clean or nothing: %s -> %s" % [input, clean])
		for bad: String in ["script", "onload", "CDATA", "<!", "&"]:
			assert_true(not clean.contains(bad), "%s -> %s" % [input, clean])
	assert_eq(_clean('<svg><rect width="5" height="5"/></svg><svg><circle r="9"/></svg>'), SvgGuard.HEAD + '<rect width="5" height="5"/>' + SvgGuard.TAIL, "only the first root counts")
	assert_eq(_clean('<svg><rect width="5" height="5" width="99"/></svg>'), SvgGuard.HEAD + '<rect width="5" height="5"/>' + SvgGuard.TAIL, "a repeated attribute keeps its first value")
	assert_eq(_clean('<SVG><RECT width="5" height="5"/></SVG>'), "", "names are case-sensitive")


func test_renderable_turns_tokens_into_colors_that_rasterize() -> void:
	var clean := _clean('<svg><rect width="64" height="64" fill="p22"/><circle cx="32" cy="32" r="12" fill="p17"/><rect x="0" y="0" width="4" height="4"/></svg>')
	var drawn := SvgGuard.renderable(clean)
	assert_true(drawn.contains("#%s" % ArtPalette.color(22).to_html(false)) and not drawn.contains('"p22"'), drawn)
	var image := Image.new()
	assert_eq(image.load_svg_from_string(drawn, 1.0), OK, "it rasterizes")
	assert_eq(image.get_size(), Vector2i(64, 64))
	assert_true(_near(image.get_pixel(32, 32), ArtPalette.color(17)), "gold in the middle: %s" % image.get_pixel(32, 32))
	assert_true(_near(image.get_pixel(60, 60), ArtPalette.color(22)), "crimson field")
	var corner := image.get_pixel(1, 1)
	assert_true(corner.r < 0.25 and corner.b < 0.3, "an unpainted shape is ink, not raw black or white: %s" % corner)
	assert_eq(SvgGuard.inner(clean), clean.trim_prefix(SvgGuard.HEAD).trim_suffix(SvgGuard.TAIL))
	assert_eq(SvgGuard.inner("<svg><rect/></svg>"), "", "inner() only reads clean SVG")
