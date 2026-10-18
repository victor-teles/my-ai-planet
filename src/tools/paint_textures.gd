extends SceneTree
## Paints the tileable brush-stroke texture the toon shader lays over every surface.
##   godot --headless --path Godot -s res://tools/paint_textures.gd
## Red holds light and dark strokes, green warm and cool ones; 0.5 means no change.
## Seeded, so running it again paints the same texture.

const SIZE := 512
const STROKES := 2600
const OUT := "res://art/textures/brush_strokes.png"


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1977
	var value := PackedFloat32Array()
	var warmth := PackedFloat32Array()
	value.resize(SIZE * SIZE)
	warmth.resize(SIZE * SIZE)
	value.fill(0.5)
	warmth.fill(0.5)
	for i: int in STROKES:
		# Strokes mostly lean the same way, like one painter's hand.
		var angle := deg_to_rad(28.0 + rng.randfn(0.0, 22.0))
		var length := rng.randf_range(14.0, 42.0)
		var width := rng.randf_range(4.0, 9.0)
		var center := Vector2(rng.randf() * SIZE, rng.randf() * SIZE)
		_stroke(value, center, angle, length, width, 0.5 + rng.randf_range(-0.32, 0.32))
		_stroke(warmth, center, angle, length, width, 0.5 + rng.randf_range(-0.3, 0.3))
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y: int in SIZE:
		for x: int in SIZE:
			var grain := rng.randf_range(-0.025, 0.025) # canvas tooth
			image.set_pixel(x, y, Color(value[y * SIZE + x] + grain, warmth[y * SIZE + x], 0.5))
	image.save_png(OUT)
	print("Painted ", ProjectSettings.globalize_path(OUT))
	quit()


## One soft-edged, round-ended stroke, wrapping around the edges so the texture tiles.
func _stroke(canvas: PackedFloat32Array, center: Vector2, angle: float, length: float, width: float, tone: float) -> void:
	var along := Vector2.from_angle(angle)
	var across := along.orthogonal()
	var reach := ceili(length / 2.0 + width)
	for dy: int in range(-reach, reach + 1):
		for dx: int in range(-reach, reach + 1):
			var offset := Vector2(dx, dy)
			var u := absf(offset.dot(along)) - length / 2.0
			var v := absf(offset.dot(across))
			var distance := Vector2(maxf(u, 0.0), v).length() / (width / 2.0)
			if distance >= 1.0:
				continue
			var x := posmod(int(center.x) + dx, SIZE)
			var y := posmod(int(center.y) + dy, SIZE)
			var coverage := 0.7 * (1.0 - distance * distance)
			canvas[y * SIZE + x] = lerpf(canvas[y * SIZE + x], tone, coverage)
