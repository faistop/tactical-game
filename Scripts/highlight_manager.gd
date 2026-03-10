extends Node3D
class_name HighlightManager

enum Mode { GREEN, RED, YELLOW }

@export var green_tile_scene: PackedScene
@export var red_tile_scene: PackedScene
@export var yellow_tile_scene: PackedScene

@export var floor_world_y: float = 0.0
@export var lock_to_floor_y: bool = true

@export var grid_path: NodePath
@export var board_size: Vector2i = Vector2i(11, 11)
@export var board_layer_y: int = 0

@export var y_offset: float = 0.06
@export var tile_size: float = 0.95

@onready var grid: GridMap = get_node(grid_path) as GridMap

var _sticky_cells: Dictionary = {} # Vector3i -> Mode
var _temp_cells: Dictionary = {}   # Vector3i -> Mode
var _modes: Dictionary = {} # Vector3i -> Mode

# Vector3i -> MeshInstance3D
var _tiles: Dictionary = {}

func clear() -> void:
	for cell in _tiles.keys():
		var n: Node3D = _tiles[cell] as Node3D
		if is_instance_valid(n):
			n.queue_free()
	_tiles.clear()
	_modes.clear()
	_sticky_cells.clear()
	_temp_cells.clear()

func show_cells(cells: Array[Vector3i], mode: Mode = Mode.GREEN) -> void:
	clear_temp()
	for c in cells:
		_temp_cells[Vector3i(c.x, board_layer_y, c.z)] = mode
		_set_cell(c, mode)

func _set_cell(cell_in: Vector3i, mode: Mode) -> void:
	if grid == null:
		return

	var cell := Vector3i(cell_in.x, board_layer_y, cell_in.z)

	if cell.x < 0 or cell.x >= board_size.x:
		return
	if cell.z < 0 or cell.z >= board_size.y:
		return

	# если клетка уже подсвечена, но режим другой — пересоздаём
	if _tiles.has(cell):
		var old_mode_v: Variant = _modes.get(cell, null)
		if old_mode_v != null and (old_mode_v as Mode) != mode:
			var old_node: Node3D = _tiles[cell] as Node3D
			if is_instance_valid(old_node):
				old_node.queue_free()
			_tiles.erase(cell)
			_modes.erase(cell)

	# создаём, если нет
	if not _tiles.has(cell):
		var node := _create_tile_instance(cell, mode)
		if node != null:
			_tiles[cell] = node
			_modes[cell] = mode

func _unset_cell(cell_in: Vector3i) -> void:
	var cell := Vector3i(cell_in.x, board_layer_y, cell_in.z)

	if _tiles.has(cell):
		var old_node: Node3D = _tiles[cell] as Node3D
		if is_instance_valid(old_node):
			old_node.queue_free()
		_tiles.erase(cell)
		_modes.erase(cell)

func _create_tile_instance(cell: Vector3i, mode: Mode) -> Node3D:
	var scene: PackedScene = null
	match mode:
		Mode.GREEN:
			scene = green_tile_scene
		Mode.RED:
			scene = red_tile_scene
		Mode.YELLOW:
			scene = yellow_tile_scene

	if scene == null:
		push_warning("HighlightManager: tile scene is not assigned for mode=%s" % [str(mode)])
		return null

	var node := scene.instantiate() as Node3D
	if node == null:
		push_warning("HighlightManager: instantiated tile is not Node3D. Make root Node3D in hl_*.tscn")
		return null

	add_child(node) # сначала в дерево

	# берем центр клетки из GridMap
	var local_pos: Vector3 = grid.map_to_local(cell)
	var world_pos: Vector3 = grid.to_global(local_pos)

	# фиксируем Y к полу (как ты уже починил)
	if lock_to_floor_y:
		world_pos.y = floor_world_y + y_offset
	else:
		world_pos.y += y_offset

	node.global_position = world_pos
	return node

func clear_temp() -> void:
	for key: Variant in _temp_cells.keys():
		var cell: Vector3i = key as Vector3i
		if _sticky_cells.has(cell):
			var m: Mode = _sticky_cells[cell] as Mode
			_set_cell(cell, m)
		else:
			_unset_cell(cell)
	_temp_cells.clear()

func show_sticky_cells(cells: Array[Vector3i], mode: Mode = Mode.RED) -> void:
	clear_sticky()

	for c: Vector3i in cells:
		var cell: Vector3i = Vector3i(c.x, board_layer_y, c.z)
		_sticky_cells[cell] = mode
		_set_cell(cell, mode)

	# восстановить temp поверх (если был)
	for key: Variant in _temp_cells.keys():
		var tc: Vector3i = key as Vector3i
		var m: Mode = _temp_cells[tc] as Mode
		_set_cell(tc, m)

func add_sticky_cells(cells: Array[Vector3i], mode: Mode) -> void:
	for c: Vector3i in cells:
		var cell: Vector3i = Vector3i(c.x, board_layer_y, c.z)
		_sticky_cells[cell] = mode
		_set_cell(cell, mode)

	# temp должен оставаться поверх sticky
	for key: Variant in _temp_cells.keys():
		var tc: Vector3i = key as Vector3i
		var m: Mode = _temp_cells[tc] as Mode
		_set_cell(tc, m)

func clear_sticky() -> void:
	# убрать только липкие клетки
	for key: Variant in _sticky_cells.keys():
		var cell: Vector3i = key as Vector3i
		if _temp_cells.has(cell):
			# вернуть временный режим КАК БЫЛ
			var m: Mode = _temp_cells[cell] as Mode
			_set_cell(cell, m)
		else:
			_unset_cell(cell)
	_sticky_cells.clear()
