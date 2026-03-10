extends Node3D
class_name UnitSpawner

signal placement_finished

enum SpawnSide { TOP, BOTTOM, LEFT, RIGHT }

@export var debug_auto_start: bool = true
@export var hive_scene: PackedScene
@export var highlight_path: NodePath
@export var enemy_scene: PackedScene
@export var enemy_count: int = 5
# Если хочешь детерминированный "рандом" — оставь фиксированный seed
@export var enemy_seed: int = 12345
# Если включишь true — будет каждый запуск по-разному (НЕ детерминировано)
@export var enemy_randomize_each_run: bool = false

@export var enemy_units: Array[PackedScene] = []
@export var board_layer_y: int = 0
@export var board_size: Vector2i = Vector2i(11, 11)
@export var player_spawn_side: SpawnSide = SpawnSide.BOTTOM
@export var spawn_depth_lines: int = 2

@export var battle_state_path: NodePath
@export var input_controller_path: NodePath
@export var units_root_path: NodePath
@export var grid_path: NodePath

@onready var highlight: HighlightManager = get_node(highlight_path) as HighlightManager
@onready var battle_state: BattleState = get_node(battle_state_path) as BattleState
@onready var input_controller: Node = get_node(input_controller_path)
@onready var units_root: Node3D = get_node(units_root_path) as Node3D
@onready var grid: GridMap = get_node(grid_path) as GridMap

var _placing: bool = false
var _player_queue: Array[PackedScene] = []
var _player_index: int = 0
var _allowed_cells: Dictionary = {}

func _ready() -> void:
	if input_controller.has_signal("cell_clicked"):
		input_controller.connect("cell_clicked", Callable(self, "_on_cell_clicked"))
	else:
		push_warning("UnitSpawner: input_controller has no signal 'cell_clicked'.")

	# DEBUG: временно запускаем бой сразу
	var test_player_units: Array[PackedScene] = [
		preload("res://Units/Heroes/hero_capsule.tscn"),
		preload("res://Units/Heroes/hero_sphere.tscn"),
		preload("res://Units/Heroes/hero_square.tscn"),
	]

	if debug_auto_start:
		start_battle(test_player_units)

func start_player_placement(player_units: Array[PackedScene]) -> void:
	_player_queue = player_units.duplicate()
	_player_index = 0
	_allowed_cells = _make_spawn_zone(player_spawn_side, spawn_depth_lines)
	_refresh_spawn_highlight()
	_placing = true

func _refresh_spawn_highlight() -> void:
	if highlight == null:
		return

	var cells: Array[Vector3i] = []
	for k in _allowed_cells.keys():
		var c: Vector3i = k
		# показываем только то, где реально можно спавнить
		if battle_state.can_spawn_on(c):
			cells.append(c)

	highlight.show_cells(cells, HighlightManager.Mode.GREEN)

func cancel_player_placement() -> void:
	_placing = false
	_player_queue.clear()
	_allowed_cells.clear()
	_player_index = 0
	if highlight != null:
		highlight.clear()

func start_battle(player_units: Array[PackedScene]) -> void:
	spawn_enemies(enemy_units)
	start_player_placement(player_units)

func spawn_enemies(enemy_scenes: Array[PackedScene]) -> void:
	if hive_scene != null:
		var w: int = board_size.x
		var h: int = board_size.y

		var cx: int = int(w / 2.0)
		var cz: int = int(h / 2.0)

		var enemy_side: SpawnSide = _opposite_side(player_spawn_side)

		var hive_x: int = cx
		var hive_z: int = cz

		match enemy_side:
			SpawnSide.TOP:
				hive_z = 1
				hive_x = cx
			SpawnSide.BOTTOM:
				hive_z = h - 2
				hive_x = cx
			SpawnSide.LEFT:
				hive_x = 1
				hive_z = cz
			SpawnSide.RIGHT:
				hive_x = w - 2
				hive_z = cz

		var hive_cell: Vector3i = Vector3i(hive_x, board_layer_y, hive_z)

		if battle_state.can_spawn_on(hive_cell):
			var hive: Node3D = hive_scene.instantiate() as Node3D
			units_root.add_child(hive)

			if not battle_state.place(hive, hive_cell):
				push_warning("UnitSpawner: failed to place hive at " + str(hive_cell))
				hive.queue_free()
		else:
			push_warning("UnitSpawner: hive cell is blocked: " + str(hive_cell))
	else:
		push_warning("UnitSpawner: hive_scene is not set.")

	_spawn_from_list(enemy_scenes, true, not enemy_randomize_each_run)

