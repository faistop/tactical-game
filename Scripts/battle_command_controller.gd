extends Node3D
class_name BattleCommandController

enum Phase { PLACEMENT, ENEMY_PLAN, PLAYER_TURN, ENEMY_EXECUTE, READY_TO_START, }
enum ActionMode { NONE, MOVE, ATTACK, CLEAN }

signal enemy_clicked(unit: Node3D, stats: UnitStats)
var action_mode: ActionMode = ActionMode.NONE

@export var enemy_abilities: Array[EnemyAbility] = []

@export var btn_move_path: NodePath
@export var btn_attack_path: NodePath
@export var btn_clean_path: NodePath

@export var ability_manager_path: NodePath
@export var battle_state_path: NodePath
@export var input_controller_path: NodePath
@export var unit_spawner_path: NodePath
@export var highlight_path: NodePath

@onready var units_root: Node = get_node_or_null("../../Units")
@onready var highlight: HighlightManager = get_node(highlight_path) as HighlightManager
@onready var battle_state: BattleState = get_node(battle_state_path) as BattleState
@onready var input_controller: Node = get_node(input_controller_path)
@onready var spawner: UnitSpawner = get_node(unit_spawner_path) as UnitSpawner
@export var pathfinder_path: NodePath
@export var resolver_path: NodePath

var _ability_manager: AbilityManager = null
var _ai_prev_map: Dictionary = {} # Node3D -> Dictionary (Vector3i -> Vector3i)
var _pathfinder: Pathfinder = null
var _resolver: MovementResolver = null

var _move_prev_map: Dictionary = {}
var _move_cost_map: Dictionary = {}
var _move_reachable: Array[Vector3i] = []
var _planned_damage: Dictionary = {} # key: Node3D (player unit), value: int
var _did_attack: Dictionary = {} # Node3D -> bool

var _ability_by_tag: Dictionary = {} # UnitStats.UnitTag -> EnemyAbility

var _btn_move: Button
var _btn_attack: Button
var _btn_clean: Button

var _enemy_intents: Dictionary = {} # Node3D -> Dictionary (target cell)
var phase: Phase = Phase.PLACEMENT

var _round_index: int = 1
var _battle_started: bool = false

var selected_unit: Node3D = null
var selected_cell: Vector3i = Vector3i(999999, 999999, 999999)

func _start_round(n: int) -> void:
	_did_attack.clear()
	action_mode = ActionMode.MOVE
	_round_index = n
	_battle_started = true
	battle_state.begin_round()

	if _ability_manager != null:
		_ability_manager.on_round_start()

	await _enemy_plan_phase()

func _end_round() -> void:
	if not _battle_started:
		return
	if phase != Phase.PLAYER_TURN:
		return

	if _ability_manager != null:
		_ability_manager.on_round_end()

	# ход врагов (последовательно + задержка)
	await _enemy_execute_phase()

	# новый раунд
	_start_round(_round_index + 1)

	# возвращаем игрока
	phase = Phase.PLAYER_TURN
	selected_unit = null
	if highlight:
		highlight.clear_temp()

	print("Round:", _round_index)

