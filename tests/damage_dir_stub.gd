extends Node2D
## テスト用: World2D.show_damage_direction の受け口だけを持つスタブ。

var received = null

func show_damage_direction(source_pos: Vector2) -> void:
	received = source_pos