func _spawn_enemies_random() -> void:
	if enemy_scene == null:
		push_warning("UnitSpawner: enemy_scene is null. Assign it in inspector.")
		return
	if enemy_count <= 0:
		return

	var list: Array[PackedScene] = []
	for i: int in range(enemy_count):
		list.append(enemy_scene)

	# randomize_cells = true
	# use_seed = NOT enemy_randomize_each_run (если false — детерминированно)
	_spawn_from_list(list, true, not enemy_randomize_each_run)

func _spawn_from_list(scenes: Array[PackedScene],randomize_cells: bool,use_seed: bool) -> void:
	if scenes.is_empty():
		return

	var enemy_side: SpawnSide = _opposite_side(player_spawn_side)
	var enemy_zone: Dictionary = _make_enemy_zone()

	# Важно: этот порядок идёт "от вражеского края" вглубь карты.
	var ordered_cells: Array[Vector3i] = _ordered_cells(enemy_zone, enemy_side)

	# Фильтруем клетки: единый арбитр спавна
	var free_cells: Array[Vector3i] = []
	for c: Vector3i in ordered_cells:
		if battle_state.can_spawn_on(c):
			free_cells.append(c)

	if free_cells.is_empty():
		push_warning("UnitSpawner: no free cells in enemy zone.")
		return

	# RNG (для "слегка рандомно" внутри полос)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if randomize_cells:
		if use_seed:
			rng.seed = enemy_seed
		else:
			rng.randomize()

	# 1) Сортируем юниты по (роль, приоритет, resource_path) детерминированно
	# 2) BUILDING игнорируем (просто выкидываем из списка)
	var scenes_filtered: Array[PackedScene] = []
	for ps: PackedScene in scenes:
		if ps == null:
			continue
		var role_i: int = _packed_spawn_role(ps)
		if role_i == int(UnitStats.SpawnRole.BUILDING):
			continue
		scenes_filtered.append(ps)

	if scenes_filtered.is_empty():
		return

	var scenes_sorted: Array[PackedScene] = scenes_filtered.duplicate()
	scenes_sorted.sort_custom(func(a: PackedScene, b: PackedScene) -> bool:
		var ra: int = _packed_spawn_role(a)
		var rb: int = _packed_spawn_role(b)

		# Порядок ролей: ATTACK, SUPPORT, DEFENSE (как ты просил)
		# Но для спавна нам удобнее обрабатывать в этом порядке — дальше мы кладём в свои полосы.
		# Если одинаковая роль — сортируем по priority.
		if ra == rb:
			var pa: int = _packed_spawn_priority(a)
			var pb: int = _packed_spawn_priority(b)
			if pa == pb:
				return a.resource_path < b.resource_path
			return pa < pb

		# ATTACK(0) раньше SUPPORT(1) раньше DEFENSE(2)
		return ra < rb
	)

	var bands: Dictionary = _split_cells_for_roles(free_cells)
	var lines: Array = bands["lines"] as Array

	# Слегка рандомно: мешаем клетки ВНУТРИ каждой линии
	if randomize_cells:
		for i_line: int in range(lines.size()):
			var line_cells: Array[Vector3i] = lines[i_line] as Array[Vector3i]
			_shuffle_cells_in_place(line_cells, rng)
			lines[i_line] = line_cells

	# Вместо пулов: распределение по линиям (round-robin)
	var num_lines: int = lines.size()
	if num_lines == 0:
		push_warning("UnitSpawner: enemy zone has 0 lines after filtering.")
		return

	# Курсоры round-robin для каждой роли
	var cursor_attack: int = 0
	var cursor_support: int = 0
	var cursor_defense: int = 0

	for packed: PackedScene in scenes_sorted:
		var role_int: int = _packed_spawn_role(packed)

		# На всякий: BUILDING мы уже фильтровали, но если попадёт — пропускаем
		if role_int == int(UnitStats.SpawnRole.BUILDING):
			continue

		var allowed: Array[int] = _role_allowed_line_indices(role_int, num_lines)

		var pick: Dictionary = {}
		if role_int == int(UnitStats.SpawnRole.ATTACK):
			pick = _pick_cell_round_robin(lines, allowed, cursor_attack)
			cursor_attack = pick["cursor"] as int
		elif role_int == int(UnitStats.SpawnRole.SUPPORT):
			pick = _pick_cell_round_robin(lines, allowed, cursor_support)
			cursor_support = pick["cursor"] as int
		else:
			# DEFENSE
			pick = _pick_cell_round_robin(lines, allowed, cursor_defense)
			cursor_defense = pick["cursor"] as int

		var ok_pick: bool = pick["ok"] as bool
		if not ok_pick:
			push_warning("UnitSpawner: enemy zone is full.")
			return

		var chosen_cell: Vector3i = pick["cell"] as Vector3i

		var ok: bool = _try_spawn_unit(packed, chosen_cell)
		if not ok:
			push_warning("UnitSpawner: place failed for enemy at %s" % [str(chosen_cell)])

