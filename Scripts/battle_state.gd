extends Node3D
class_name BattleState

enum UnitState { READY, SPENT }
enum UnitAction { MOVE = 1, ATTACK = 2, CLEAN = 4,}

@export var grid_path: NodePath
@onready var grid: GridMap = get_node(grid_path) as GridMap

@export var unit_status_manager_path: NodePath
@onready var unit_status_manager: UnitStatusManager = get_node(unit_status_manager_path) as UnitStatusManager

@export var cell_entities_path: NodePath
@onready var cell_entities: CellEntities = get_node(cell_entities_path) as CellEntities

signal cell_cleaned(cell: Vector3i, by_unit: Node3D)
signal unit_hp_changed(unit: Node3D, hp: int, max_hp: int)
signal unit_removed(unit: Node3D, cell: Vector3i)

const MAX_AP_PER_ROUND: int = 2
const INVALID_CELL: Vector3i = Vector3i(999999, 999999, 999999)

var _mp_left: Dictionary = {} # Dictionary[Node3D, int]
# Реакции “на клетку” (например prepared attack). key = Vector3i
# value = Dictionary с данными (тип/урон/стоп и т.п.)
var _cell_reactions: Dictionary = {} # Dictionary[Vector3i, Dictionary]
var _ap_left: Dictionary = {}        # key: Node3D, value: int
var _actions_used: Dictionary = {}   # key: Node3D, value: int (bitmask)
var _unit_state: Dictionary = {} # key: unit instance_id -> UnitState
var occupied: Dictionary = {}
# клетки, где нельзя спавнить (горы/декор/стены и т.п.)
var spawn_blocked: Dictionary = {} # key: Vector3i -> true

func begin_round() -> void:
	_unit_state.clear()

	_ap_left.clear()
	_actions_used.clear()

	# Инициализируем AP/флаги на раунд для всех юнитов, которые стоят на поле
	for c: Variant in occupied.keys():
		var cell: Vector3i = c as Vector3i
		var u: Node3D = occupied.get(cell) as Node3D
		if u == null:
			continue
		_ap_left[u] = MAX_AP_PER_ROUND
		_actions_used[u] = 0

	if unit_status_manager != null:
		unit_status_manager.begin_round()

	if cell_entities != null:
		cell_entities.tick_round()

	_reset_mp_for_all_units()
	_cell_reactions.clear()

func is_unit_ready(unit: Node) -> bool:
	if unit == null:
		return false
	return _unit_state.get(unit.get_instance_id(), UnitState.READY) == UnitState.READY

func set_unit_spent(unit: Node) -> void:
	if unit == null:
		return
	_unit_state[unit.get_instance_id()] = UnitState.SPENT

func is_occupied(cell: Vector3i) -> bool:
	return occupied.has(cell)

func place(unit: Node3D, cell: Vector3i) -> bool:
	if unit == null or grid == null:
		return false
	if not can_spawn_on(cell):
		return false

	var local_pos: Vector3 = grid.map_to_local(cell)
	var world_pos: Vector3 = grid.to_global(local_pos)

	unit.global_position = world_pos
	occupied[cell] = unit

	var st: UnitStats = get_stats(unit) as UnitStats
	if st != null:
		var cb: Callable = Callable(self, "_on_stats_hp_changed").bind(unit)
		if not st.hp_changed.is_connected(cb):
			st.hp_changed.connect(cb)

	return true

func clear_cell(cell: Vector3i) -> void:
	if occupied.has(cell):
		occupied.erase(cell)

func manhattan_cells(a: Vector3i, b: Vector3i) -> int:
	return abs(a.x - b.x) + abs(a.z - b.z)

func can_move_by_range(unit: Node3D, from_cell: Vector3i, to_cell: Vector3i) -> bool:
	if unit == null:
		return false
	# PUSH двигает на 1 клетку за шаг: просто проверяем вход
	return can_enter_cell(unit, from_cell, to_cell)

func get_unit_at(cell: Vector3i) -> Node3D:
	if occupied.has(cell):
		return occupied[cell] as Node3D
	return null

func move_unit(unit: Node3D, from_cell: Vector3i, to_cell: Vector3i) -> bool:

	if unit == null or grid == null:
		return false
	if not occupied.has(from_cell):
		return false
	if occupied[from_cell] != unit:
		return false
	if is_occupied(to_cell):
		return false

	# обновляем occupied
	occupied.erase(from_cell)
	occupied[to_cell] = unit

	# двигаем в центр клетки
	var local_pos: Vector3 = grid.map_to_local(to_cell)
	unit.global_position = grid.to_global(local_pos)
	return true

