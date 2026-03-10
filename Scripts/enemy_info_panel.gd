extends PanelContainer
class_name EnemyInfoPanel

@export var battle_command_controller_path: NodePath
@export var name_label_path: NodePath
@export var tags_label_path: NodePath

var _name_label: Label
var _tags_label: Label

func _ready() -> void:
	visible = false

	# 1) лейблы
	if name_label_path != NodePath():
		_name_label = get_node_or_null(name_label_path) as Label
	if tags_label_path != NodePath():
		_tags_label = get_node_or_null(tags_label_path) as Label

	if _name_label == null:
		push_warning("EnemyInfoPanel: name_label not found. Set name_label_path in inspector.")
	if _tags_label == null:
		push_warning("EnemyInfoPanel: tags_label not found. Set tags_label_path in inspector.")

	# 2) контроллер
	if battle_command_controller_path == NodePath():
		push_warning("EnemyInfoPanel: battle_command_controller_path is empty.")
		return

	var bcc: Node = get_node_or_null(battle_command_controller_path)
	if bcc == null:
		push_warning("EnemyInfoPanel: BattleCommandController not found by path.")
		return

	if not bcc.is_connected("enemy_clicked", Callable(self, "_on_enemy_clicked")):
		bcc.connect("enemy_clicked", Callable(self, "_on_enemy_clicked"))

func _on_enemy_clicked(unit: Node3D, stats: UnitStats) -> void:
	visible = true

	if _name_label != null:
		var shown_name: String = stats.display_name
		if shown_name.is_empty():
			shown_name = String(unit.name)
		_name_label.text = "Враг: " + shown_name

	if _tags_label != null:
		_tags_label.text = "Теги: " + stats.get_tags_text_ru() + "\nАтака: " + _get_attack_type_text(stats)

func _get_attack_type_text(stats: UnitStats) -> String:
	# Подстрой под твои поля в UnitStats.
	# Если у тебя есть is_melee / is_ranged — отлично.
	# Если нет — временно верни "—".
	if "is_melee" in stats and bool(stats.get("is_melee")):
		return "Melee"
	if "is_ranged" in stats and bool(stats.get("is_ranged")):
		return "Ranged"
	return "—"
