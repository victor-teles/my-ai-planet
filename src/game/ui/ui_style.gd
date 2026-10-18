class_name UiStyle
extends RefCounted
## The HUD's look, shared by every panel: the tokens (colors, type scale, spacing, radii, motion),
## the theme (fonts, buttons and their variations, cards, tooltips, scroll bars, switches) and
## small builders (labels, chips, bars, headers, tabs). docs/ART_BIBLE.md, "UI", lists the rules.
##
## Panels pick a look with theme_type_variation: "Card" (a panel), "Plaque" (a small floating
## group, like the top bar's), "Well" (a sunk area); buttons: plain Button (secondary),
## "PrimaryButton", "GhostButton", "ChipButton", "TabButton" (inside a "Segmented" well),
## "NavButton" and "MiracleButton".

# --- Colors ---------------------------------------------------------------------------------
const INK := Color(0.16, 0.10, 0.20) ## the art bible's ink #291a33: text, outlines
const INK_SOFT := Color(0.33, 0.26, 0.38) ## secondary text
const INK_FAINT := Color(0.45, 0.39, 0.48) ## captions, dates, hints (4.5:1 on paper)
const INK_GHOST := Color(0.66, 0.60, 0.64) ## disabled text, hairlines
const PAPER := Color(0.99, 0.95, 0.86) ## card background
const PAPER_DEEP := Color(0.96, 0.88, 0.72) ## buttons, chips, selected rows
const PAPER_SUNK := Color(0.93, 0.86, 0.74) ## wells, tracks, segmented controls
const GOLD := Color(0.95, 0.70, 0.30) ## the god's color: Influence, pressed, active
const GOLD_SOFT := Color(1.0, 0.85, 0.58) ## hover
const ORACLE := Color(0.42, 0.30, 0.62) ## the Oracle's violet: prophecy, AI
const GOOD := Color(0.22, 0.48, 0.26)
const BAD := Color(0.72, 0.24, 0.20)
const WARN := Color(0.80, 0.50, 0.14)
const DARK := Color(0.58, 0.18, 0.30) ## dystopia, dark laws, dark destinies
const SCRIM := Color(0.14, 0.08, 0.20, 0.48) ## dims the world under a modal (violet, never black)
const SHADOW := Color(0.22, 0.10, 0.30, 0.32)
## Kept for the panels written before the tokens.
const PARCHMENT := PAPER
const CHIP := PAPER_DEEP
const FAINT := 0.35 ## how much lighter secondary ink is (INK.lightened(FAINT) ~ INK_FAINT)

# --- Type scale (logical pixels at 1152x648) --------------------------------------------------
const CAPTION := 11
const SMALL := 12
const BODY := 14
const LEAD := 16
const TITLE := 20
const DISPLAY := 26

# --- Spacing, radii, layout ----------------------------------------------------------------
const SPACE_1 := 4
const SPACE_2 := 8
const SPACE_3 := 12
const SPACE_4 := 16
const SPACE_5 := 24
const RADIUS_S := 6
const RADIUS_M := 10
const RADIUS_L := 14
const BORDER := 2 ## the ink line around cards and buttons

# --- Motion --------------------------------------------------------------------------------
const MOTION_FAST := 0.14 ## hover, chips
const MOTION := 0.2 ## panels sliding or fading in
const MOTION_SLOW := 0.45 ## meters filling
const SLIDE := 18.0 ## pixels a dock slides in from

const FONT_DIR := "res://art/ui/fonts/"

static var _theme: Theme
static var _fonts: Dictionary = {}


# --- Fonts ---------------------------------------------------------------------------------