func can_start_move(unit: Node3D) -> bool:
	if unit == null:
		return false

	# Запрещаем двигаться, если уже была атака или чистка
	if has_used_action(unit, UnitAction.ATTACK):
		return false
	if has_used_action(unit, UnitAction.CLEAN):
		return false

	# Можно начать движение, если можем потратить MOVE (1 AP)
	return can_spend_action(unit, UnitAction.MOVE)

func on_move_started(unit: Node3D) -> void:
	if unit == null:
		return
	# Тратим MOVE action один раз при первом шаге движения
	if not has_used_action(unit, UnitAction.MOVE):
		spend_action(unit, UnitAction.MOVE)

func force_move_unit(unit: Node3D, from_cell: Vector3i, to_cell: Vector3i) -> bool:
	if unit == null or grid == null:
		return false
	if not occupied.has(from_cell):
		return false
	if occupied[from_cell] != unit:
		return false
	if is_occupied(to_cell):
		return false

	occupied.erase(from_cell)
	occupied[to_cell] = unit

	var local_pos: Vector3 = grid.map_to_local(to_cell)
	unit.global_position = grid.to_global(local_pos)
	return true

func get_stats(unit: Node3D) -> UnitStats:
	if unit == null:
		return null

	# если это наш Unit-скрипт
	if unit is Unit:
		return (unit as Unit).stats

	# если есть метод get_stats()
	if unit.has_method("get_stats"):
		return unit.call("get_stats") as UnitStats

	# fallback: если статы лежат child-node с именем UnitStats
	if unit.has_node("UnitStats"):
		return unit.get_node("UnitStats") as UnitStats

	return null

func set_spawn_blocked(cell: Vector3i, blocked: bool) -> void:
	if blocked:
		spawn_blocked[cell] = true
	else:
		if spawn_blocked.has(cell):
			spawn_blocked.erase(cell)

func is_spawn_blocked(cell: Vector3i) -> bool:
	return spawn_blocked.has(cell)

func can_spawn_on(cell: Vector3i) -> bool:
	if is_occupied(cell):
		return false
	if is_spawn_blocked(cell):
		return false
	if cell_entities != null and cell_entities.has_spawn_blocker_at(cell):
		return false
	return true

func is_rooted(unit: Node3D) -> bool:
	if unit_status_manager == null:
		return false
	return unit_status_manager.is_rooted(unit)

func apply_root(unit: Node3D, owner_unit: Node3D) -> void:
	if unit_status_manager == null:
		return
	unit_status_manager.apply_root(unit, owner_unit)

func clear_root(unit: Node3D) -> void:
	if unit_status_manager == null:
		return
	unit_status_manager.clear_root(unit)

func is_rooted_by_owner(unit: Node3D, owner_unit: Node3D) -> bool:
	if unit_status_manager == null:
		return false
	return unit_status_manager.is_rooted_by_owner(unit, owner_unit)

func get_unit_cell(unit: Node3D) -> Vector3i:
	# Если у тебя есть словарь cell -> unit, чаще всего он называется occupied
	# Подставь имя своего словаря, если оно другое.
	for cell in occupied.keys():
		if occupied[cell] == unit:
			return cell
	return INVALID_CELL

func can_attack(attacker: Node3D, from_cell: Vector3i, target_cell: Vector3i) -> bool:
	var st = get_stats(attacker)
	if st == null:
		return false

	var d: int = abs(target_cell.x - from_cell.x) + abs(target_cell.z - from_cell.z)

	# MELEE
	if st.ai_role == UnitStats.AIRole.MELEE:
		return d == 1

	# RANGED
	if st.ai_role == UnitStats.AIRole.RANGED:
		return d >= st.shoot_min_range and d <= st.shoot_range

	return false

func get_ap_left(unit: Node3D) -> int:
	if unit == null:
		return 0
	return int(_ap_left.get(unit, MAX_AP_PER_ROUND))

func _get_actions_mask(unit: Node3D) -> int:
	return int(_actions_used.get(unit, 0))

func has_used_action(unit: Node3D, action: int) -> bool:
	if unit == null:
		return false
	return (_get_actions_mask(unit) & action) != 0

func can_spend_action(unit: Node3D, action: int) -> bool:
	if unit == null:
		return false
	if not is_unit_ready(unit):
		return false

	# rooted запрещает движение
	if action == UnitAction.MOVE and is_rooted(unit):
		return false

	var ap: int = get_ap_left(unit)
	if ap <= 0:
		return false

	if has_used_action(unit, action):
		return false

	return true

