class_name FlatGround
extends RefCounted
## A flat floor at the origin for tests that need no realm: 160 m square on the world layer,
## its top at y = 0. With a stair: six 0.4 m risers 0.8 m deep, the top at 2.4 m, starting at
## z = -26.


static func add(parent: Node, with_stair := false) -> void:
	box(parent, Vector3(0, -0.5, 0), Vector3(160, 1, 160))
	if with_stair:
		for s in 6:
			box(parent, Vector3(8, 0.2 + s * 0.2, -26 - s * 0.8), Vector3(4, 0.4 + s * 0.4, 0.8))


## A static box of a size, its middle at a point, on the world layer.
static func box(parent: Node, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = SimPlayer.LAYER_WORLD
	body.collision_mask = 0
	body.position = at
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = size
	shape.shape = cube
	body.add_child(shape)
	parent.add_child(body)