func _on_cell_clicked(cell: Vector3i) -> void:
	cell = Vector3i(cell.x, board_layer_y, cell.z)
	if not _placing:
		return
	if highlight != null:
		highlight.clear()
	if not _allowed_cells.has(cell):
		return
	if not battle_state.can_spawn_on(cell):
		return

	var packed := _player_queue[_player_index]
	var unit := packed.instantiate() as Node3D
	units_root.add_child(unit)

	var ok: bool = battle_state.place(unit, cell)
	if not ok:
		unit.queue_free()
		return

	_player_index += 1
	# клетка теперь занята — обновим подсветку зоны спавна
	_refresh_spawn_highlight()
	if _player_index >= _player_queue.size():
		_placing = false
		emit_signal("placement_finished")

func _opposite_side(side: SpawnSide) -> SpawnSide:
	match side:
		SpawnSide.TOP: return SpawnSide.BOTTOM
		SpawnSide.BOTTOM: return SpawnSide.TOP
		SpawnSide.LEFT: return SpawnSide.RIGHT
		SpawnSide.RIGHT: return SpawnSide.LEFT
	return SpawnSide.TOP

func _make_spawn_zone(side: SpawnSide, depth: int) -> Dictionary:
	var w := board_size.x
	var h := board_size.y
	var zone: Dictionary = {}

	depth = clamp(depth, 1, max(w, h))

	match side:
		SpawnSide.TOP:
			for z in range(0, min(depth, h)):
				for x in range(0, w):
					zone[Vector3i(x, board_layer_y, z)] = true
		SpawnSide.BOTTOM:
			for z in range(max(0, h - depth), h):
				for x in range(0, w):
					zone[Vector3i(x, board_layer_y, z)] = true
		SpawnSide.LEFT:
			for x in range(0, min(depth, w)):
				for z in range(0, h):
					zone[Vector3i(x, board_layer_y, z)] = true
		SpawnSide.RIGHT:
			for x in range(max(0, w - depth), w):
				for z in range(0, h):
					zone[Vector3i(x, board_layer_y, z)] = true

	return zone

