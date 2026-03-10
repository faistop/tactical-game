extends Control
class_name UnitHoverHP

@export var camera_path: NodePath
@export var battle_state_path: NodePath
@export var input_controller_path: NodePath

@export var screen_offset_px: Vector2 = Vector2(0.0, -18.0)

@export var hp_bar_scene: PackedScene

@onready var _camera: Camera3D = get_node_or_null(camera_path) as Camera3D
@onready var _battle_state: BattleState = get_node_or_null(battle_state_path) as BattleState
@onready var _input: BattleInputController = get_node_or_null(input_controller_path) as BattleInputController

var _hovered_unit: Node3D = null
var _hovered_stats: UnitStats = null
var _bar: UnitHpBar = null

var _bar_size: Vector2 = Vector2(0.0, 0.0)
var _size_refreshing: bool = false

func _ready() -> void:
	visible = false

	if hp_bar_scene != null:
		_bar = hp_bar_scene.instantiate() as UnitHpBar
		add_child(_bar)
		_bar.position = Vector2(0.0, 0.0)

func _exit_tree() -> void:
	_disconnect_stats_signal()

func _connect_stats_signal(stats: UnitStats) -> void:
	if stats == null:
		return
	if not stats.is_connected("hp_changed", Callable(self, "_on_hp_changed")):
		stats.connect("hp_changed", Callable(self, "_on_hp_changed"))

func _disconnect_stats_signal() -> void:
	if _hovered_stats == null:
		return
	if _hovered_stats.is_connected("hp_changed", Callable(self, "_on_hp_changed")):
		_hovered_stats.disconnect("hp_changed", Callable(self, "_on_hp_changed"))
	_hovered_stats = null

func _on_hp_changed(hp: int, max_hp: int) -> void:
	if _bar == null:
		return
	if _hovered_unit == null:
		return
	if not visible:
		return

	_bar.set_values(hp, max_hp)
	call_deferred("_refresh_size_next_frame")

func _refresh_size_next_frame() -> void:
	if _bar == null:
		return
	if _size_refreshing:
		return

	_size_refreshing = true
	await get_tree().process_frame

	# После layout размеры уже корректные
	var s: Vector2 = _bar.get_combined_minimum_size()
	if s.x <= 0.0 or s.y <= 0.0:
		s = _bar.size

	_bar_size = s
	size = s # важно: размер родителя = размер бара для стабильного центрирования
	_size_refreshing = false

func _process(_delta: float) -> void:
	if _camera == null or _battle_state == null or _input == null:
		_hovered_unit = null
		_disconnect_stats_signal()
		visible = false
		return

	var cell: Vector3i = _input.get_cell_under_mouse()
	if cell == BattleState.INVALID_CELL:
		_hovered_unit = null
		_disconnect_stats_signal()
		visible = false
		return

	var unit: Node3D = _battle_state.get_unit_at(cell)
	if unit == null:
		_hovered_unit = null
		_disconnect_stats_signal()
		visible = false
		return

	# Жёсткое правило: без HpAnchor HP не показываем
	var anchor: Node3D = unit.get_node_or_null("HpAnchor") as Node3D
	if anchor == null:
		_hovered_unit = null
		_disconnect_stats_signal()
		visible = false
		return

	# Новый юнит — обновляем HP и подписки
	if unit != _hovered_unit:
		_hovered_unit = unit
		_update_hp_from_unit(unit)
		call_deferred("_refresh_size_next_frame")

	_update_screen_position_from_anchor(anchor)
	visible = true

func _update_hp_from_unit(unit: Node3D) -> void:
	if _bar == null:
		visible = false
		return

	var stats: UnitStats = (_battle_state as Object).call("get_stats", unit) as UnitStats
	if stats == null:
		visible = false
		return

	if stats != _hovered_stats:
		_disconnect_stats_signal()
		_hovered_stats = stats
		_connect_stats_signal(_hovered_stats)

	_bar.set_values(stats.hp, stats.max_hp)

func _update_screen_position_from_anchor(anchor: Node3D) -> void:
	var world_pos: Vector3 = anchor.global_transform.origin

	if _camera.is_position_behind(world_pos):
		visible = false
		return

	var screen_pos: Vector2 = _camera.unproject_position(world_pos)
	screen_pos += screen_offset_px

	var s: Vector2 = _bar_size
	if s.x <= 0.0 or s.y <= 0.0:
		s = size
		if s.x <= 0.0 or s.y <= 0.0:
			s = (_bar.get_combined_minimum_size() if _bar != null else Vector2(0.0, 0.0))

	position = screen_pos - (s * 0.5)
