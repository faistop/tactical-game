extends Node3D
class_name BattleInputController

signal cell_clicked(cell: Vector3i)

@export var board: Board
@export var camera: Camera3D

const INVALID_CELL := Vector3i(-999, -999, -999)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body

func _get_cell_under_mouse() -> Vector3i:
	if board == null or board.grid == null or camera == null:
		return INVALID_CELL

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	var ray_to := ray_origin + ray_dir * 1000.0

	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(ray_origin, ray_to)
	# ВАЖНО: чтобы луч не попадал в юнитов/декор — кликаем только по полу
	# Настрой collision_layer у BoardCollision, например Layer 1.
	params.collision_mask = 1
	params.collide_with_areas = false
	params.collide_with_bodies = true

	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return INVALID_CELL

	# Немного сдвигаемся внутрь поверхности, чтобы не ловить пограничные случаи
	var hit_pos: Vector3 = hit.position + hit.normal * 0.01

	var local := board.grid.to_local(hit_pos)
	var cell := board.grid.local_to_map(local)

	# Жесткая проверка границ — чтобы не было кликов "за полем"
	if not board.is_in_bounds(cell):
		return INVALID_CELL

	return cell

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell := _get_cell_under_mouse()
		if cell != INVALID_CELL:
			emit_signal("cell_clicked", cell)

func get_cell_under_mouse() -> Vector3i:
	return _get_cell_under_mouse()