## "body" (Nunito), "strong", "caps" (tracked small capitals), "display" (Fraunces, for titles)
## and "quote" (Fraunces italic, for the Oracle's words).
static func font(kind: String) -> Font:
	if _fonts.is_empty():
		var nunito := _font_file("Nunito.ttf")
		var fraunces := _font_file("Fraunces.ttf")
		var fraunces_italic := _font_file("Fraunces-Italic.ttf")
		_fonts["body"] = _variation(nunito, {"wght": 560})
		_fonts["strong"] = _variation(nunito, {"wght": 780})
		var caps := _variation(nunito, {"wght": 820})
		caps.spacing_glyph = 1
		_fonts["caps"] = caps
		_fonts["display"] = _variation(fraunces, {"wght": 600, "opsz": 40, "SOFT": 100, "WONK": 1})
		_fonts["quote"] = _variation(fraunces_italic, {"wght": 420, "opsz": 18, "SOFT": 100})
	return _fonts.get(kind, _fonts["body"])


static func _font_file(file: String) -> Font:
	var loaded := load(FONT_DIR + file) as Font
	return loaded if loaded else ThemeDB.fallback_font


static func _variation(base: Font, axes: Dictionary) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = base
	var text_server := TextServerManager.get_primary_interface()
	var coordinates := {}
	for axis: String in axes:
		coordinates[text_server.name_to_tag(axis)] = axes[axis]
	variation.variation_opentype = coordinates
	# Symbols the fonts lack (✦ ⚑ ⚔ ...) come from the engine's font, then the system's.
	variation.fallbacks = [ThemeDB.fallback_font]
	return variation


# --- Theme ---------------------------------------------------------------------------------

static func theme() -> Theme:
	if _theme:
		return _theme
	_theme = Theme.new()
	_theme.default_font = font("body")
	_theme.default_font_size = BODY
	_build_buttons()
	_build_panels()
	_build_fields()
	_build_misc()
	return _theme


