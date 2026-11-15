class_name ScatterShape
extends Resource
## The solid part of one Scatter.Kind (M35): a box, cylinder or sphere sized in meters for a point
## of size factor 1.0 (TerrainView scales the model by 0.8 + 0.5 * the point's size roll; the
## shape takes the same factor). Files live in res://data/scatter/<kind in lower case>.tres. A
## trunk is only its trunk, not the crown. Pure data and math: a worker thread builds the
## Solids, the main thread makes the physics shapes (TerrainChunks._add_body).

enum Form { BOX, CYLINDER, SPHERE }

static var _shapes: Array[ScatterShape] = []

@export var form := Form.BOX
## BOX: full extents (x, height above ground, z). CYLINDER: x radius, y height. SPHERE: x radius,
## y the height of its center over the ground (negative: a dome).
@export var size := Vector3.ONE
## Meters the box or cylinder reaches under the ground (so slopes leave no gap).
@export var sink := 0.3


static func of_kind(kind: int) -> ScatterShape:
	if _shapes.is_empty():
		for name_of: String in Scatter.Kind.keys():
			_shapes.append(load("res://data/scatter/%s.tres" % name_of.to_lower()) as ScatterShape)
	return _shapes[kind]


## Every point's solid, in the points' order. Same frame as TerrainView._transform (standing
## along the point's up, turned by its yaw), so shape and model line up.
static func solids(points: Array[Scatter.Point]) -> Array[Solid]:
	var found: Array[Solid] = []
	for point in points:
		var solid := Solid.new()
		solid.shape = of_kind(point.kind)
		solid.scale_by = 0.8 + 0.5 * point.size
		var forward := SimPlayer._tangent(Vector3.FORWARD, point.up)
		var basis := SimPlayer.frame(point.up, forward).rotated(point.up, point.yaw)
		var size := solid.extents()
		var center := 0.0
		match solid.shape.form:
			Form.SPHERE:
				center = size.y
			_:
				center = (size.y - solid.shape.sink) * 0.5
		solid.transform = Transform3D(basis, point.position + point.up * center)
		found.append(solid)
	return found


## Radius of the circle around the center that holds the shape's footprint, for extents.
func footprint(extents: Vector3) -> float:
	if form == Form.BOX:
		return 0.5 * Vector2(extents.x, extents.z).length()
	return extents.x


## The physics shape of a solid (main thread only).
func make(extents: Vector3) -> Shape3D:
	match form:
		Form.SPHERE:
			var sphere := SphereShape3D.new()
			sphere.radius = extents.x
			return sphere
		Form.CYLINDER:
			var cylinder := CylinderShape3D.new()
			cylinder.radius = extents.x
			cylinder.height = extents.y + sink
			return cylinder
	var box := BoxShape3D.new()
	box.size = Vector3(extents.x, extents.y + sink, extents.z)
	return box


## One solid of a chunk: a shape and where it stands, realm relative.
class Solid:
	extends RefCounted
	var shape: ScatterShape
	var transform: Transform3D
	## The size factor of the point (0.8 to 1.3).
	var scale_by: float

	## The shape's extents for this point (see size).
	func extents() -> Vector3:
		return shape.size * scale_by
