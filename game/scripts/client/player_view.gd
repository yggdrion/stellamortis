class_name PlayerView
extends Node3D
## A player's look until M2's animated model: a capsule in the player's color with a visor
## showing where it faces, and its name above. The origin is at the feet.


func _init(player_name: String, peer_id: int, show_name: bool) -> void:
	var color := Color.from_hsv(fposmod(peer_id * 0.61803, 1.0), 0.55, 0.9)
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = SimPlayer.HEIGHT
	capsule.radius = SimPlayer.RADIUS
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5
	capsule.material = material
	body.mesh = capsule
	body.position.y = SimPlayer.HEIGHT / 2.0
	add_child(body)

	var visor := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.18, 0.2)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.1, 0.9, 1.0)
	glass.emission_enabled = true
	glass.emission = Color(0.1, 0.9, 1.0)
	glass.emission_energy_multiplier = 2.0
	box.material = glass
	visor.mesh = box
	visor.position = Vector3(0.0, 1.5, -0.32)
	add_child(visor)

	if show_name:
		var label := Label3D.new()
		label.text = player_name
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position.y = SimPlayer.HEIGHT + 0.35
		label.font_size = 48
		label.pixel_size = 0.005
		label.outline_size = 12
		add_child(label)
