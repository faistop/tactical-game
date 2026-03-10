extends RefCounted
class_name TrapEntityFactory

static func create(cell: Vector3i, owner_unit: Node3D) -> CellEntity:
	var entity: CellEntity = CellEntity.new().setup(&"trap", cell, owner_unit)
	entity.duration_rounds = -1
	entity.blocks_spawn = false
	entity.blocks_enter = false
	entity.cleanable = true
	entity.trigger_on_enter = true
	entity.remove_after_trigger = false
	entity.data = {
		"apply_root": true,
		"stop": true
	}
	print("[TRAP CREATE] owner=", owner_unit.name, " cell=", cell)
	return entity