func _ready() -> void:
	set_process_unhandled_input(true)
	phase = Phase.PLACEMENT
	selected_unit = null

	# клики по клеткам
	if input_controller.has_signal("cell_clicked"):
		input_controller.connect("cell_clicked", Callable(self, "_on_cell_clicked"))
	else:
		push_warning("BattleCommandController: input_controller has no signal 'cell_clicked'.")

	# конец расстановки героев
	if spawner.has_signal("placement_finished"):
		spawner.connect("placement_finished", Callable(self, "_on_placement_finished"))
	else:
		push_warning("BattleCommandController: spawner has no signal 'placement_finished'.")

	if battle_state != null and not battle_state.is_connected("unit_removed", Callable(self, "_on_unit_removed")):
		battle_state.connect("unit_removed", Callable(self, "_on_unit_removed"))

	if btn_move_path != NodePath():
		_btn_move = get_node(btn_move_path) as Button
	if btn_attack_path != NodePath():
		_btn_attack = get_node(btn_attack_path) as Button
	if btn_clean_path != NodePath():
		_btn_clean = get_node(btn_clean_path) as Button

	if _btn_move != null:
		_btn_move.pressed.connect(_on_btn_move_pressed)
	if _btn_attack != null:
		_btn_attack.pressed.connect(_on_btn_attack_pressed)
	if _btn_clean != null:
		_btn_clean.pressed.connect(_on_btn_clean_pressed)

	if pathfinder_path != NodePath():
		_pathfinder = get_node(pathfinder_path) as Pathfinder
	if resolver_path != NodePath():
		_resolver = get_node(resolver_path) as MovementResolver

	if _pathfinder != null and battle_state != null:
		_pathfinder.setup(battle_state)
	if _resolver != null and battle_state != null:
		_resolver.setup(battle_state, _ability_manager)

	if ability_manager_path != NodePath():
		_ability_manager = get_node(ability_manager_path) as AbilityManager
	if _ability_manager != null and battle_state != null:
		_ability_manager.setup(battle_state, units_root)

	_ability_by_tag.clear()
	for a: EnemyAbility in enemy_abilities:
		if a == null:
			continue
		_ability_by_tag[a.tag] = a

func _get_ability_for_enemy(st: UnitStats) -> EnemyAbility:
	if st == null:
		return null
	for t: UnitStats.UnitTag in st.tags:
		if _ability_by_tag.has(t):
			return _ability_by_tag[t] as EnemyAbility
	return null

func _on_btn_move_pressed() -> void:
	if selected_unit == null:
		return
	action_mode = ActionMode.MOVE
	_refresh_selected_highlight()

func _on_btn_attack_pressed() -> void:
	if selected_unit == null:
		return
	action_mode = ActionMode.ATTACK
	_refresh_selected_highlight()

func _on_btn_clean_pressed() -> void:
	if selected_unit == null:
		return
	action_mode = ActionMode.CLEAN
	_refresh_selected_highlight()

func _unit_did_attack(unit: Node3D) -> bool:
	return _did_attack.has(unit) and bool(_did_attack[unit])

func _refresh_selected_highlight() -> void:
	if highlight == null:
		return
	highlight.clear_temp()

	if selected_unit == null:
		return

	if not battle_state.is_unit_ready(selected_unit):
		return

	if action_mode == ActionMode.NONE:
		# ничего не показываем
		return

	var s: UnitStats = battle_state.get_stats(selected_unit)
	if s == null:
		return

	if action_mode == ActionMode.CLEAN:
		if highlight != null:
			highlight.clear_temp()

		var clean_cells: Array[Vector3i] = []
		var candidates: Array[Vector3i] = [
			selected_cell,
			selected_cell + Vector3i(1, 0, 0),
			selected_cell + Vector3i(-1, 0, 0),
			selected_cell + Vector3i(0, 0, 1),
			selected_cell + Vector3i(0, 0, -1),
		]

		for c: Vector3i in candidates:
			if battle_state.can_clean(selected_unit, selected_cell, c):
				clean_cells.append(c)

		# Используй тот режим подсветки, который у тебя точно есть.
		# Если у тебя есть YELLOW — удобно для "утилити".
		highlight.show_cells(clean_cells, HighlightManager.Mode.YELLOW)
		return

	# MOVE mode
	if action_mode == ActionMode.MOVE:

		_move_prev_map.clear()
		_move_cost_map.clear()
		_move_reachable.clear()

		if _pathfinder == null or battle_state == null or selected_unit == null:
			return

		var start_cell: Vector3i = battle_state.get_unit_cell(selected_unit)
		var mp_left: int = battle_state.get_mp_left(selected_unit)

		var res: Dictionary = _pathfinder.compute_reachability(selected_unit, start_cell, mp_left)
		_move_cost_map = res["cost_map"] as Dictionary
		_move_prev_map = res["prev_map"] as Dictionary
		_move_reachable = res["reachable"] as Array[Vector3i]

		if highlight != null:
			highlight.show_cells(_move_reachable, HighlightManager.Mode.GREEN)
			return

	# ATTACK mode
	if _unit_did_attack(selected_unit):
		return

	var r: int = max(s.shoot_range, 0)
	var cells: Array[Vector3i] = []
	for dx: int in range(-r, r + 1):
		for dz: int in range(-r, r + 1):
			if abs(dx) + abs(dz) > r:
				continue
			if dx == 0 and dz == 0:
				continue
			var c: Vector3i = Vector3i(selected_cell.x + dx, selected_cell.y, selected_cell.z + dz)
			cells.append(c)

	highlight.show_cells(cells, HighlightManager.Mode.RED)

