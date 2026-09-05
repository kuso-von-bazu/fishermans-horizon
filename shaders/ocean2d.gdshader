shader_type canvas_item;
// 2D見下ろしの海面。カメラ位置(cam_pos)でワールド座標を復元し、
// ドメインワーピングで自然な波+深浅+雲影+きらめきを描く。全画面ColorRect(背面レイヤー)用。

uniform vec2 cam_pos = vec2(0.0);
// #278(提案5): 演出ズーム中もワールド座標がずれないよう、カメラの倍率を受け取る
uniform float cam_zoom = 1.0;
uniform vec3 shallow_color : source_color = vec3(0.26, 0.62, 0.76);
uniform vec3 deep_color : source_color = vec3(0.04, 0.20, 0.36);
uniform vec3 crest_color : source_color = vec3(0.80, 0.92, 0.97);
uniform float wave_scale = 0.028;
uniform float wave_speed = 0.9;
// #135: 島の位置(ワールド座標)。島周りは淡い青にする
uniform vec2 islands[11];   // #239: 島8つ → #248/#251: 寄り道の島2つで10 → #290: 雪夜の島で11
uniform int island_count = 0;
uniform float island_light_radius = 900.0;
// #190/#191/#192: 近海の天候。night=夜(月下の島), rough=高波/荒波(嵐越え・果て)
uniform float night = 0.0;
// #239: 夜の演出を分解して島ごとに出し分ける。
//   moon  = 海面に映る月(月下=1 / 星霜・常闇=0)
//   stars = 海面に映る星々(星霜=1)
uniform float moon = 1.0;
uniform float stars = 0.0;
//   sunlight = 強い日射し(潮鳴り=1)。海面を明るくし、太陽の反射を落とす
uniform float sunlight = 0.0;
uniform float rough = 0.0;
// #278(提案1): 海のドット絵化。
//   px_size      … ワールド/画面座標を切り捨てる仮想ピクセルの大きさ(1.0で従来表示)
//   color_levels … 出力色の段階数(0で段階化しない)
// 波・きらめき・雲影・月/星の反射といった既存の演出はそのまま生きたまま、
// 質感だけがドット絵になる。
uniform float px_size = 3.0;
uniform float color_levels = 9.0;
// #278(提案7-1): 海岸の白波。島の浅瀬の縁(Island2D._coast と同じ式)に沿って白い帯を出す。
//   island_r    … 浅瀬の外縁の半径(ワールド単位。0以下でその島は白波なし)
//   island_wob  … 海岸線のゆらぎ(PALETTES.wob)
//   island_seed … ゆらぎの位相(Island2D の s1 と同じ値)
uniform float island_r[11];
uniform float island_wob[11];
uniform float island_seed[11];