static func _build_buttons() -> void:
	# Secondary (plain Button): paper with an ink line; gold when hovered and pressed.
	_button_states("Button", {
		"normal": [PAPER_DEEP, INK], "hover": [GOLD_SOFT, INK], "pressed": [GOLD, INK],
		"hover_pressed": [GOLD, INK], "disabled": [PAPER_SUNK, INK_GHOST],
	}, RADIUS_M, Vector4(12, 6, 12, 6), BORDER)
	_button_fonts("Button", INK, INK, INK_GHOST)
	_theme.set_constant("h_separation", "Button", SPACE_2)
	# Primary: filled with ink, for the one action that moves the story on.
	_variation_of("PrimaryButton", "Button")
	_button_states("PrimaryButton", {
		"normal": [Color(0.24, 0.16, 0.30), INK], "hover": [ORACLE, INK], "pressed": [INK, INK],
		"hover_pressed": [INK, INK], "disabled": [INK_GHOST, INK_GHOST],
	}, RADIUS_M, Vector4(20, 8, 20, 8), BORDER)
	_button_fonts("PrimaryButton", PAPER, PAPER, PAPER_SUNK)
	_theme.set_font("font", "PrimaryButton", font("strong"))
	_theme.set_font_size("font_size", "PrimaryButton", LEAD)
	# Ghost: no frame until hovered. Icon buttons, closing, folding.
	_variation_of("GhostButton", "Button")
	_button_states("GhostButton", {
		"normal": [Color(PAPER_SUNK, 0.0), Color(INK, 0.0)], "hover": [PAPER_SUNK, Color(INK, 0.0)],
		"pressed": [PAPER_DEEP, Color(INK, 0.0)], "hover_pressed": [PAPER_DEEP, Color(INK, 0.0)],
		"disabled": [Color(PAPER_SUNK, 0.0), Color(INK, 0.0)],
	}, RADIUS_S + 2, Vector4(6, 4, 6, 4), 0)
	_button_fonts("GhostButton", INK_SOFT, INK, INK_GHOST)
	# Nav: ghost, but a toggled one stays lit (the panel it opens is showing).
	_variation_of("NavButton", "Button")
	_button_states("NavButton", {
		"normal": [Color(PAPER_SUNK, 0.0), Color(INK, 0.0)], "hover": [PAPER_SUNK, Color(INK, 0.0)],
		"pressed": [GOLD_SOFT, INK], "hover_pressed": [GOLD_SOFT, INK],
		"disabled": [Color(PAPER_SUNK, 0.0), Color(INK, 0.0)],
	}, RADIUS_M - 2, Vector4(8, 4, 10, 4), 1)
	_button_fonts("NavButton", INK, INK, INK_GHOST)
	_theme.set_font("font", "NavButton", font("strong"))
	_theme.set_font_size("font_size", "NavButton", SMALL + 1)
	_theme.set_constant("h_separation", "NavButton", 5)
	# Chips: small pills that filter. Off is faded, on is filled.
	_variation_of("ChipButton", "Button")
	_button_states("ChipButton", {
		"normal": [Color(PAPER, 0.0), INK_GHOST], "hover": [GOLD_SOFT, INK],
		"pressed": [PAPER_DEEP, INK], "hover_pressed": [GOLD_SOFT, INK], "disabled": [Color(PAPER, 0.0), INK_GHOST],
	}, 99, Vector4(8, 2, 9, 2), 1)
	_button_fonts("ChipButton", INK_FAINT, INK, INK_GHOST)
	_theme.set_color("font_pressed_color", "ChipButton", INK)
	_theme.set_color("font_hover_pressed_color", "ChipButton", INK)
	_theme.set_font_size("font_size", "ChipButton", SMALL)
	_theme.set_constant("h_separation", "ChipButton", 4)
	# Tabs and segments: flat inside a sunk "Segmented" well; the chosen one is raised paper.
	_variation_of("TabButton", "Button")
	_button_states("TabButton", {
		"normal": [Color(PAPER, 0.0), Color(INK, 0.0)], "hover": [Color(PAPER, 0.55), Color(INK, 0.0)],
		"pressed": [PAPER, INK], "hover_pressed": [PAPER, INK], "disabled": [Color(PAPER, 0.0), Color(INK, 0.0)],
	}, RADIUS_S + 1, Vector4(10, 3, 10, 3), 1)
	_button_fonts("TabButton", INK_SOFT, INK, INK_GHOST)
	_theme.set_color("font_pressed_color", "TabButton", INK)
	_theme.set_color("font_hover_pressed_color", "TabButton", INK)
	_theme.set_font("font", "TabButton", font("strong"))
	_theme.set_font_size("font_size", "TabButton", SMALL + 1)
	# Miracles: a paper tile with an icon over its name.
	_variation_of("MiracleButton", "Button")
	_button_states("MiracleButton", {
		"normal": [PAPER, INK], "hover": [GOLD_SOFT, INK], "pressed": [GOLD, INK],
		"hover_pressed": [GOLD, INK], "disabled": [PAPER_SUNK, INK_GHOST],
	}, RADIUS_M, Vector4(6, 5, 6, 4), BORDER)
	_button_fonts("MiracleButton", INK, INK, INK_GHOST)
	_theme.set_font("font", "MiracleButton", font("strong"))
	_theme.set_font_size("font_size", "MiracleButton", SMALL)
	_theme.set_constant("h_separation", "MiracleButton", 2)
	# Links: inked text, underlined on hover.
	for color_name: String in ["font_color", "font_focus_color"]:
		_theme.set_color(color_name, "LinkButton", Color(0.30, 0.22, 0.48))
	_theme.set_color("font_hover_color", "LinkButton", DARK)
	_theme.set_color("font_pressed_color", "LinkButton", DARK)


