extends Resource
class_name CellEntity

var kind: StringName = &""
var cell: Vector3i = Vector3i.ZERO

var owner_unit: Node3D = null
var owner_id: int = 0

var duration_rounds: int = -1

var blocks_spawn: bool = false
var blocks_enter: bool = false
var cleanable: bool = true

var trigger_on_enter: bool = false
var remove_after_trigger: bool = false

var data: Dictionary = {}

func setup(new_kind: StringName, new_cell: Vector3i, new_owner_unit: Node3D) -> CellEntity:
	kind = new_kind
	cell = new_cell
	owner_unit = new_owner_unit
	owner_id = 0
	if new_owner_unit != null:
		owner_id = new_owner_unit.get_instance_id()
	return self
