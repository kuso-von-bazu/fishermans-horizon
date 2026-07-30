shader_type canvas_item;
// #190/#191/#192: 近海ごとの天候オーバーレイ(全画面ColonRect・HUDより下のCanvasLayer用)。
// tint=画面全体に被せる色(夜/曇天/ホワイトアウト)、rain=大雨、snow=吹雪。
// 降水は tint の上に「over合成」で重ねるため、アルファは自前で合成して返す。

uniform vec4 tint : source_color = vec4(0.0);
uniform float rain = 0.0;
uniform float snow = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float pa = 0.0;              // 降水そのものの不透明度
	vec3 pc = vec3(0.86, 0.92, 1.0);

	// #191: 大雨。斜めに流れる細い雨線を3層重ねて奥行きを出す
	if (rain > 0.001) {
		float acc = 0.0;
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			vec2 p = uv * vec2(120.0 + fi * 44.0, 30.0 + fi * 10.0);
			p += vec2(-1.0, 5.2) * TIME * (6.0 + fi * 2.2);
			vec2 c = floor(p);
			vec2 f = fract(p);
			float h = hash(c + fi * 17.3);
			// セルの一部だけを雨線にする。セル内では x を細く絞り、y 方向に尾を引かせて「線」にする
			float thin = smoothstep(0.14, 0.0, abs(f.x - 0.5));
			float tail = smoothstep(0.0, 0.75, f.y);
			acc = max(acc, step(0.955, h) * thin * tail * (0.55 + 0.45 * fi / 2.0));
		}
		pa = max(pa, acc * 0.60 * rain);
	}

	// #192: 吹雪。横殴りに流れる丸い雪片3層+白い靄
	if (snow > 0.001) {
		float acc = 0.0;
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float sc = 30.0 + fi * 20.0;
			vec2 p = uv * vec2(sc, sc * 0.6);
			p += vec2(-1.0, 0.38) * TIME * (3.2 + fi * 1.8);
			p.x += sin(TIME * (0.8 + fi * 0.35) + uv.y * 9.0) * 0.9;
			vec2 c = floor(p);
			vec2 f = fract(p);
			float h = hash(c + fi * 31.7);
			vec2 ctr = vec2(hash(c + 3.1), hash(c + 7.9));
			float dot_a = smoothstep(0.34, 0.0, distance(f, ctr)) * step(0.90, h);
			acc = max(acc, dot_a * (0.55 + 0.45 * fi / 2.0));
		}
		pa = max(pa, acc * 0.95 * snow);
		pa = max(pa, 0.14 * snow);   // ホワイトアウト気味の靄
	}

	// tint の上に降水を over 合成(結果を非プリマルチプライドへ戻す)
	float out_a = pa + tint.a * (1.0 - pa);
	vec3 out_c = (pc * pa + tint.rgb * tint.a * (1.0 - pa)) / max(out_a, 0.0001);
	COLOR = vec4(out_c, out_a);
}
