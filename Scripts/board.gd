extends Node3D
class_name Board

@export var grid: GridMap
@export var board_collision: StaticBody3D

@export var size: Vector2i = Vector2i(11, 11)
@export var auto_fit_collision: bool = false # <- ВАЖНО: false = ручная коллизия

func _ready() -> void:
	if grid == null:
		grid = get_node_or_null("Grid") as GridMap
	if board_collision == null:
		board_collision = get_node_or_null("BoardCollision") as StaticBody3D

	if auto_fit_collision:
		_fit_board_collision_to_size()

func is_in_bounds(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.z >= 0 and cell.x < size.x and cell.z < size.y

func _fit_board_collision_to_size() -> void:
	if board_collision == null:
		return
	var shape_node := board_collision.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return
	var box := shape_node.shape as BoxShape3D
	if box == null:
		return

	box.size = Vector3(size.x, 0.2, size.y)
	board_collision.position = Vector3((size.x - 1) * 0.5, 0.0, (size.y - 1) * 0.5)
