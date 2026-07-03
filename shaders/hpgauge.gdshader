shader_type spatial;
// 敵のHP円形ゲージ。カメラを向くビルボード板に放射状(時計回り)の残量アークを描く。
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;

uniform float fill = 1.0;   // 0..1 残HP割合

void vertex() {
	// ビルボード(常にカメラを向く)。位置はMODEL、姿勢はカメラ基底。
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float r = length(uv);
	float a = 0.0;
	vec3 col = vec3(0.08);
	if (r < 0.5 && r > 0.33) {
		float ang = atan(uv.x, -uv.y);       // 上=0, 時計回り
		if (ang < 0.0) ang += 6.2831853;
		float frac = ang / 6.2831853;
		if (frac <= fill) {
			col = mix(vec3(1.0, 0.2, 0.15), vec3(0.35, 1.0, 0.4), fill);  // 少ないほど赤
			a = 1.0;
		} else {
			col = vec3(0.06, 0.06, 0.08);
			a = 0.5;
		}
	}
	ALBEDO = col;
	ALPHA = a;
}
