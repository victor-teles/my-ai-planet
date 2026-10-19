extends SceneTree
## Villagers crossing a marked floor at set speeds, seen side on, for checking that planted feet
## stay put. They really move (the animator measures their movement, as in a camp), so this checks
## the game's path. Record frames with Movie Maker:
##   godot --path src --resolution 1600x700 --write-movie /abs/dir/f.png --fixed-fps 30 \
##     --quit-after 90 -s res://tools/walk_by.gd -- [--speeds=0.42,0.9,1.6] [--carry]

const SKY_SHADER := preload("res://art/shaders/sky_dusk.gdshader")

var _walkers: Array[Node3D] = []
var _speeds: Array[float] = [0.42, 0.9, 1.6]
var _start := -1.6


func _initialize() -> void:
	var carry := false
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=")
		if pair[0] == "speeds" and pair.size() > 1:
			_speeds.clear()
			for value: String in pair[1].split(","):
				_speeds.append(float(value))
		elif pair[0] == "carry":
			carry = true
	var world := Node3D.new()
	root.add_child(world)
	var sky_material := ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.50, 0.36, 0.70)
	environment.ambient_light_energy = 0.6
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-20.0), 0.0)
	world.add_child(sun)
	# A floor striped every 0.1 units along the walk, so a sliding foot shows against the stripes.
	for i: int in 60:
		var stripe := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.1, 0.02, 3.0)
		stripe.mesh = box
		stripe.position = Vector3(-3.0 + i * 0.1 + 0.05, -0.01, 0.0)
		stripe.material_override = ToonMaterials.get_material(Color(0.46, 0.70, 0.38) if i % 2 == 0 else Color(0.40, 0.60, 0.34), 0.0, true)
		world.add_child(stripe)
	var camera := Camera3D.new()
	camera.fov = 30.0
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 0.55, 4.2), Vector3(0.0, 0.25, 0.0))
	for i: int in _speeds.size():
		var looks := VillagerArt.appearance(11 + i * 12, i % 2 == 0, 30, false, Color(0.86, 0.38, 0.52).lerp(Color(0.25, 0.42, 0.72), i / 2.0))
		var walker := VillagerArt.make(looks, i)
		walker.position = Vector3(_start, 0.0, -0.6 + i * 0.6)
		walker.rotation.y = PI / 2.0 # face +X
		world.add_child(walker)
		VillagerArt.animator(walker).fixed_rate = 1
		if carry:
			VillagerArt.set_carry(walker, "wood")
		_walkers.append(walker)
		var label := Label3D.new()
		label.text = "%.2f u/s" % _speeds[i]
		label.pixel_size = 0.004
		label.position = Vector3(0.0, 0.85, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		walker.add_child(label)


func _process(delta: float) -> bool:
	for i: int in _walkers.size():
		var walker := _walkers[i]
		walker.position.x += _speeds[i] * delta
		VillagerArt.set_locomotion_speed(walker, _speeds[i])
		if walker.position.x > 1.8:
			walker.position.x = _start
	return false