static func _build_panels() -> void:
	# Card: every panel and modal.
	_variation_of("Card", "PanelContainer")
	_theme.set_stylebox("panel", "Card", card_box())
	# Plaque: the small floating groups (top bar, prophecy pill).
	_variation_of("Plaque", "PanelContainer")
	_theme.set_stylebox("panel", "Plaque", plaque_box())
	# Well: a sunk area (segmented controls, quotes, filters).
	_variation_of("Well", "PanelContainer")
	_theme.set_stylebox("panel", "Well", well_box())
	_variation_of("Segmented", "PanelContainer")
	var segmented := well_box()
	segmented.set_content_margin_all(3)
	_theme.set_stylebox("panel", "Segmented", segmented)
	# Labels: ink on paper.
	_theme.set_color("font_color", "Label", INK)
	_theme.set_color("font_outline_color", "Label", INK)
	# Tooltips: dark ink with paper text, so they never read as another panel.
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color(0.20, 0.13, 0.26, 0.97)
	tip.border_color = Color(0.36, 0.26, 0.44)
	tip.set_border_width_all(1)
	tip.set_corner_radius_all(RADIUS_S + 1)
	tip.content_margin_left = 10
	tip.content_margin_right = 10
	tip.content_margin_top = 6
	tip.content_margin_bottom = 7
	tip.shadow_color = SHADOW
	tip.shadow_size = 6
	tip.shadow_offset = Vector2(0, 3)
	_theme.set_stylebox("panel", "TooltipPanel", tip)
	_theme.set_color("font_color", "TooltipLabel", Color(1.0, 0.96, 0.88))
	_theme.set_font_size("font_size", "TooltipLabel", SMALL + 1)
	_theme.set_font("font", "TooltipLabel", font("body"))


static func _build_fields() -> void:
	# Text fields and spin boxes: pale paper with an ink line, gold when focused.
	for state: String in ["normal", "focus", "read_only"]:
		var field := StyleBoxFlat.new()
		field.bg_color = Color(1.0, 0.99, 0.95) if state != "read_only" else PAPER_SUNK
		field.border_color = GOLD if state == "focus" else INK_GHOST
		field.set_border_width_all(2 if state == "focus" else 1)
		field.set_corner_radius_all(RADIUS_S)
		field.content_margin_left = 8
		field.content_margin_right = 8
		field.content_margin_top = 4
		field.content_margin_bottom = 4
		_theme.set_stylebox(state, "LineEdit", field)
	_theme.set_color("font_color", "LineEdit", INK)
	_theme.set_color("font_placeholder_color", "LineEdit", INK_GHOST)
	_theme.set_color("caret_color", "LineEdit", INK)
	_theme.set_color("selection_color", "LineEdit", GOLD_SOFT)
	# Drop-down lists: paper, inked; the open list too.
	var menu := card_box()
	menu.set_content_margin_all(6)
	menu.shadow_size = 6
	_theme.set_stylebox("panel", "PopupMenu", menu)
	var hover := StyleBoxFlat.new()
	hover.bg_color = GOLD_SOFT
	hover.set_corner_radius_all(RADIUS_S)
	_theme.set_stylebox("hover", "PopupMenu", hover)
	for color_name: String in ["font_color", "font_hover_color", "font_accelerator_color"]:
		_theme.set_color(color_name, "PopupMenu", INK)
	_theme.set_color("font_disabled_color", "PopupMenu", INK_GHOST)
	_theme.set_icon("arrow", "OptionButton", UiIcons.texture("chevron_down", 14))
	# Check boxes and switches: just the mark and the text.
	for type: String in ["CheckBox", "CheckButton"]:
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color(PAPER_SUNK, 0.0 if state not in ["hover", "hover_pressed"] else 0.7)
			box.set_corner_radius_all(RADIUS_S)
			box.content_margin_left = 4
			box.content_margin_right = 4
			box.content_margin_top = 2
			box.content_margin_bottom = 2
			_theme.set_stylebox(state, type, box if state != "focus" else StyleBoxEmpty.new())
		_button_fonts(type, INK, INK, INK_GHOST)
		_theme.set_constant("h_separation", type, SPACE_2)
	_theme.set_icon("checked", "CheckBox", UiIcons.texture("check_on", 18))
	_theme.set_icon("unchecked", "CheckBox", UiIcons.texture("check_off", 18))
	_theme.set_icon("checked", "CheckButton", UiIcons.texture("switch_on", 18))
	_theme.set_icon("unchecked", "CheckButton", UiIcons.texture("switch_off", 18))
	for type: String in ["CheckBox", "CheckButton", "OptionButton"]:
		_theme.set_constant("icon_max_width", type, 30 if type == "CheckButton" else 18)