func spend_action(unit: Node3D, action: int) -> bool:
	if not can_spend_action(unit, action):
		return false

	var ap: int = get_ap_left(unit)
	ap -= 1
	_ap_left[unit] = ap

	var mask: int = _get_actions_mask(unit)
	mask |= action
	_actions_used[unit] = mask

	if ap <= 0:
		set_unit_spent(unit)

	return true

func attack(attacker: Node3D, from_cell: Vector3i, target_cell: Vector3i, force: bool = false) -> bool:
	if not force:
		if not can_attack(attacker, from_cell, target_cell):
			return false

	# AP: атака можно сделать только 1 раз за раунд и если есть AP
	if not spend_action(attacker, UnitAction.ATTACK):
		return false

	var target_unit: Node3D = get_unit_at(target_cell)

	var target_name: String = "none"
	if target_unit != null:
		target_name = str(target_unit.name)

	# атака в пустоту разрешена (можешь потом запретить)
	if target_unit == null:
		print("[ATTACK] ", str(attacker.name), " attacks cell ", target_cell, " target=none")
		return true

	var a_stats: UnitStats = get_stats(attacker)
	var t_stats: UnitStats = get_stats(target_unit)
	if a_stats == null or t_stats == null:
		return false

	if a_stats.faction == t_stats.faction and not force:
		return false

	# 1) PUSH (толчок) — без board.is_in_bounds, проверяем через can_move_by_range/move_unit
	if a_stats.attack_effect == UnitStats.AttackEffect.PUSH:
		var dx: int = target_cell.x - from_cell.x
		var dz: int = target_cell.z - from_cell.z

		var dir: Vector3i = Vector3i.ZERO
		if abs(dx) > abs(dz):
			dir = Vector3i(signi(dx), 0, 0)
		else:
			dir = Vector3i(0, 0, signi(dz))

		var steps: int = max(a_stats.push_power, 0)
		var cur: Vector3i = target_cell

		for i: int in range(steps):
			var nxt: Vector3i = cur + dir

		# используем существующую проверку (границы/занятость/дальность)
			if not can_move_by_range(target_unit, cur, nxt):
				break

			var moved: bool = force_move_unit(target_unit, cur, nxt)
			if not moved:
				break

			cur = nxt

		print("[ATTACK] ", str(attacker.name), " PUSH target=", target_name, " to=", cur)
		return true

	# 2) NONE — атака без эффекта (заглушка под дебаффы)
	if a_stats.attack_effect == UnitStats.AttackEffect.NONE:
		print("[ATTACK] ", str(attacker.name), " attacks cell ", target_cell, " effect=NONE target=", target_name)
		return true

	# 3) DAMAGE
	var dmg: int = max(a_stats.damage, 0)
	var old_hp: int = t_stats.hp
	t_stats.apply_damage(dmg)

	if t_stats.hp != old_hp:
		unit_hp_changed.emit(target_unit, t_stats.hp, t_stats.max_hp)

	print("[ATTACK] ", str(attacker.name), " attacks cell ", target_cell,
		" target=", target_name, " dmg=", dmg, " target_hp=", t_stats.hp)

	if t_stats.hp <= 0:
		remove_unit(target_unit)

	return true

func _in_bounds(cell: Vector3i) -> bool:
	# Если у тебя есть board-ссылка — используй её.
	# Если board нет, временно считаем "в пределах" (но лучше подключить board).
	if has_node("../Board"):
		var b: Node = get_node("../Board")
		if b != null and b.has_method("is_in_bounds"):
			return bool(b.call("is_in_bounds", cell))
	return true

func remove_unit(unit: Node3D) -> void:
	if unit == null:
		return

	var st: UnitStats = get_stats(unit) as UnitStats
	if st != null:
		var cb: Callable = Callable(self, "_on_stats_hp_changed").bind(unit)
		if st.hp_changed.is_connected(cb):
			st.hp_changed.disconnect(cb)

	var cell: Vector3i = get_unit_cell(unit)

	if cell != INVALID_CELL:
		clear_cell(cell)

	_ap_left.erase(unit)
	_actions_used.erase(unit)
	if cell_entities != null:
		cell_entities.clear_entities_of_owner(unit)

	unit_removed.emit(unit, cell)

	if unit_status_manager != null:
		unit_status_manager.clear_all_for_unit(unit)

	unit.queue_free()

