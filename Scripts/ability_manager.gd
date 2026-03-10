extends Node
class_name AbilityManager

var battle_state: BattleState = null
var units_root: Node = null

# Список способностей по владельцу
var _by_unit: Dictionary = {} # Node3D -> Array[Ability]

func setup(state: BattleState, units: Node) -> void:
	battle_state = state
	units_root = units

func rebuild_cache() -> void:
	_by_unit.clear()
	if units_root == null or battle_state == null:
		return

	for child_any: Node in units_root.get_children():
		var u: Node3D = child_any as Node3D
		if u == null:
			continue
		var st: UnitStats = battle_state.get_stats(u) as UnitStats
		if st == null:
			continue
		if st.abilities == null or st.abilities.is_empty():
			continue

		var arr: Array[Ability] = []
		for a: Ability in st.abilities:
			if a == null:
				continue
			# owner уже проставляется в Unit._ready(), но это безопасно
			a.setup(u)
			arr.append(a)

		if not arr.is_empty():
			_by_unit[u] = arr

func on_round_start() -> void:
	# каждый раунд можно пересобрать, чтобы учесть новых юнитов/призыв
	rebuild_cache()

	# глобальные события (можешь сделать позже)
	for u_any: Variant in _by_unit.keys():
		var u: Node3D = u_any as Node3D
		if u == null:
			continue
		var arr: Array[Ability] = _by_unit[u] as Array[Ability]
		for a: Ability in arr:
			a.on_round_start()

func on_round_end() -> void:
	for u_any: Variant in _by_unit.keys():
		var u: Node3D = u_any as Node3D
		if u == null:
			continue
		var arr: Array[Ability] = _by_unit[u] as Array[Ability]
		for a: Ability in arr:
			a.on_round_end()

func on_cell_enter(unit: Node3D, cell: Vector3i) -> void:
	if unit == null:
		return
	if not _by_unit.has(unit):
		return
	var arr: Array[Ability] = _by_unit[unit] as Array[Ability]
	for a: Ability in arr:
		a.on_cell_enter(unit, cell)

func on_unit_damaged(unit: Node3D, damage: int) -> void:
	if unit == null:
		return
	if not _by_unit.has(unit):
		return
	var arr: Array[Ability] = _by_unit[unit] as Array[Ability]
	for a: Ability in arr:
		a.on_unit_damaged(unit, damage)

func plan_enemy(controller, unit: Node3D, from_cell: Vector3i) -> Dictionary:
	if unit == null:
		return {}
	if not _by_unit.has(unit):
		return {}

	var arr: Array[Ability] = _by_unit[unit] as Array[Ability]
	for a: Ability in arr:
		var intent: Dictionary = a.plan(controller, unit, from_cell)
		if intent != null and not intent.is_empty():
			return intent
	return {}

func execute_enemy(controller, unit: Node3D, intent: Dictionary) -> bool:
	if unit == null:
		return false
	if not _by_unit.has(unit):
		return false

	var arr: Array[Ability] = _by_unit[unit] as Array[Ability]
	for a: Ability in arr:
		var handled: bool = a.execute(controller, unit, intent)
		if handled:
			return true
	return false
