shader_type spatial;
render_mode unshaded, depth_draw_never, fog_disabled, shadows_disabled;

// Backdrop material for a track's SKY.PRM dome, applied by track_sky.gd.
//
// wipeout-rewrite's scene_draw() draws the dome first with depth writing off
// (render_set_depth_write(false)), so every other polygon paints over it however
// far away it is -- the ~180 m dome reads as an infinitely distant backdrop and
// not as a mesh sitting in the level. Godot offers no hook to force an opaque
// mesh to the front of the draw list, so the same result is reached
// order-independently: write no depth, and flatten the dome's clip-space depth
// onto the far plane so nothing in the scene can ever sort behind it.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// Godot 4 uses a reversed-Z depth buffer: NDC z is 1.0 at the near plane and
	// 0.0 at the far plane. Stop just short of 0.0 so the fragments still pass a
	// depth test against a buffer cleared to the far value.
	POSITION.z = POSITION.w * 1e-5;
}

void fragment() {
	// COLOR is the PRM's baked per-vertex shading: the glTF import carries it as
	// COLOR_0, and the imported StandardMaterial3D consumed it through
	// vertex_color_use_as_albedo.
	ALBEDO = texture(albedo_texture, UV).rgb * COLOR.rgb;
}