func _on_stats_hp_changed(hp: int, max_hp: int, unit: Node3D) -> void:
	unit_hp_changed.emit(unit, hp, max_hp)

func can_clean(unit: Node3D, from_cell: Vector3i, target_cell: Vector3i) -> bool:
	if unit == null:
		return false
	if not _in_bounds(target_cell):
		return false

	# только на своей клетке или соседней (манхэттен 1)
	var d: int = abs(target_cell.x - from_cell.x) + abs(target_cell.z - from_cell.z)
	if d > 1:
		return false

	# нельзя "чистить" клетку, занятую другим юнитом (кроме своей)
	var occ: Node3D = get_unit_at(target_cell)
	if occ != null and occ != unit:
		return false

	return can_spend_action(unit, UnitAction.CLEAN)

func clean_cell(unit: Node3D, from_cell: Vector3i, target_cell: Vector3i) -> bool:
	if not can_clean(unit, from_cell, target_cell):
		return false

	if not spend_action(unit, UnitAction.CLEAN):
		return false

	if cell_entities != null:
		cell_entities.clear_cleanable_at(target_cell)

	if target_cell == from_cell and is_rooted(unit):
		clear_root(unit)

	emit_signal("cell_cleaned", target_cell, unit)
	return true

func _reset_mp_for_all_units() -> void:
	_mp_left.clear()
	# occupied: Dictionary[Vector3i, Node3D] у тебя уже есть
	for k: Variant in occupied.keys():
		var u: Node3D = occupied[k] as Node3D
		var st: UnitStats = get_stats(u)
		if st == null:
			continue
		# ВАЖНО: тут предполагаю, что у статов поле move_range = MP за раунд.
		# Если у тебя другое имя (например mp / move_points) — замени только эту строку.
		var max_mp: int = int(st.move_range)
		_mp_left[u] = max_mp

func get_mp_left(unit: Node3D) -> int:
	return int(_mp_left.get(unit, 0))

func spend_mp(unit: Node3D, amount: int) -> void:
	var cur: int = get_mp_left(unit)
	var nxt: int = cur - amount
	if nxt < 0:
		nxt = 0
	_mp_left[unit] = nxt

func can_enter_cell(unit: Node3D, from_cell: Vector3i, to_cell: Vector3i) -> bool:
	if not _in_bounds(to_cell):
		return false

	var other: Node3D = get_unit_at(to_cell)
	if other != null and other != unit:
		return false

	if cell_entities != null and cell_entities.has_enter_blocker_at(to_cell):
		return false

	return true

# Стоимость шага (from->to). Здесь же профили движения (герой/враг).
func get_move_step_cost(unit: Node3D, from_cell: Vector3i, to_cell: Vector3i) -> int:
	var base_cost: int = 1

	# Пример: дебаф "rooted" полностью запрещает движение
	if is_rooted(unit):
		return 0

	# TODO: сюда подключишь лес/болото:
	# base_cost += get_terrain_extra_cost(to_cell)

	# Пример профиля: враги игнорируют часть стоимостей/дебафов
	var st: UnitStats = get_stats(unit)
	if st != null and st.faction == UnitStats.Faction.ENEMY:
		# например: игнор болота => оставляем base_cost=1
		pass

	return base_cost

func register_cell_reaction(cell: Vector3i, data: Dictionary) -> void:
	_cell_reactions[cell] = data

func clear_cell_reaction(cell: Vector3i) -> void:
	if _cell_reactions.has(cell):
		_cell_reactions.erase(cell)

# Вернёт true если надо остановить движение
func resolve_on_enter_cell(unit: Node3D, from_cell: Vector3i, to_cell: Vector3i) -> bool:
	if cell_entities != null:
		if cell_entities.get_stop_on_enter_at(to_cell, unit, self):
			return true

	if _cell_reactions.has(to_cell):
		var rx: Dictionary = _cell_reactions[to_cell] as Dictionary
		if rx.has("damage"):
			var rdmg: int = int(rx["damage"])
			apply_damage_to_unit(unit, rdmg)

		if rx.has("stop"):
			return bool(rx["stop"])
		return true

	return false

func apply_damage_to_unit(unit: Node3D, dmg: int) -> void:
	var st: UnitStats = get_stats(unit)
	if st == null:
		return
	st.apply_damage(dmg)
	# если у тебя remove_unit делается по сигналу hp_changed — ок
	# иначе тут можно проверить st.is_dead() и вызвать remove_unit(unit)
