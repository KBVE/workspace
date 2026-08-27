shader_type spatial;

// An inverted hull: the shape is drawn a second time, slightly fatter, with the front
// faces thrown away so only the sliver standing proud of the real mesh survives. It is
// the outline that works on the compatibility renderer, which has no screen space pass
// to find edges with, and this game ships to the web on gl_compatibility.
// Depth testing stays ON. The hull only reads as an outline because the real mesh is
// drawn over the top of it and hides everything but the sliver standing proud: turn the
// test off and the whole back face shows through, which is a filled-in door, not an
// outlined one. The seat box wants the opposite and uses its own material to get it.
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled;

uniform vec4 edge_colour : source_color = vec4(1.0, 0.86, 0.55, 1.0);

// Metres at one metre away. Scaled by view distance below so a seat down the carriage
// keeps the same weight of line as the one being stood next to; an outline in fixed
// world units thins to nothing across a room.
uniform float edge_metres : hint_range(0.002, 0.08) = 0.012;

void vertex() {
	vec4 in_view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float away = max(-in_view.z, 0.05);
	vec3 pushed = VERTEX + normalize(NORMAL) * edge_metres * away;
	VERTEX = pushed;
}

void fragment() {
	ALBEDO = edge_colour.rgb;
	ALPHA = edge_colour.a;
}