static func _build_misc() -> void:
	# Scroll bars: a thin ink grabber on no track.
	for type: String in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(INK, 0.06)
		track.set_corner_radius_all(4)
		track.content_margin_left = 3
		track.content_margin_right = 3
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		_theme.set_stylebox("scroll", type, track)
		_theme.set_stylebox("scroll_focus", type, track)
		for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var grabber := StyleBoxFlat.new()
			var alpha: float = {"grabber": 0.28, "grabber_highlight": 0.45, "grabber_pressed": 0.6}[state]
			grabber.bg_color = Color(INK, alpha)
			grabber.set_corner_radius_all(4)
			_theme.set_stylebox(state, type, grabber)
	_theme.set_constant("scrollbar_h_separation", "ScrollContainer", SPACE_1)
	# Progress bars: a sunk track and a colored fill (UiStyle.bar sets the fill).
	_theme.set_stylebox("background", "ProgressBar", bar_box(PAPER_SUNK))
	_theme.set_stylebox("fill", "ProgressBar", bar_box(GOLD))
	_theme.set_color("font_color", "ProgressBar", INK)
	# Separators: a faint hairline.
	var line := StyleBoxLine.new()
	line.color = Color(INK, 0.16)
	line.thickness = 1
	_theme.set_stylebox("separator", "HSeparator", line)
	_theme.set_constant("separation", "HSeparator", SPACE_2)


static func _variation_of(type: String, base: String) -> void:
	_theme.set_type_variation(type, base)


## states: state -> [fill, border]; padding: left, top, right, bottom.
static func _button_states(type: String, states: Dictionary, radius: int, padding: Vector4, border: int) -> void:
	for state: String in states:
		var colors: Array = states[state]
		var box := StyleBoxFlat.new()
		box.bg_color = colors[0]
		box.border_color = colors[1]
		box.set_border_width_all(border)
		box.set_corner_radius_all(radius)
		box.content_margin_left = padding.x
		box.content_margin_top = padding.y
		box.content_margin_right = padding.z
		box.content_margin_bottom = padding.w
		box.anti_aliasing_size = 0.8
		_theme.set_stylebox(state, type, box)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = GOLD
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(radius + 2)
	focus.set_expand_margin_all(2)
	_theme.set_stylebox("focus", type, focus)


static func _button_fonts(type: String, normal: Color, hover: Color, disabled: Color) -> void:
	for color_name: String in ["font_color", "font_focus_color"]:
		_theme.set_color(color_name, type, normal)
	for color_name: String in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		_theme.set_color(color_name, type, hover)
	_theme.set_color("font_disabled_color", type, disabled)
	_theme.set_color("icon_disabled_color", type, Color(1, 1, 1, 0.4))


# --- Boxes ---------------------------------------------------------------------------------

## A panel: paper, an ink line, round corners and a soft violet shadow.
static func card_box(padding: int = SPACE_4) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PAPER
	box.border_color = INK
	box.set_border_width_all(BORDER)
	box.set_corner_radius_all(RADIUS_L)
	box.set_content_margin_all(padding)
	box.shadow_color = SHADOW
	box.shadow_size = 12
	box.shadow_offset = Vector2(0, 5)
	box.anti_aliasing_size = 0.8
	return box


## A small floating group: like a card, tighter.
static func plaque_box() -> StyleBoxFlat:
	var box := card_box(SPACE_2)
	box.set_corner_radius_all(RADIUS_M + 2)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	box.shadow_size = 8
	box.shadow_offset = Vector2(0, 3)
	return box


