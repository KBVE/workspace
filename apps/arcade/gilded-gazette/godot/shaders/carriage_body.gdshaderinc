// &credit -> GodotShaders for some examples and all the other KBVE shaders, damn I have too many.
// &why -> atlas gives 59 texels/m over 697 m2. no atlas size fixes that at web
//         budget, so add high-frequency detail that is independent of it.
// &trick -> UV density is uniform across the whole model, so UV * k lands at a
//           constant PHYSICAL frequency. no triplanar, no UV2, stays tangent space.

// &baked -> the carriage is lit in Blender and the light rides in COLOR, so this is
//           unshaded: no normal, no roughness, no metallic, and no lamp in the scene
//           touching a single one of these pixels. tools/bake_carriage_light.py is
//           what writes them, and six OmniLights a car is what it buys back.
uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_detail : filter_linear_mipmap_anisotropic, repeat_enable;

// What the whole carriage is multiplied by, so the evening can still move over a
// bake that cannot. White is the hour it was baked at.
uniform vec3 light_tint : source_color = vec3(1.0);

uniform float detail_tiling = 45.0;
uniform float detail_albedo : hint_range(0.0, 0.5) = 0.05;

// The bake is per vertex, so a bench is lit across its whole face by four corners.
// Leaning on it entirely flattens the room; this is how much of it to believe.
uniform float bake_strength : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec3 alb = texture(tex_albedo, UV).rgb;

	// the detail map is still worth its fetch unlit: the atlas gives 59 texels/m and
	// what it buys here is grain in the albedo rather than slope in a normal
	vec3 n_det = texture(tex_detail, UV * detail_tiling).xyz * 2.0 - 1.0;
	float grain = (n_det.x + n_det.y) * 0.5;

	vec3 baked = mix(vec3(1.0), COLOR.rgb, bake_strength);
	ALBEDO = alb * (1.0 + grain * detail_albedo) * baked * light_tint;
}
