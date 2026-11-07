shader_type canvas_item;
// Hit flash for sprites (enemies, towers). Pixel-exact: the silhouette is filled with ONE flat
// palette colour while `flash` > 0.5 — no blending, no glow, so the frame stays in-palette.
// Usage: material = ShaderMaterial(hit_flash.gdshader); tween `flash` 1 -> 0 over ~0.08 s
// (it is a step, so this shows exactly 1-2 frames of flat colour). See docs/ART.md.
uniform vec4 flash_color : source_color = vec4(0.933, 0.949, 0.953, 1.0); // steam_3 (#eef2f3)
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(tex.rgb, flash_color.rgb, step(0.5, flash)), tex.a);
}