static func well_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PAPER_SUNK
	box.set_corner_radius_all(RADIUS_M)
	box.set_content_margin_all(SPACE_2)
	return box


## Kept for older callers: a card with this radius and padding.
static func parchment_box(radius: int, padding: int) -> StyleBoxFlat:
	var box := card_box(padding)
	box.set_corner_radius_all(radius)
	return box


static func chip_box(color: Color = CHIP) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = Color(INK, 0.7)
	box.set_border_width_all(1)
	box.set_corner_radius_all(99)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 1
	box.content_margin_bottom = 2
	box.anti_aliasing_size = 0.8
	return box


static func bar_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = Color(INK, 0.55)
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	box.anti_aliasing_size = 0.8
	return box


static func need_color(value: float) -> Color:
	if value < 0.3:
		return Color(0.85, 0.36, 0.30)
	if value < 0.6:
		return Color(0.93, 0.68, 0.30)
	return Color(0.45, 0.70, 0.40)


# --- Labels --------------------------------------------------------------------------------

static func inked(label: Label, size: int) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", INK)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## Light text with an ink outline, for words set straight on the world.
static func outlined(label: Label, size: int, outline: int) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.88))
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", outline)


## A plain inked label, optionally wrapping.
static func label(text: String, size: int = BODY, wrap: bool = false) -> Label:
	var result := Label.new()
	result.text = text
	inked(result, size)
	if wrap:
		result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result


## A label in a softer ink: captions, dates, notes.
static func faint(text: String, size: int = SMALL, wrap: bool = false) -> Label:
	var result := label(text, size, wrap)
	result.add_theme_color_override("font_color", INK_FAINT)
	return result


## A title in the storybook face (Fraunces).
static func title(text: String, size: int = TITLE) -> Label:
	var result := label(text, size)
	result.add_theme_font_override("font", font("display"))
	return result


## Words in the Oracle's voice (Fraunces italic).
static func quote(text: String, size: int = BODY, wrap: bool = true) -> Label:
	var result := label(text, size, wrap)
	result.add_theme_font_override("font", font("quote"))
	result.add_theme_color_override("font_color", INK_SOFT)
	return result


## A small heading in tracked capitals.
static func section(text: String) -> Label:
	var result := Label.new()
	result.text = text
	inked(result, CAPTION)
	result.add_theme_font_override("font", font("caps"))
	result.add_theme_color_override("font_color", INK_FAINT)
	return result


## Makes a label bold.
static func strong(target: Label) -> Label:
	target.add_theme_font_override("font", font("strong"))
	return target


# --- Buttons -------------------------------------------------------------------------------

static func ink_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", BODY)
	return button


static func primary_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = "PrimaryButton"
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


## A frameless button with an icon (and optional text).
static func ghost_button(icon_name: String, tip: String = "", text: String = "", icon_size: int = 16) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = "GhostButton"
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = tip
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if icon_name:
		set_icon(button, icon_name, icon_size)
	return button


static func set_icon(button: Button, icon_name: String, icon_size: int) -> void:
	button.icon = UiIcons.texture(icon_name, icon_size)
	button.add_theme_constant_override("icon_max_width", icon_size)
	button.expand_icon = false


## A small ink × button for closing panels.
static func close_button() -> Button:
	var button := ghost_button("close", "Close (Esc)", "", 16)
	button.custom_minimum_size = Vector2(30, 30)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return button


## A flat text button that reads like a link: inked, underlined on hover.
static func link(text: String, size: int = BODY) -> LinkButton:
	var button := LinkButton.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_font_override("font", font("strong"))
	return button