func _get_enemy_units_sorted() -> Array[Node3D]:
	var list: Array[Node3D] = []

	# ===== ВАРИАНТ B: берём детей из Units-root =====
	if units_root != null:
		for child in units_root.get_children():
			var u := child as Node3D
			if u == null:
				continue
			var st := battle_state.get_stats(u)
			if st != null and st.faction == UnitStats.Faction.ENEMY:
				list.append(u)

	# сортируем по клетке: z, потом x (стабильно и детерминировано)
	list.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var ca: Vector3i = battle_state.get_unit_cell(a)
		var cb: Vector3i = battle_state.get_unit_cell(b)
		if ca.z == cb.z:
			return ca.x < cb.x
		return ca.z < cb.z
	)

	return list

func _ai_pick_attack_cell(enemy: Node3D, origin_cell: Vector3i) -> Vector3i:
	var st: UnitStats = battle_state.get_stats(enemy) as UnitStats
	if st == null:
		return BattleState.INVALID_CELL

	var target: Node3D = _ai_pick_target(enemy, origin_cell)
	if target == null:
		return BattleState.INVALID_CELL

	var t_cell: Vector3i = battle_state.get_unit_cell(target)

	if battle_state.can_attack(enemy, origin_cell, t_cell):
		return t_cell

	return BattleState.INVALID_CELL

func _ai_pick_target(_enemy: Node3D, origin_cell: Vector3i) -> Node3D:
	var best_any: Node3D = null
	var best_any_d: int = 999999

	var best_not_covered: Node3D = null
	var best_not_covered_d: int = 999999

	if units_root == null:
		return null

	for u_any: Node in units_root.get_children():
		var u: Node3D = u_any as Node3D
		if u == null:
			continue

		var st: UnitStats = battle_state.get_stats(u) as UnitStats
		if st == null:
			continue
		if st.faction != UnitStats.Faction.PLAYER:
			continue

		var c: Vector3i = battle_state.get_unit_cell(u)
		var d: int = abs(c.x - origin_cell.x) + abs(c.z - origin_cell.z)

		# fallback: ближайший вообще
		if d < best_any_d:
			best_any_d = d
			best_any = u

		# предпочтение: ближайший, который ещё НЕ гарантированно убит по плану
		var hp: int = st.hp
		var planned_v: Variant = _planned_damage.get(u, 0)
		var planned: int = int(planned_v) if typeof(planned_v) == TYPE_INT else 0

		# ТОЛЬКО проверка "уже хватает ли запланированного урона, чтобы убить"
		if planned < hp:
			if d < best_not_covered_d:
				best_not_covered_d = d
				best_not_covered = u

	return best_not_covered if best_not_covered != null else best_any