// 2D擬似ノイズ
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 px = SCREEN_UV / SCREEN_PIXEL_SIZE;      // 画面ピクセル座標
	vec2 world = px / max(cam_zoom, 0.01) + cam_pos;   // ワールド座標(平行投影)
	// #278(提案1): 仮想ピクセルの格子へ載せてから波・ノイズを計算する。
	// 画面座標(quv)も同じ格子に載せ、月・太陽・星の反射までドット単位にする。
	float pxs = max(px_size, 1.0);
	world = floor(world / pxs) * pxs;
	vec2 quv = floor(px / pxs) * pxs * SCREEN_PIXEL_SIZE;
	vec2 p = world * wave_scale;
	float t = TIME * wave_speed;

	// #134: ドメインワーピングで一直線でなく波打つ模様にする
	vec2 warp = vec2(
		sin(p.y * 1.3 + t * 0.8) + noise(p * 0.7 + t * 0.05),
		sin(p.x * 1.1 - t * 0.7) + noise(p * 0.6 - t * 0.04));
	vec2 pw = p + warp * 0.6;
	float h = sin(pw.x * 1.0 + t) * 0.5
			+ sin(pw.y * 1.35 - t * 0.8) * 0.5
			+ sin((pw.x + pw.y) * 0.6 + t * 1.1) * 0.35
			+ sin((pw.x * 1.6 - pw.y * 0.8) - t * 1.3) * 0.22;
	float ripple = sin(pw.x * 5.2 + pw.y * 3.7 + t * 2.2) * sin(pw.y * 4.6 - pw.x * 2.9 - t * 1.7);
	// #191/#192: 荒天は大きなうねりを重ねて海面全体を波立たせる
	h += sin(pw.x * 0.45 + pw.y * 0.35 + t * 0.85) * rough * 0.55;

	// #135: 深浅。低周波ノイズで濃淡をつけ、島周りは必ず淡い青に寄せる
	float depth = noise(world * 0.00035 + 13.0);          // 0..1 (低=浅, 高=深)
	float shallow_amt = 1.0 - depth;
	for (int i = 0; i < island_count; i++) {
		float d = distance(world, islands[i]);
		shallow_amt = max(shallow_amt, 1.0 - smoothstep(0.0, island_light_radius, d));
	}
	shallow_amt = clamp(shallow_amt + h * 0.12 + ripple * 0.03, 0.0, 1.0);
	vec3 col = mix(deep_color, shallow_color, shallow_amt);

	// 波頭(高い所にだけ細く)
	float crest = smoothstep(1.15 - rough * 0.32, 1.45 - rough * 0.30, h + ripple * 0.25);
	col = mix(col, crest_color, crest * (0.35 + rough * 0.22));

	// 太陽のきらめき(波間に走る鋭い光点)
	float sparkle = sin(pw.x * 7.3 + t * 3.1) * sin(pw.y * 6.7 - t * 2.3) * sin((pw.x - pw.y) * 9.1 + t * 1.7);
	sparkle = pow(max(sparkle, 0.0), 12.0);
	col += vec3(1.0, 0.95, 0.8) * sparkle * 0.45 * (1.0 - night * 0.8);

	// #133: 流れる雲の影。多重ノクターブで大小さまざま、影のない所もつくる
	vec2 cw = world * 0.0006 + vec2(t * 0.02, t * 0.015);
	float cloud = noise(cw) * 0.6 + noise(cw * 2.3 + 5.0) * 0.3 + noise(cw * 5.1 + 9.0) * 0.1;
	float shadow = smoothstep(0.62, 0.82, cloud);   // 閾値以上だけ影(=影のない領域ができる)
	col *= 1.0 - shadow * (0.20 + rough * 0.28);   // #191/#192: 荒天は雲が厚く海面が暗い

	// 画面右上からの太陽光(暖色のグラデーション)
	float sun = max(0.0, 1.0 - length(quv - vec2(0.82, 0.12)) * 1.4);
	col += vec3(0.95, 0.85, 0.6) * sun * sun * 0.10 * (1.0 - night);

	// #250: 潮鳴りの島の近海は日射しが強い。海面全体を明るくし、
	// 右上の太陽から縦に伸びる反射(海面に砕けた光の道)を落とす。
	if (sunlight > 0.001) {
		col *= 1.0 + sunlight * 0.26;
		col += vec3(1.0, 0.95, 0.78) * sparkle * 0.95 * sunlight;   // 波間のきらめきも強める
		vec2 sun_uv = quv - vec2(0.70, 0.26);
		sun_uv.x += sin(quv.y * 88.0 + t * 2.0) * 0.008;
		float sun_disc = 1.0 - smoothstep(0.030, 0.044, length(vec2(sun_uv.x, sun_uv.y * 0.72)));
		float spath_w = 0.016 + quv.y * 0.070;
		float sun_path = exp(-pow(abs(quv.x - 0.70) / spath_w, 2.0));
		sun_path *= smoothstep(0.22, 0.32, quv.y) * (1.0 - smoothstep(0.32, 0.98, quv.y));
		float sbroken = pow(max(sin(quv.y * 190.0 + h * 3.2 + t * 2.1), 0.0), 5.0);
		col += vec3(1.0, 0.94, 0.74) * (sun_disc * 0.85 + sun_path * sbroken * 0.85) * sunlight;
	}

	// #190: 月下の島の近海は常に夜。全体を暗い藍へ沈め、左上からの月光を落とす
	col = mix(col, col * vec3(0.30, 0.36, 0.60) + vec3(0.015, 0.025, 0.055), night);
	float moon_glow = max(0.0, 1.0 - length(quv - vec2(0.18, 0.13)) * 1.5);
	col += vec3(0.62, 0.70, 0.95) * moon_glow * moon_glow * 0.16 * night * moon;

	// #190再3: 月下の海面に映る満月。波で輪郭が揺れる月影と、縦に伸びる細かな反射を重ねる。
	vec2 moon_uv = quv - vec2(0.18, 0.27);
	moon_uv.x += sin(quv.y * 92.0 + t * 2.2) * 0.006;
	float moon_disc = 1.0 - smoothstep(0.040, 0.052, length(vec2(moon_uv.x, moon_uv.y * 0.78)));
	float path_width = 0.018 + quv.y * 0.085;
	float moon_path = exp(-pow(abs(quv.x - 0.18) / path_width, 2.0));
	moon_path *= smoothstep(0.25, 0.34, quv.y) * (1.0 - smoothstep(0.34, 0.94, quv.y));
	float broken = pow(max(sin(quv.y * 185.0 + h * 2.8 + t * 1.7), 0.0), 7.0);
	float reflection = moon_disc * 0.80 + moon_path * broken * 0.42;
	col += vec3(0.72, 0.80, 1.0) * reflection * night * moon;   // #239: moon=0 の海域では月の反射を出さない

	// #239: 星霜の島の近海。海面いっぱいに星の反射がきらめく(月の道は出さない)
	if (stars > 0.001) {
		// 粒が四角く目立たないよう、細かい格子でセル内の中心からの距離で丸く落とす
		vec2 suv = quv * vec2(430.0, 260.0);
		vec2 sc = floor(suv);
		vec2 sf = fract(suv) - 0.5;
		float rnd = fract(sin(sc.x * 12.9898 + sc.y * 78.233) * 43758.5453);
		float dot_mask = 1.0 - smoothstep(0.10, 0.36, length(sf));
		// #239再4: 以前は pow(...,18) で大半の時間 0 になり、星が点いたり消えたり
		// していた。常に光らせたうえで、瞬きは明るさの揺らぎだけにする。
		float twinkle = 0.72 + 0.28 * sin(t * 1.6 + rnd * 24.0);
		float star = step(0.975, rnd) * twinkle * dot_mask;
		// 波で上下に揺らして「映り込み」らしく見せる
		float sway = 0.55 + 0.45 * sin(quv.y * 60.0 + h * 3.0 + t * 1.1);
		col += vec3(0.82, 0.90, 1.0) * star * sway * 0.95 * night * stars;
	}
	// #278(提案7-1): 海岸の白波。浅瀬の縁に沿って明滅する白いドットの縁取りを重ねる
	for (int i = 0; i < island_count; i++) {
		float r0 = island_r[i];
		if (r0 > 0.0) {
			vec2 dv = world - islands[i];
			float d = length(dv);
			if (d < r0 * 1.8) {
				float a = atan(dv.y, dv.x);
				float sd = island_seed[i];
				float wb = island_wob[i];
				float rr = r0 * (1.0 + wb * sin(3.0 * a + sd) + wb * 0.6 * sin(7.0 * a + sd * 2.3));
				float band = 1.0 - smoothstep(0.0, 20.0, abs(d - rr));
				float flick = 0.50 + 0.50 * sin(t * 2.0 + a * 4.0 + float(i));
				col = mix(col, crest_color, clamp(band * flick * 0.6, 0.0, 1.0));
			}
		}
	}

	// #278(提案1): 出力色の段階化。ここまでの計算を「ドット絵の色数」に丸める
	if (color_levels > 1.5) {
		col = floor(col * color_levels + 0.5) / color_levels;
	}
	COLOR = vec4(col, 1.0);
}