## A row of tabs in a sunk well: toggle buttons sharing a group. Returns the well; the buttons
## are its row's children in order, and each calls on_pick with its name.
static func tabs(names: Array[String], on_pick: Callable, buttons: Dictionary, expand: bool = true) -> PanelContainer:
	var well := PanelContainer.new()
	well.theme_type_variation = "Segmented"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	well.add_child(row)
	var group := ButtonGroup.new()
	for tab_name: String in names:
		var button := Button.new()
		button.text = tab_name
		button.theme_type_variation = "TabButton"
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if expand:
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(on_pick.bind(tab_name))
		row.add_child(button)
		buttons[tab_name] = button
	return well


## A panel's header: its title (and an optional icon) at the left, the close button at the right.
static func header(title_label: Label, close: Button, icon_name: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SPACE_2)
	if icon_name:
		row.add_child(icon(icon_name, 22))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	if close:
		close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(close)
	return row


# --- Small pieces --------------------------------------------------------------------------

## A small chip label (traits, tags).
static func chip(text: String, color: Color = CHIP, size: int = SMALL) -> Label:
	var result := Label.new()
	result.text = text
	result.mouse_filter = Control.MOUSE_FILTER_PASS
	result.add_theme_stylebox_override("normal", chip_box(color))
	inked(result, size)
	return result


## A 0..1 bar colored by how good the value is (or a fixed color). A width of 0 fills the room
## it is given (in a grid, its column stretches).
static func bar(value: float, width: float = 170.0, color: Color = Color.TRANSPARENT) -> ProgressBar:
	var result := ProgressBar.new()
	result.max_value = 1.0
	result.value = clampf(value, 0.0, 1.0)
	result.show_percentage = false
	result.custom_minimum_size = Vector2(width if width > 0.0 else 48.0, 10)
	if width <= 0.0:
		result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	result.add_theme_stylebox_override("background", bar_box(PAPER_SUNK))
	result.add_theme_stylebox_override("fill", bar_box(color if color.a > 0.0 else need_color(value)))
	result.mouse_filter = Control.MOUSE_FILTER_PASS
	return result


## A small square filled with a color, for allele swatches and legends.
static func swatch(color: Color, size: float = 12.0) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(size, size)
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = Color(INK, 0.7)
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", box)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return panel


## An icon from UiIcons at this size.
static func icon(icon_name: String, size: int = 18) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = UiIcons.texture(icon_name, size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(size, size)
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return rect


## A keyboard key, drawn small: shortcut hints.
static func keycap(key: String) -> Label:
	var result := Label.new()
	result.text = key
	result.add_theme_font_size_override("font_size", CAPTION - 1)
	result.add_theme_font_override("font", font("strong"))
	result.add_theme_color_override("font_color", INK_FAINT)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(PAPER, 0.6)
	box.border_color = Color(INK, 0.3)
	box.set_border_width_all(1)
	box.border_width_bottom = 2
	box.set_corner_radius_all(4)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 0
	box.content_margin_bottom = 1
	result.add_theme_stylebox_override("normal", box)
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


# --- Motion --------------------------------------------------------------------------------

## Fades a control in and slides it from an offset (kept in its "slide" meta, which the layout
## adds to its position). Short and eased out; nothing bounces.
static func appear(control: Control, from_offset: Vector2 = Vector2.ZERO, duration: float = MOTION) -> void:
	control.modulate.a = 0.0
	control.set_meta("slide", from_offset)
	var tween := control.create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(control, "modulate:a", 1.0, duration)
	if from_offset != Vector2.ZERO:
		tween.tween_method(func(offset: Vector2) -> void: control.set_meta("slide", offset), from_offset, Vector2.ZERO, duration)


## A modal card: fades in and grows from 97%.
static func pop_in(control: Control) -> void:
	control.modulate.a = 0.0
	control.pivot_offset = control.size / 2.0
	control.scale = Vector2(0.97, 0.97)
	var tween := control.create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(control, "modulate:a", 1.0, MOTION)
	tween.tween_property(control, "scale", Vector2.ONE, MOTION)


static func slide_of(control: Control) -> Vector2:
	return control.get_meta("slide", Vector2.ZERO)