func _ai_pick_move_cell(enemy: Node3D) -> Vector3i:
	var st: UnitStats = battle_state.get_stats(enemy) as UnitStats
	if st == null:
		return BattleState.INVALID_CELL

	if _pathfinder == null or battle_state == null:
		return BattleState.INVALID_CELL

	var from: Vector3i = battle_state.get_unit_cell(enemy)
	if from == BattleState.INVALID_CELL:
		return BattleState.INVALID_CELL

	var target: Node3D = _ai_pick_target(enemy, from)
	if target == null:
		return BattleState.INVALID_CELL
	var t_cell: Vector3i = battle_state.get_unit_cell(target)

	# MP бюджет врага (берём из BattleState, он сбрасывается в begin_round)
	var mp_budget: int = battle_state.get_mp_left(enemy)
	if mp_budget <= 0:
		return BattleState.INVALID_CELL

	var res: Dictionary = _pathfinder.compute_reachability(enemy, from, mp_budget)
	var prev_map: Dictionary = res["prev_map"] as Dictionary
	var reachable: Array[Vector3i] = res["reachable"] as Array[Vector3i]

	# кешируем prev_map, чтобы потом построить путь для execute
	_ai_prev_map[enemy] = prev_map

	if reachable.is_empty():
		return BattleState.INVALID_CELL

	# reachable уже не включает занятые клетки (can_enter_cell отфильтровал),
	# но стартовая клетка (from) там есть.
	var candidates: Array[Vector3i] = reachable

	match st.ai_role:
		UnitStats.AIRole.MELEE:
			return _ai_best_cell_melee(candidates, t_cell)
		UnitStats.AIRole.RANGED:
			return _ai_best_cell_ranged(candidates, t_cell, st.shoot_min_range, st.shoot_range)
		_:
			return BattleState.INVALID_CELL

func _ai_best_cell_melee(candidates: Array[Vector3i], target_cell: Vector3i) -> Vector3i:
	var best: Vector3i = BattleState.INVALID_CELL
	var best_score: int = 999999

	for c in candidates:
		var d: int = abs(c.x - target_cell.x) + abs(c.z - target_cell.z)

		# score: чем ближе к 1, тем лучше; 1 — идеал.
		var score: int = abs(d - 1)

		# тайбрейк: если score одинаковый — выбираем реально ближе (меньше d)
		score = score * 100 + d

		if score < best_score:
			best_score = score
			best = c

	return best

func _ai_best_cell_ranged(candidates: Array[Vector3i],target_cell: Vector3i,min_r: int,max_r: int) -> Vector3i:
	var best := BattleState.INVALID_CELL
	var best_score := 999999

	# желаемая дистанция: под ITB-like “держать подальше”
	var ideal_min: int = maxi(min_r, 3)
	var ideal_max: int = max_r

	for c in candidates:
		var d: int = abs(c.x - target_cell.x) + abs(c.z - target_cell.z)

		var score := 0

		# 1) огромный штраф, если вне дальности выстрела
		if d > ideal_max:
			score += (d - max_r) * 1000
		# 2) штраф, если слишком близко (меньше min)
		if d < min_r:
			score += (min_r - d) * 1000

		# 3) внутри допустимого диапазона: предпочесть “идеальный” [ideal_min..ideal_max]
		if d < ideal_min:
			score += (ideal_min - d) * 10
		# если d внутри [ideal_min..ideal_max] — почти идеально, маленький тайбрейк
		score += d

		if score < best_score:
			best_score = score
			best = c

	return best

func _ai_get_attack_damage(attacker: Node3D) -> int:
	var st: UnitStats = battle_state.get_stats(attacker) as UnitStats
	if st == null:
		return 0
	return max(st.damage, 0)


func _ai_register_planned_damage_for_attack_cell(attacker: Node3D, attack_cell: Vector3i) -> void:
	var target_unit: Node3D = battle_state.get_unit_at(attack_cell)
	if target_unit == null:
		return

	var target_stats: UnitStats = battle_state.get_stats(target_unit) as UnitStats
	if target_stats == null:
		return
	if target_stats.faction != UnitStats.Faction.PLAYER:
		return

	var dmg: int = _ai_get_attack_damage(attacker)
	if dmg <= 0:
		return

	var old_v: Variant = _planned_damage.get(target_unit, 0)
	var old_value: int = int(old_v) if typeof(old_v) == TYPE_INT else 0
	_planned_damage[target_unit] = old_value + dmg

