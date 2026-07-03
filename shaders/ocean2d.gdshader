shader_type canvas_item;
// 2D見下ろしの海面。カメラ位置(cam_pos)でワールド座標を復元し、
// 多重サイン波で深浅の色ムラ+波頭を描く。全画面ColorRect(背面レイヤー)用。

uniform vec2 cam_pos = vec2(0.0);
uniform vec3 shallow_color : source_color = vec3(0.22, 0.58, 0.72);
uniform vec3 deep_color : source_color = vec3(0.05, 0.24, 0.40);
uniform vec3 crest_color : source_color = vec3(0.80, 0.92, 0.97);
uniform float wave_scale = 0.028;
uniform float wave_speed = 0.9;

void fragment() {
	vec2 px = SCREEN_UV / SCREEN_PIXEL_SIZE;      // 画面ピクセル座標
	vec2 world = px + cam_pos;                     // ワールド座標(平行投影)
	vec2 p = world * wave_scale;
	float t = TIME * wave_speed;
	float h = sin(p.x * 1.0 + t) * 0.5
			+ sin(p.y * 1.35 - t * 0.8) * 0.5
			+ sin((p.x + p.y) * 0.7 + t * 1.15) * 0.35
			+ sin((p.x * 1.8 - p.y * 0.9) - t * 1.4) * 0.22;
	// 細かいさざ波(高周波・控えめ)
	float ripple = sin(p.x * 5.2 + p.y * 3.7 + t * 2.2) * sin(p.y * 4.6 - p.x * 2.9 - t * 1.7);
	vec3 col = mix(deep_color, shallow_color, clamp(h * 0.20 + 0.5 + ripple * 0.04, 0.0, 1.0));
	// 波頭(高い所にだけ細く)
	float crest = smoothstep(1.22, 1.5, h + ripple * 0.25);
	col = mix(col, crest_color, crest * 0.4);
	// うっすら大きなうねり(遠景の濃淡)
	float swell = sin(world.x * 0.0015 + t * 0.2) * sin(world.y * 0.0013 - t * 0.15);
	col *= 1.0 + swell * 0.05;
	COLOR = vec4(col, 1.0);
}