func _ordered_cells(zone: Dictionary, side: Variant = null) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for k: Variant in zone.keys():
		cells.append(k as Vector3i)

	# по умолчанию — твой старый порядок (z, потом x)
	if side == null:
		cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
			if a.z == b.z:
				return a.x < b.x
			return a.z < b.z
		)
		return cells

	var s: SpawnSide = side as SpawnSide
	var w: int = board_size.x
	var h: int = board_size.y

	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		var da: int = 0
		var db: int = 0
		var ca: int = 0
		var cb: int = 0

		match s:
			SpawnSide.TOP:
				da = a.z
				db = b.z
				ca = a.x
				cb = b.x
			SpawnSide.BOTTOM:
				da = (h - 1) - a.z
				db = (h - 1) - b.z
				ca = a.x
				cb = b.x
			SpawnSide.LEFT:
				da = a.x
				db = b.x
				ca = a.z
				cb = b.z
			SpawnSide.RIGHT:
				da = (w - 1) - a.x
				db = (w - 1) - b.x
				ca = a.z
				cb = b.z

		if da == db:
			return ca < cb
		return da < db
	)

	return cells

func _shuffle_cells_in_place(cells: Array[Vector3i], rng: RandomNumberGenerator) -> void:
	# Fisher–Yates shuffle (детерминированно при фиксированном seed)
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cells[i]
		cells[i] = cells[j]
		cells[j] = tmp

func _is_edge_cell(cell: Vector3i) -> bool:
	var w: int = board_size.x
	var h: int = board_size.y
	return cell.x == 0 or cell.x == (w - 1) or cell.z == 0 or cell.z == (h - 1)

func _make_enemy_zone() -> Dictionary:
	var w: int = board_size.x
	var h: int = board_size.y

	# Внутренняя область без краёв: x=1..w-2, z=1..h-2
	var x_min: int = 1
	var x_max: int = w - 2
	var z_min: int = 1
	var z_max: int = h - 2

	var zone: Dictionary = {}
	if x_max < x_min or z_max < z_min:
		return zone

	for z: int in range(z_min, z_max + 1):
		for x: int in range(x_min, x_max + 1):
			zone[Vector3i(x, board_layer_y, z)] = true

	# Запрет зоны игрока (глубиной spawn_depth_lines)
	var player_zone: Dictionary = _make_spawn_zone(player_spawn_side, spawn_depth_lines)
	for k: Variant in player_zone.keys():
		var pc: Vector3i = k as Vector3i
		if zone.has(pc):
			zone.erase(pc)

	return zone

func _try_spawn_unit(packed: PackedScene, cell: Vector3i) -> bool:
	if packed == null:
		return false
	if not battle_state.can_spawn_on(cell):
		return false

	var unit: Node3D = packed.instantiate() as Node3D
	if unit == null:
		return false

	# ВАЖНО: global_position работает корректно только когда юнит в дереве
	units_root.add_child(unit)

	var ok: bool = battle_state.place(unit, cell)
	if not ok:
		units_root.remove_child(unit)
		unit.queue_free()

	return ok

func _packed_spawn_role(packed: PackedScene) -> int:
	# Возвращает int(UnitStats.SpawnRole.*)
	# Если нет stats — считаем ATTACK
	var role: int = int(UnitStats.SpawnRole.ATTACK)

	if packed == null:
		return role

	var tmp: Node3D = packed.instantiate() as Node3D
	if tmp == null:
		return role

	if tmp.has_method("get_stats"):
		var st: UnitStats = tmp.call("get_stats") as UnitStats
		if st != null:
			role = int(st.spawn_role)

	tmp.queue_free()
	return role

func _packed_spawn_priority(packed: PackedScene) -> int:
	var pr: int = 0
	if packed == null:
		return pr

	var tmp: Node3D = packed.instantiate() as Node3D
	if tmp == null:
		return pr

	if tmp.has_method("get_stats"):
		var st: UnitStats = tmp.call("get_stats") as UnitStats
		if st != null:
			pr = int(st.spawn_priority)

	tmp.queue_free()
	return pr

