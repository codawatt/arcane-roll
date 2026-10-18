shader_type canvas_item;

uniform vec4 background_color = vec4(0.118, 0.106, 0.180, 1.0);
uniform vec4 dot_color = vec4(0.227, 0.200, 0.345, 1.0);
uniform vec4 triangle_color = vec4(0.557, 0.486, 0.765, 1.0);
uniform vec2 rect_size = vec2(1080.0, 1920.0);

// Star grid settings.
// Keeping dot_* names for compatibility with background.gd.
uniform float dot_spacing = 200.0;
uniform float dot_radius = 40;
uniform vec2 dot_drift = vec2(16.0, -32.0);

// Star customization.
uniform float star_size_variation = 0.20; // +/- 20% size.
uniform float star_rotation_variation = 0.55; // +/- radians.

uniform float tooth_width = 230.0;
uniform float tooth_depth = 100.0;
uniform float glide_speed = 30.0;

uniform vec4 shadow_color = vec4(0.0, 0.0, 0.0, 0.35);
uniform vec2 shadow_offset = vec2(10.0, 14.0);
uniform float shadow_softness = 8.0;

uniform float band_reveal = 1.0;




// --------------------------------------------------
// Deterministic randomness per grid cell.
// --------------------------------------------------

float hash21(vec2 p) {
	return fract(
		sin(dot(p, vec2(127.1, 311.7))) * 43758.5453
	);
}


// --------------------------------------------------
// Anti-aliased star shape.
// Supports different point counts, inner radii,
// sizes, and rotations.
// --------------------------------------------------

float star_coverage(
	vec2 p,
	float radius,
	float inner_ratio,
	float points,
	float rotation
) {
	// Rotate individual star.
	float c = cos(rotation);
	float s = sin(rotation);

	p = vec2(
		p.x * c - p.y * s,
		p.x * s + p.y * c
	);

	// Fold angle into a single star arm.
	float sector = TAU / points;
	float angle = atan(p.y, p.x);

	float a = abs(
		mod(angle + sector * 0.5, sector)
		- sector * 0.5
	);

	// Outer point and inner valley.
	vec2 outer = vec2(radius, 0.0);

	float half_angle = PI / points;

	vec2 inner = radius * inner_ratio * vec2(
		cos(half_angle),
		sin(half_angle)
	);

	// Straight edges give the stars sharp tips.
	vec2 edge = inner - outer;

	vec2 q = length(p) * vec2(
		cos(a),
		sin(a)
	);

	// Signed distance to the star's edge.
	float d = -(
		edge.x * (q.y - outer.y)
		- edge.y * (q.x - outer.x)
	) / length(edge);

	// Smooth pixel edges.
	float aa = max(fwidth(d), 0.0001);

	return 1.0 - smoothstep(-aa, aa, d);
}


// --------------------------------------------------
// Six different magical star variants.
// --------------------------------------------------

float magical_star(vec2 local, vec2 cell_id) {
	// Each cell chooses one of six shapes.
	int variant = int(floor(
		hash21(cell_id + vec2(21.1, 9.2)) * 6.0
	));

	// Independent size and rotation.
	float size_random = hash21(
		cell_id + vec2(7.3, 13.7)
	);

	float rotation_random = hash21(
		cell_id + vec2(19.1, 3.7)
	);

	float radius = dot_radius * (
		1.0 + (size_random * 2.0 - 1.0)
		* star_size_variation
	);

	float rotation = (
		rotation_random * 2.0 - 1.0
	) * star_rotation_variation;

	float points = 5.0;
	float inner_ratio = 0.45;

	// 1: Four-point diamond star.
	if (variant == 0) {
		points = 4.0;
		inner_ratio = 0.38;
	}

	// 2: Classic five-point star.
	else if (variant == 1) {
		points = 5.0;
		inner_ratio = 0.48;
	}

	// 3: Six-point magical star.
	else if (variant == 2) {
		points = 6.0;
		inner_ratio = 0.52;
	}

	// 4: Seven-point arcane star.
	else if (variant == 3) {
		points = 7.0;
		inner_ratio = 0.48;
	}

	// 5: Eight-point radiant star.
	else if (variant == 4) {
		points = 8.0;
		inner_ratio = 0.52;
	}

	// 6: Thin four-point celestial star.
	else {
		points = 4.0;
		inner_ratio = 0.20;
	}

	return star_coverage(
		local,
		radius,
		inner_ratio,
		points,
		rotation
	);
}


// --------------------------------------------------
// Triangle band geometry.
// --------------------------------------------------

float tooth_profile(float along_edge) {
	float phase = fract(along_edge / tooth_width);

	return tooth_depth * (
		1.0 - abs(2.0 * phase - 1.0)
	);
}

float teeth_coverage(
	float distance_from_edge,
	float along_edge,
	float softness
) {
	float d = distance_from_edge
		- tooth_profile(along_edge);

	float blur = max(fwidth(d), softness);

	return 1.0 - smoothstep(-blur, blur, d);
}


// --------------------------------------------------
// Main fragment.
// --------------------------------------------------

void fragment() {
	vec2 p = UV * rect_size;

	// ----------------------------------------------
	// Drifting magical star grid.
	// ----------------------------------------------

	vec2 grid_pos = (
		p + dot_drift * TIME
	) / dot_spacing;

	// Integer grid coordinates identify each star.
	vec2 cell_id = floor(grid_pos);

	// Local position centered inside each cell.
	vec2 local = (
		fract(grid_pos) - 0.5
	) * dot_spacing;

	// Render a randomized magical star.
	float star_mask = magical_star(
		local,
		cell_id
	);

	vec3 color = mix(
		background_color.rgb,
		dot_color.rgb,
		star_mask
	);

	// ----------------------------------------------
	// Triangle bands.
	// ----------------------------------------------

	float hide = (1.0 - band_reveal) * (
		tooth_depth
		+ shadow_offset.x
		+ shadow_softness * 2.0
		+ 2.0
	);

	float left_distance = p.x + hide;

	float right_distance = rect_size.x - p.x + hide;

	float offset = glide_speed * TIME;

	float left_along = p.y - offset;
	float right_along = p.y + offset;

	// ----------------------------------------------
	// Drop shadows.
	// ----------------------------------------------

	float shadow = max(
		teeth_coverage(
			left_distance - shadow_offset.x,
			left_along - shadow_offset.y,
			shadow_softness
		),
		teeth_coverage(
			right_distance - shadow_offset.x,
			right_along - shadow_offset.y,
			shadow_softness
		)
	);

	color = mix(
		color,
		shadow_color.rgb,
		shadow * shadow_color.a
	);

	// ----------------------------------------------
	// Solid triangle bands.
	// ----------------------------------------------

	float teeth = max(
		teeth_coverage(
			left_distance,
			left_along,
			0.0
		),
		teeth_coverage(
			right_distance,
			right_along,
			0.0
		)
	);

	color = mix(
		color,
		triangle_color.rgb,
		teeth
	);

	COLOR = vec4(color, 1.0);
}