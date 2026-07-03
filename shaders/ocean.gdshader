shader_type spatial;
// Fisherman's Horizon の海面。頂点変位なしのフラグメント波(法線ゆらぎ)+波頭+フレネル。
// Compatibility(WebGL2)でも動く軽量シェーダ。

uniform vec3 shallow_color : source_color = vec3(0.20, 0.56, 0.70);
uniform vec3 deep_color : source_color = vec3(0.05, 0.20, 0.34);
uniform vec3 crest_color : source_color = vec3(0.78, 0.90, 0.96);
uniform float wave_scale = 0.12;
uniform float wave_speed = 0.7;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = world_pos.xz * wave_scale;
	float h = sin(p.x + t) * 0.5
			+ sin(p.y * 1.3 - t * 0.8) * 0.5
			+ sin((p.x + p.y) * 0.7 + t * 1.1) * 0.3
			+ sin((p.x * 1.7 - p.y * 0.9) - t * 1.4) * 0.2;
	float dx = cos(p.x + t) * 0.5
			+ cos((p.x + p.y) * 0.7 + t * 1.1) * 0.21
			+ cos((p.x * 1.7 - p.y * 0.9) - t * 1.4) * 0.34;
	float dz = cos(p.y * 1.3 - t * 0.8) * 0.65
			+ cos((p.x + p.y) * 0.7 + t * 1.1) * 0.21
			- cos((p.x * 1.7 - p.y * 0.9) - t * 1.4) * 0.18;
	vec3 nrm = normalize(vec3(-dx, 5.0, -dz));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	float fres = pow(clamp(1.0 - dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float crest = smoothstep(0.95, 1.45, h);
	vec3 col = mix(deep_color, shallow_color, clamp(h * 0.4 + 0.5, 0.0, 1.0));
	col = mix(col, crest_color, crest * 0.5 + fres * 0.35);
	ALBEDO = col;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
