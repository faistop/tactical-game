extends Node
class_name Pathfinder

const INF: int = 1_000_000_000

var battle_state: BattleState = null

func setup(state: BattleState) -> void:
	battle_state = state

# Возвращает:
# - cost_map: Dictionary[Vector3i, int]
# - prev_map: Dictionary[Vector3i, Vector3i]
# - reachable: Array[Vector3i]
func compute_reachability(unit: Node3D, start: Vector3i, mp_budget: int) -> Dictionary:
	var cost_map: Dictionary = {}
	var prev_map: Dictionary = {}
	var open: Array[Vector3i] = []

	cost_map[start] = 0
	open.append(start)

	while not open.is_empty():
		# Находим вершину с минимальной стоимостью (O(n), но поле 11x11 -> норм)
		var best_i: int = 0
		var best_c: int = INF
		for i: int in range(open.size()):
			var ccell: Vector3i = open[i]
			var ccost: int = int(cost_map.get(ccell, INF))
			if ccost < best_c:
				best_c = ccost
				best_i = i

		var cur: Vector3i = open[best_i]
		open.remove_at(best_i)

		var cur_cost: int = int(cost_map.get(cur, INF))
		if cur_cost > mp_budget:
			continue

		for nb: Vector3i in _neighbors4(cur):
			if battle_state == null:
				continue
			if not battle_state._in_bounds(nb):
				continue
			if not battle_state.can_enter_cell(unit, cur, nb):
				continue

			var step_cost: int = battle_state.get_move_step_cost(unit, cur, nb)
			if step_cost <= 0:
				continue

			var new_cost: int = cur_cost + step_cost
			if new_cost > mp_budget:
				continue

			var old_cost: int = int(cost_map.get(nb, INF))
			if new_cost < old_cost:
				cost_map[nb] = new_cost
				prev_map[nb] = cur
				if not open.has(nb):
					open.append(nb)

	var reachable: Array[Vector3i] = []
	for k: Variant in cost_map.keys():
		reachable.append(k as Vector3i)

	return {
		"cost_map": cost_map,
		"prev_map": prev_map,
		"reachable": reachable,
	}

func build_path(prev_map: Dictionary, start: Vector3i, goal: Vector3i) -> Array[Vector3i]:
	if start == goal:
		return [start]

	if not prev_map.has(goal):
		return []

	var path: Array[Vector3i] = []
	var cur: Vector3i = goal
	path.append(cur)

	var guard: int = 0
	while cur != start and guard < 512:
		guard += 1
		cur = prev_map[cur] as Vector3i
		path.append(cur)

	path.reverse()
	return path

func _neighbors4(c: Vector3i) -> Array[Vector3i]:
	return [
		Vector3i(c.x + 1, c.y, c.z),
		Vector3i(c.x - 1, c.y, c.z),
		Vector3i(c.x, c.y, c.z + 1),
		Vector3i(c.x, c.y, c.z - 1),
	]
