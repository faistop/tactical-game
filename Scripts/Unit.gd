extends Node3D
class_name Unit

@export var stats: UnitStats

func _ready() -> void:
	if stats == null:
		stats = get_node_or_null("UnitStats") as UnitStats
	if stats == null:
		stats = get_node_or_null("unitstats") as UnitStats

	if stats == null:
		push_error("Unit has NO UnitStats node assigned/found: " + str(name))
		return

	stats.reset_runtime()

	# 3) abilities
	if stats.abilities != null:
		for a: Ability in stats.abilities:
			if a == null:
				continue
			a.setup(self)

func get_stats() -> UnitStats:
	return stats