func _ai_get_unit_hp(unit: Node3D) -> int:
	var st: UnitStats = battle_state.get_stats(unit) as UnitStats
	if st == null:
		return 0
	return st.hp

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event

		# SPACE: старт раунда после расстановки ИЛИ конец хода игрока
		if k.keycode == KEY_SPACE:
			if phase == Phase.READY_TO_START:
				_start_round(1)
				return
			if phase == Phase.PLAYER_TURN:
				_end_round()
				return
			return

		# 1: переключение режима MOVE/ATTACK (только когда выбран юнит игрока)
		if k.keycode == KEY_1:
			if phase != Phase.PLAYER_TURN:
				return
			if selected_unit == null:
				return
			if not battle_state.is_unit_ready(selected_unit):
				return

			if action_mode == ActionMode.MOVE:
				action_mode = ActionMode.ATTACK
				print("Mode: ATTACK")
			else:
				action_mode = ActionMode.MOVE
				print("Mode: MOVE")

			_refresh_selected_highlight()
			return

		# ВАЖНО: больше НИЧЕГО не делаем на другие клавиши
		return

func _on_placement_finished() -> void:
	phase = Phase.READY_TO_START
	selected_unit = null
	if highlight != null:
		highlight.clear() # тут ок: после placement можно очистить всё
	print("Placement finished. Press SPACE to start the round.")

func _on_cell_clicked(cell: Vector3i) -> void:
	if phase != Phase.PLAYER_TURN:
		return

	var unit_on_cell: Node3D = battle_state.get_unit_at(cell)

	# 1) клик по своему юниту — выбираем, режим MOVE по умолчанию
	if unit_on_cell != null:
		var st: UnitStats = battle_state.get_stats(unit_on_cell)
		if st != null:
			# 1a) клик по врагу
			if st.faction == UnitStats.Faction.ENEMY:
				# Если сейчас режим атаки и выбран наш юнит — НЕ показываем инфо,
				# даём коду ниже обработать атаку.
				if selected_unit != null and action_mode == ActionMode.ATTACK:
					pass
				else:
					emit_signal("enemy_clicked", unit_on_cell, st)
					return

			# 1b) клик по своему юниту — выбираем, режим MOVE по умолчанию
			if st.faction == UnitStats.Faction.PLAYER:
				selected_unit = unit_on_cell
				selected_cell = cell
				action_mode = ActionMode.NONE
				if highlight != null:
					highlight.clear_temp()
				print("Selected PLAYER unit at ", cell, " (mode NONE)")
				return

	# 2) если никто не выбран — всё
	if selected_unit == null:
		return

	# выбранный юнит должен быть READY (иначе нельзя ни мув, ни атака)
	if not battle_state.is_unit_ready(selected_unit):
		print("Нельзя: этот юнит уже SPENT.")
		return

	var from_cell: Vector3i = selected_cell
	var to_cell: Vector3i = cell

	# 3) ATTACK mode
	if action_mode == ActionMode.ATTACK:
		if _unit_did_attack(selected_unit):
			print("Атака уже потрачена на этом юните.")
			return

		# атакуем только если на клетке есть враг
		if unit_on_cell == null:
			print("Нет цели для атаки.")
			return

		var a_stats: UnitStats = battle_state.get_stats(selected_unit)
		var t_stats: UnitStats = battle_state.get_stats(unit_on_cell)
		if a_stats == null or t_stats == null:
			return
		if a_stats.faction == t_stats.faction:
			return

		var ok_attack: bool = battle_state.attack(selected_unit, from_cell, to_cell, false)
		if ok_attack:
			_did_attack[selected_unit] = true

			# если уже сделал и мув и атаку — завершаем юнита
			if battle_state.get_ap_left(selected_unit) <= 0:
				battle_state.set_unit_spent(selected_unit)
				if highlight != null:
					highlight.clear_temp()
				selected_unit = null
				return

			# иначе остаёмся выбранными, обновляем подсветку (можно переключиться на MOVE и походить)
			_refresh_selected_highlight()
		return

	# 3.5) CLEAN mode
	if action_mode == ActionMode.CLEAN:
		var ok_clean: bool = battle_state.clean_cell(selected_unit, from_cell, to_cell)
		if ok_clean:
			# Важно: если ты дальше будешь считать "юнит завершён", нужно учитывать CLEAN тоже.
			_refresh_selected_highlight()
		return

	# 4) MOVE mode
	if action_mode != ActionMode.MOVE:
		return

	# Новый мувмент: частичный MP + шаговые триггеры
	if _resolver == null or _pathfinder == null:
		push_warning("Move: resolver/pathfinder not set.")
		return

	# цель должна быть достижима по текущему mp_left
	if _move_cost_map.is_empty() or not _move_cost_map.has(to_cell):
		print("Cell not reachable by MP. to=", to_cell)
		return

	var start_cell: Vector3i = battle_state.get_unit_cell(selected_unit)
	var path: Array[Vector3i] = _pathfinder.build_path(_move_prev_map, start_cell, to_cell)
	if path.is_empty():
		print("No path.")
		return

	var moved: bool = _resolver.execute_path(selected_unit, path)
	if not moved:
		print("Move failed (no progress).")
		return

	# обновляем выбранную клетку после фактического движения
	selected_cell = battle_state.get_unit_cell(selected_unit)

	_refresh_selected_highlight()

