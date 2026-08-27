shader_type spatial;
render_mode cull_back, unshaded;

// A prop wears the same light the walls around it were baked with, but as one colour
// for the whole mesh rather than a value per vertex.
//
// It has to be per instance and not per vertex, because the whole consist shares one
// crate mesh and one atlas between every crate in the train -- that sharing is what
// makes a furnished room cost transforms rather than geometry. Baking light into the
// mesh would give every crate the light of whichever one was baked. A tint is small
// enough to differ per placement while the mesh underneath stays the one mesh.
uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 baked_tint : source_color = vec3(1.0);

void fragment() {
	ALBEDO = texture(tex_albedo, UV).rgb * baked_tint;
}
