extends Node2D
## テスト用: take_damage の呼び出しを記録するだけの僚艦役。
var hits: int = 0

func take_damage(amount: float) -> void:
	hits += 1