func _enemy_plan_phase() -> void:
	phase = Phase.ENEMY_PLAN
	_enemy_intents.clear()
	_planned_damage.clear()

	# очищаем старую подсветку
	if highlight:
		highlight.clear()

	var enemies: Array[Node3D] = _get_enemy_units_sorted()

	for e: Node3D in enemies:
		var st: UnitStats = battle_state.get_stats(e) as UnitStats
		if st == null:
			continue

		# 1) ДВИЖЕНИЕ ВРАГА РЕАЛЬНО (до телеграфа и до хода игрока)
		var from_cell: Vector3i = battle_state.get_unit_cell(e)
		var to_cell: Vector3i = _ai_pick_move_cell(e)

		if to_cell != BattleState.INVALID_CELL and to_cell != from_cell:
			if _resolver == null or _pathfinder == null:
				push_warning("Enemy move: resolver/pathfinder not set.")
			else:
				var prev_map: Dictionary = {}
				if _ai_prev_map.has(e):
					prev_map = _ai_prev_map[e] as Dictionary

				var path: Array[Vector3i] = _pathfinder.build_path(prev_map, from_cell, to_cell)
				if not path.is_empty():
					_resolver.execute_path(e, path)

		# КРИТИЧНО: после движения берём РЕАЛЬНУЮ клетку (resolver мог остановить раньше)
		from_cell = battle_state.get_unit_cell(e)

		# В будущем: здесь будут триггеры "на вход" (мины/ловушки) и возможная смерть врага.

		# --- ability plan (например трапер) ---
		# --- ability plan (новая система: UnitStats.abilities) ---
		if _ability_manager != null:
			var ab_intent: Dictionary = _ability_manager.plan_enemy(self, e, from_cell)
			if not ab_intent.is_empty():
				_enemy_intents[e] = ab_intent
				await get_tree().create_timer(0.5).timeout
				continue

		# 2) Телеграф атаки из РЕАЛЬНОЙ позиции after-move
		var attack_cell: Vector3i = _ai_pick_attack_cell(e, from_cell)

		var plan_intent: Dictionary = {}

		if attack_cell != BattleState.INVALID_CELL:
			plan_intent[IntentKeys.INTENT_KIND] = IntentKeys.KIND_ATTACK
			plan_intent[IntentKeys.INTENT_CELLS] = [attack_cell]
			_ai_register_planned_damage_for_attack_cell(e, attack_cell)

		_enemy_intents[e] = plan_intent

		await get_tree().create_timer(0.5).timeout

	_show_enemy_intents()
	phase = Phase.PLAYER_TURN