func _split_cells_for_roles(ordered_cells_from_enemy_zone: Array[Vector3i]) -> Dictionary:
	# Группируем по "линии" относительно игрока:
	# TOP/BOTTOM -> по z, LEFT/RIGHT -> по x
	var lines_dict: Dictionary = {} # key:int -> Array (raw)

	for c: Vector3i in ordered_cells_from_enemy_zone:
		var key: int = 0
		match player_spawn_side:
			SpawnSide.TOP, SpawnSide.BOTTOM:
				key = c.z
			SpawnSide.LEFT, SpawnSide.RIGHT:
				key = c.x

		if not lines_dict.has(key):
			lines_dict[key] = []

		var raw: Array = lines_dict[key] as Array
		raw.append(c)
		lines_dict[key] = raw

	# Сортируем ключи так, чтобы первым шли линии БЛИЖЕ к игроку
	var keys: Array[int] = []
	for k: Variant in lines_dict.keys():
		keys.append(k as int)

	keys.sort_custom(func(a: int, b: int) -> bool:
		match player_spawn_side:
			SpawnSide.TOP:
				return a < b # меньше z ближе к TOP
			SpawnSide.BOTTOM:
				return a > b # больше z ближе к BOTTOM
			SpawnSide.LEFT:
				return a < b # меньше x ближе к LEFT
			SpawnSide.RIGHT:
				return a > b # больше x ближе к RIGHT
		return a < b
	)

	# Собираем lines как Array, каждый элемент — Array[Vector3i]
	var lines: Array = []
	for kk: int in keys:
		var raw_line: Array = lines_dict[kk] as Array
		var typed_line: Array[Vector3i] = []
		for v: Variant in raw_line:
			typed_line.append(v as Vector3i)
		lines.append(typed_line)

	return {"lines": lines}

func _role_allowed_line_indices(role_int: int, num_lines: int) -> Array[int]:
	var idx: Array[int] = []
	if num_lines <= 0:
		return idx

	# Линии: 0 = ближайшая к игроку, num_lines-1 = самая дальняя
	var attack_count: int = min(3, num_lines)
	var defense_count: int = min(3, num_lines)

	var attack_start: int = 0
	var attack_end: int = attack_count - 1 # включительно

	var defense_end: int = num_lines - 1
	var defense_start: int = max(0, num_lines - defense_count) # включительно

	# Support: 4 линии, с перекрытием: одна с attack (последняя attack),
	# одна с defense (первая defense). Между ними заполняем.
	var support_start: int = max(0, attack_end)          # включает overlap с attack
	var support_end: int = min(defense_start, num_lines - 1) # включает overlap с defense

	# Если между overlap'ами мало линий — расширяем в пределах массива
	# хотим примерно 4 линии поддержки
	while (support_end - support_start + 1) < 4 and support_start > 0:
		support_start -= 1
	while (support_end - support_start + 1) < 4 and support_end < num_lines - 1:
		support_end += 1

	if role_int == int(UnitStats.SpawnRole.ATTACK):
		for i: int in range(attack_start, attack_end + 1):
			idx.append(i)

	elif role_int == int(UnitStats.SpawnRole.SUPPORT):
		for j: int in range(support_start, support_end + 1):
			idx.append(j)

	else:
		# DEFENSE
		for k: int in range(defense_start, defense_end + 1):
			idx.append(k)

	return idx


func _pick_cell_round_robin(lines: Array, allowed: Array[int], cursor: int) -> Dictionary:
	var result: Dictionary = {"cell": BattleState.INVALID_CELL, "cursor": cursor, "ok": false}

	if allowed.is_empty():
		return result

	var tries: int = allowed.size()
	var local_cursor: int = cursor

	for t: int in range(tries):
		var line_index: int = allowed[local_cursor] as int
		local_cursor = (local_cursor + 1) % allowed.size()

		var line_cells: Array[Vector3i] = lines[line_index] as Array[Vector3i]

		while not line_cells.is_empty() and not battle_state.can_spawn_on(line_cells[0]):
			line_cells.remove_at(0)

		if not line_cells.is_empty():
			var cell: Vector3i = line_cells[0]
			line_cells.remove_at(0)
			lines[line_index] = line_cells

			result["cell"] = cell
			result["cursor"] = local_cursor
			result["ok"] = true
			return result

	result["cursor"] = local_cursor
	return result
