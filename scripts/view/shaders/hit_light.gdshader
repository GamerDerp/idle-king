shader_type canvas_item;
// Enemy hit flash (view, C2b): lightens the sprite toward `flash_color` by `strength` for 1-2 frames.
// Unlike assets/shaders/hit_flash.gdshader (solid silhouette, kept for towers) the sprite's own
// shading stays visible, so a crowd under fire never turns into flat white / orange blobs.
uniform vec4 flash_color : source_color = vec4(0.933, 0.949, 0.953, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(tex.rgb, flash_color.rgb, strength), tex.a);
}
