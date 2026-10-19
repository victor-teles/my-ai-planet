extends SceneTree
## Lists every clip in the two Quaternius Universal Animation Library files, with lengths.
## Usage: godot --headless --path src -s res://tools/clip_inventory.gd

const SOURCES: Array[String] = [
	"res://art/characters/quaternius/ual1_standard.glb",
	"res://art/characters/quaternius/ual2_standard.glb",
]


func _initialize() -> void:
	for path: String in SOURCES:
		var scene := (load(path) as PackedScene).instantiate()
		var player := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var names := player.get_animation_list()
		var parts := PackedStringArray()
		for clip: StringName in names:
			parts.append("%s (%.2fs)" % [clip, player.get_animation(clip).length])
		print("%s: %d clips" % [path.get_file(), names.size()])
		for part: String in parts:
			print("  ", part)
		scene.free()
	quit()