func _show_enemy_intents() -> void:
	if highlight == null:
		return

	highlight.clear_sticky()

	var attack_cells: Array[Vector3i] = []
	var trap_cells: Array[Vector3i] = []

	for e_any: Variant in _enemy_intents.keys():
		var e: Node3D = e_any as Node3D
		if e == null:
			continue

		var v: Variant = _enemy_intents.get(e, null)
		if v == null or typeof(v) != TYPE_DICTIONARY:
			continue

		var intent: Dictionary = v

		var kind_v: Variant = intent.get(IntentKeys.INTENT_KIND, null)
		if kind_v == null or typeof(kind_v) != TYPE_STRING_NAME:
			continue
		var kind: StringName = kind_v as StringName

		var cells_v: Variant = intent.get(IntentKeys.INTENT_CELLS, null)
		if cells_v == null or typeof(cells_v) != TYPE_ARRAY:
			continue

		var arr: Array = cells_v
		if kind == IntentKeys.KIND_ATTACK:
			for c_any: Variant in arr:
				if typeof(c_any) == TYPE_VECTOR3I:
					attack_cells.append(c_any as Vector3i)
		elif kind == IntentKeys.KIND_TRAP:
			for c_any: Variant in arr:
				if typeof(c_any) == TYPE_VECTOR3I:
					trap_cells.append(c_any as Vector3i)

	# порядок не важен, мы добавляем sticky без очистки
	if not attack_cells.is_empty():
		highlight.add_sticky_cells(attack_cells, HighlightManager.Mode.RED)
	if not trap_cells.is_empty():
		highlight.add_sticky_cells(trap_cells, HighlightManager.Mode.YELLOW)

func _enemy_execute_phase() -> void:
	phase = Phase.ENEMY_EXECUTE

	var enemies: Array[Node3D] = _get_enemy_units_sorted()

	for e: Node3D in enemies:
		var v: Variant = _enemy_intents.get(e, null)
		if v == null or typeof(v) != TYPE_DICTIONARY:
			continue

		var intent: Dictionary = v

		# 0) ability execute (может полностью обработать intent)
		if _ability_manager != null:
			var handled: bool = _ability_manager.execute_enemy(self, e, intent)
			if handled:
				await get_tree().create_timer(0.5).timeout
				continue

		# 1) читаем kind
		var kind_v: Variant = intent.get(IntentKeys.INTENT_KIND, null)
		if kind_v == null or typeof(kind_v) != TYPE_STRING_NAME:
			await get_tree().create_timer(0.5).timeout
			continue
		var kind: StringName = kind_v as StringName

		# 2) ATTACK: берём первую клетку из cells
		if kind == IntentKeys.KIND_ATTACK:
			var cells_v: Variant = intent.get(IntentKeys.INTENT_CELLS, null)
			if cells_v == null or typeof(cells_v) != TYPE_ARRAY:
				await get_tree().create_timer(0.5).timeout
				continue

			var cells: Array = cells_v
			if cells.is_empty():
				await get_tree().create_timer(0.5).timeout
				continue

			var c0: Variant = cells[0]
			if typeof(c0) != TYPE_VECTOR3I:
				await get_tree().create_timer(0.5).timeout
				continue

			var attack_cell: Vector3i = c0 as Vector3i
			if attack_cell == BattleState.INVALID_CELL:
				await get_tree().create_timer(0.5).timeout
				continue

			var from_cell: Vector3i = battle_state.get_unit_cell(e)

			# атакуем только если реально можем
			if battle_state.can_attack(e, from_cell, attack_cell):
				battle_state.attack(e, from_cell, attack_cell, true)

			await get_tree().create_timer(0.5).timeout
			continue

		# 3) TRAP и прочие виды: в execute BCC ничего не делает
		await get_tree().create_timer(0.5).timeout

	_enemy_intents.clear()
	if highlight:
		highlight.clear_sticky()

func _on_unit_removed(unit: Node3D, _cell: Vector3i) -> void:
	if unit == null:
		return

	# Если умер тот, кто телеграфировал — убираем его intent
	if _enemy_intents.has(unit):
		_enemy_intents.erase(unit)

		# Перерисовываем sticky на основе оставшихся намерений
		if highlight != null:
			highlight.clear_sticky()
		_show_enemy_intents()
