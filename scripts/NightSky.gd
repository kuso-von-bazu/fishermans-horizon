extends Control
## NightSky — #209再2: ボスラッシュ制覇画面の背景。
## 三日月と満点の星空を手続き的に描く(画像アセット不要・解像度に追従)。
## 星の配置は種を固定した乱数なので、何度見ても同じ夜空になる。

const STAR_COUNT := 260
const MILKYWAY_COUNT := 420   # 天の川ぶんの微光星
const SEED := 20260811

var _stars: Array = []   # {pos(0..1の相対座標), r, alpha, twinkle}
var _t: float = 0.0

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in STAR_COUNT:
		# 上空ほど星が多くなるよう、yは二乗で上に寄せる
		var y := pow(rng.randf(), 1.7)
		var big := rng.randf() < 0.09
		_stars.append({
			"p": Vector2(rng.randf(), y * 0.86),
			"r": rng.randf_range(2.2, 3.6) if big else rng.randf_range(0.9, 1.9),
			"a": rng.randf_range(0.45, 1.0),
			"tw": rng.randf_range(0.5, 2.2),
			"ph": rng.randf() * TAU,
		})
	# 天の川: 左上から右下へ走る帯に沿って、ごく小さな星を密集させる
	for i in MILKYWAY_COUNT:
		var u := rng.randf()
		var spread := rng.randfn(0.0, 0.055)
		var bx := 0.04 + u * 0.92
		var by := 0.08 + u * 0.52 + spread
		if by < 0.0 or by > 0.88:
			continue
		_stars.append({
			"p": Vector2(bx, by),
			"r": rng.randf_range(0.6, 1.25),
			"a": rng.randf_range(0.16, 0.45),
			"tw": rng.randf_range(0.4, 1.6),
			"ph": rng.randf() * TAU,
		})
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var sz := size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return

	# 夜空のグラデーション(上=濃紺、下=水平線の淡い藍)
	var steps := 24
	for i in steps:
		var f := float(i) / float(steps)
		var col := Color(0.02, 0.03, 0.09).lerp(Color(0.06, 0.10, 0.20), f)
		draw_rect(Rect2(0.0, sz.y * f, sz.x, sz.y / float(steps) + 1.0), col)

	# 星(ゆっくり瞬く)
	for s in _stars:
		var p: Vector2 = Vector2(s.p.x * sz.x, s.p.y * sz.y)
		var tw: float = 0.72 + 0.28 * sin(_t * float(s.tw) + float(s.ph))
		var a: float = float(s.a) * tw
		var r: float = float(s.r)
		draw_circle(p, r, Color(1.0, 0.98, 0.92, a))
		if r > 2.0:
			# 大きい星は十字の光条を伸ばす
			var g := Color(1.0, 0.98, 0.92, a * 0.5)
			draw_line(p - Vector2(r * 2.6, 0), p + Vector2(r * 2.6, 0), g, 1.0)
			draw_line(p - Vector2(0, r * 2.6), p + Vector2(0, r * 2.6), g, 1.0)

	_draw_crescent(Vector2(sz.x * 0.80, sz.y * 0.20), minf(sz.x, sz.y) * 0.11)

# 三日月: 明るい円から、少しずらした背景色の円をくり抜いて描く
func _draw_crescent(c: Vector2, r: float) -> void:
	# 月あかりのにじみ(段数を多く・1枚あたりを薄くして輪郭が出ないようにする)
	var glow := 26
	for i in range(glow, 0, -1):
		var f := float(i) / float(glow)
		draw_circle(c, r * (1.0 + f * 2.4), Color(0.80, 0.87, 1.0, 0.016 * (1.0 - f) * (1.0 - f)))
	draw_circle(c, r, Color(0.98, 0.97, 0.88, 1.0))
	# 欠け際をなめらかに見せるため、背景と同じ色の円を重ねる
	draw_circle(c + Vector2(r * 0.42, -r * 0.30), r * 0.94, Color(0.032, 0.052, 0.125, 1.0))
