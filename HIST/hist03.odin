package main

import "core:fmt"
import "core:math"
import "core:math/rand"

import rl "vendor:raylib"

// ARCHITECTURE NOTES:
// - Scene1: Curve batching with SIMD-ready architecture
// - Scene2: Rotating lines with continuous time
// - Parameter system: String-indexed singleton with linear velocity
// - Params control scene elements independently (lockless shared state)

Vec2 :: [2]f32

// ===== PARAMETER SYSTEM =====

Param_Value :: struct {
	value:    f32, // Current value
	min:      f32, // Minimum value
	max:      f32, // Maximum value
	velocity: f32, // Units per second (can be negative)
}

// Global singleton - string-indexed for portability
g_params: map[string]Param_Value

// Initialize parameter system
param_init :: proc() {
	g_params = make(map[string]Param_Value)

	// Redness of Category C curves: [0-1] range, increases 0.2/sec
	g_params["Redness_ofCpoints"] = Param_Value {
		value    = 0.4, // Start at 40%
		min      = 0.0,
		max      = 1.0,
		velocity = 0.2, // +20% per second (reaches max in 3 sec)
	}

	// Greenness of Scene2 lines: [0-1] range, decreases 0.15/sec
	g_params["Greenness_ofBlines"] = Param_Value {
		value    = 0.8, // Start at 80%
		min      = 0.0,
		max      = 1.0,
		velocity = -0.15, // -15% per second (reaches min in ~5 sec)
	}
}

// Update all parameters (linear velocity)
param_update :: proc(dt: f32) {
	for key, &param in g_params {
		// Apply velocity
		param.value += param.velocity * dt

		// Clamp to range
		param.value = clamp(param.value, param.min, param.max)
	}
}

// Get parameter value
param_get :: proc(label: string) -> f32 {
	if param, ok := g_params[label]; ok {
		return param.value
	}
	return 0.0 // Default if not found
}

// Set parameter value (for external control later)
param_set :: proc(label: string, value: f32) {
	if param, ok := &g_params[label]; ok {
		param.value = clamp(value, param.min, param.max)
	}
}

// Set parameter velocity (for scripting)
param_set_velocity :: proc(label: string, velocity: f32) {
	if param, ok := &g_params[label]; ok {
		param.velocity = velocity
	}
}

// ===== SCENE 2: ROTATING LINES =====

Scene2_Line :: struct {
	start:          Vec2,
	end:            Vec2,
	color:          rl.Color,
	rotation_speed: f32, // Radians per second
	pivot:          Vec2, // Point to rotate around
}

Scene2 :: struct {
	lines: [dynamic]Scene2_Line,
}

// Generate random rotating lines
scene2_generate_lines :: proc(count: int) -> Scene2 {
	scene: Scene2
	scene.lines = make([dynamic]Scene2_Line, 0, count)

	for i in 0 ..< count {
		line: Scene2_Line

		// Random pivot point
		line.pivot = {rand.float32() * 800, rand.float32() * 600}

		// Random line endpoints relative to pivot
		offset := rand.float32() * 100 + 50 // Length: 50-150
		angle := rand.float32() * 2.0 * math.PI
		line.start = line.pivot
		line.end = line.pivot + Vec2{math.cos(angle), math.sin(angle)} * offset

		// Random rotation speed (-2 to 2 radians/sec)
		line.rotation_speed = (rand.float32() - 0.5) * 4.0

		// Random color
		line.color = rl.Color {
			u8(rand.int31() % 256),
			u8(rand.int31() % 256),
			u8(rand.int31() % 256),
			255,
		}

		append(&scene.lines, line)
	}

	fmt.printf("Scene2: Created %d rotating lines\n", count)
	return scene
}

// Update Scene2 - rotate all lines
scene2_update :: proc(scene: ^Scene2, dt: f32) {
	for &line in scene.lines {
		// Rotate the line around its pivot
		angle := line.rotation_speed * dt

		// Vector from pivot to end
		vec := line.end - line.pivot

		// Rotate vector
		cos_a := math.cos(angle)
		sin_a := math.sin(angle)
		rotated := Vec2{vec.x * cos_a - vec.y * sin_a, vec.x * sin_a + vec.y * cos_a}

		// Update end point
		line.end = line.pivot + rotated
	}
}

// Render Scene2 with parameter control
scene2_render :: proc(scene: ^Scene2) {
	// Get parameter value
	greenness_b := param_get("Greenness_ofBlines")

	for line in scene.lines {
		color := line.color

		// Apply Greenness parameter to ALL lines
		color.g = u8(greenness_b * 255.0) // Map [0-1] to [0-255]

		rl.DrawLineEx(line.start, line.end, 2, color)
		// Draw pivot point
		rl.DrawCircleV(line.pivot, 3, rl.Color{255, 255, 255, 100})
	}
}

// ===== SCENE 1: CURVE BATCHING =====

Scene1_Curve_Type :: enum {
	Bezier,
	Catmull_Rom,
	Linear,
	Hermite,
	TCB, // Kochanek-Bartels
}

Scene1_Curve_Category :: enum {
	A, // 50% of curves
	B, // 30% of curves
	C, // 20% of curves
}

Scene1_Curve :: struct {
	type:           Scene1_Curve_Type,
	control_points: [4]Vec2, // Enough for cubic curves
	color:          rl.Color,
	category:       Scene1_Curve_Category,
}

Scene1_Curve_Batch :: struct {
	type:    Scene1_Curve_Type,
	curves:  [dynamic]^Scene1_Curve,
	results: [dynamic]Vec2, // Store evaluated positions
}

// Generate random test curves
scene1_generate_test_curves :: proc(count: int) -> [dynamic]Scene1_Curve {
	curves := make([dynamic]Scene1_Curve, 0, count)

	for i in 0 ..< count {
		curve: Scene1_Curve

		// Random type distribution
		r := rand.float32()
		if r < 0.35 {
			curve.type = .Bezier // 35% Bezier
		} else if r < 0.60 {
			curve.type = .Catmull_Rom // 25% Catmull
		} else if r < 0.75 {
			curve.type = .Hermite // 15% Hermite
		} else if r < 0.90 {
			curve.type = .TCB // 15% TCB
		} else {
			curve.type = .Linear // 10% Linear
		}

		// Assign category (50% A, 30% B, 20% C)
		cat_r := rand.float32()
		if cat_r < 0.50 {
			curve.category = .A
		} else if cat_r < 0.80 {
			curve.category = .B
		} else {
			curve.category = .C
		}

		// Random control points in screen space
		for j in 0 ..< 4 {
			curve.control_points[j] = {rand.float32() * 800, rand.float32() * 600}
		}

		// Random color
		curve.color = rl.Color {
			u8(rand.int31() % 256),
			u8(rand.int31() % 256),
			u8(rand.int31() % 256),
			255,
		}

		append(&curves, curve)
	}

	// Count categories
	count_a, count_b, count_c := 0, 0, 0
	for curve in curves {
		switch curve.category {
		case .A:
			count_a += 1
		case .B:
			count_b += 1
		case .C:
			count_c += 1
		}
	}

	fmt.printf("Scene1 curves - A: %d, B: %d, C: %d\n", count_a, count_b, count_c)

	return curves
}

// Group curves by type - simple greedy algorithm
scene1_batch_curves_by_type :: proc(curves: []Scene1_Curve) -> [dynamic]Scene1_Curve_Batch {
	batches := make([dynamic]Scene1_Curve_Batch)

	// Create batches for each type
	bezier_batch := Scene1_Curve_Batch {
		type = .Bezier,
	}
	catmull_batch := Scene1_Curve_Batch {
		type = .Catmull_Rom,
	}
	linear_batch := Scene1_Curve_Batch {
		type = .Linear,
	}
	hermite_batch := Scene1_Curve_Batch {
		type = .Hermite,
	}
	tcb_batch := Scene1_Curve_Batch {
		type = .TCB,
	}

	// Sort curves into batches
	for &curve in curves {
		switch curve.type {
		case .Bezier:
			append(&bezier_batch.curves, &curve)
		case .Catmull_Rom:
			append(&catmull_batch.curves, &curve)
		case .Linear:
			append(&linear_batch.curves, &curve)
		case .Hermite:
			append(&hermite_batch.curves, &curve)
		case .TCB:
			append(&tcb_batch.curves, &curve)
		}
	}

	// Only add non-empty batches
	if len(bezier_batch.curves) > 0 {
		append(&batches, bezier_batch)
	}
	if len(catmull_batch.curves) > 0 {
		append(&batches, catmull_batch)
	}
	if len(linear_batch.curves) > 0 {
		append(&batches, linear_batch)
	}
	if len(hermite_batch.curves) > 0 {
		append(&batches, hermite_batch)
	}
	if len(tcb_batch.curves) > 0 {
		append(&batches, tcb_batch)
	}

	// Allocate result buffers
	for &batch in batches {
		batch.results = make([dynamic]Vec2, 0, len(batch.curves))
	}

	fmt.printf("Created %d batches:\n", len(batches))
	for batch in batches {
		fmt.printf("  %v: %d curves\n", batch.type, len(batch.curves))
	}

	return batches
}

// Evaluate Bezier curve (cubic)
evaluate_bezier :: proc(t: f32, p0, p1, p2, p3: Vec2) -> Vec2 {
	u := 1.0 - t
	tt := t * t
	uu := u * u
	uuu := uu * u
	ttt := tt * t

	return uuu * p0 + 3 * uu * t * p1 + 3 * u * tt * p2 + ttt * p3
}

// Evaluate Catmull-Rom curve
evaluate_catmull_rom :: proc(t: f32, p0, p1, p2, p3: Vec2) -> Vec2 {
	t2 := t * t
	t3 := t2 * t

	return(
		0.5 *
		((2.0 * p1) +
				(-p0 + p2) * t +
				(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
				(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3) \
	)
}

// Evaluate linear interpolation
evaluate_linear :: proc(t: f32, p0, p1, p2, p3: Vec2) -> Vec2 {
	return (1.0 - t) * p0 + t * p3 // Just use first and last point
}

// Evaluate Cubic Hermite curve
evaluate_hermite :: proc(t: f32, p0, p1, p2, p3: Vec2) -> Vec2 {
	t2 := t * t
	t3 := t2 * t

	// Hermite basis functions
	h00 := 2 * t3 - 3 * t2 + 1
	h10 := t3 - 2 * t2 + t
	h01 := -2 * t3 + 3 * t2
	h11 := t3 - t2

	// Use p0 and p3 as endpoints, p1 and p2 as tangents
	m0 := p1 - p0 // Start tangent
	m1 := p3 - p2 // End tangent

	return h00 * p0 + h10 * m0 + h01 * p3 + h11 * m1
}

// Evaluate Kochanek-Bartels (TCB) spline
evaluate_tcb :: proc(t: f32, p0, p1, p2, p3: Vec2) -> Vec2 {
	t2 := t * t
	t3 := t2 * t

	return(
		0.5 *
		((2.0 * p1) +
				(-p0 + p2) * t +
				(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
				(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3) \
	)
}

// Evaluate all batches
scene1_evaluate_batches :: proc(batches: []Scene1_Curve_Batch, t: f32) {
	for &batch in batches {
		clear(&batch.results)

		for curve in batch.curves {
			p0 := curve.control_points[0]
			p1 := curve.control_points[1]
			p2 := curve.control_points[2]
			p3 := curve.control_points[3]

			result: Vec2
			switch batch.type {
			case .Bezier:
				result = evaluate_bezier(t, p0, p1, p2, p3)
			case .Catmull_Rom:
				result = evaluate_catmull_rom(t, p0, p1, p2, p3)
			case .Linear:
				result = evaluate_linear(t, p0, p1, p2, p3)
			case .Hermite:
				result = evaluate_hermite(t, p0, p1, p2, p3)
			case .TCB:
				result = evaluate_tcb(t, p0, p1, p2, p3)
			}

			append(&batch.results, result)
		}
	}
}

// Render Scene1 with parameter control
scene1_render :: proc(batches: []Scene1_Curve_Batch) {
	// Get parameter value
	redness_c := param_get("Redness_ofCpoints")

	for batch in batches {
		for result, i in batch.results {
			curve := batch.curves[i]
			color := curve.color

			// Apply Redness parameter to Category C curves only
			if curve.category == .C {
				color.r = u8(redness_c * 255.0) // Map [0-1] to [0-255]
			}

			rl.DrawCircleV(result, 5, color)
		}
	}
}

main :: proc() {
	rl.InitWindow(800, 600, "Param-Controlled Demo")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	// ===== INITIALIZE PARAMETERS =====
	param_init()
	defer delete(g_params)

	// ===== HARDCODED SCENE DURATIONS =====
	scene1_duration: f32 : 10.0
	scene2_duration: f32 : 5.0
	scene3_duration: f32 : 5.0

	scene1_start: f32 : 0.0
	scene2_start := scene1_start + scene1_duration // 10.0
	scene3_start := scene2_start + scene2_duration // 15.0

	// ===== CREATE SCENES =====
	scene1_curves := scene1_generate_test_curves(100)
	defer delete(scene1_curves)

	scene1_batches := scene1_batch_curves_by_type(scene1_curves[:])
	defer {
		for batch in scene1_batches {
			delete(batch.curves)
			delete(batch.results)
		}
		delete(scene1_batches)
	}

	scene2 := scene2_generate_lines(50)
	defer delete(scene2.lines)

	for !rl.WindowShouldClose() {
		total_time := f32(rl.GetTime())
		dt := rl.GetFrameTime()

		// ===== UPDATE PARAMETERS =====
		param_update(dt)

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{20, 20, 30, 255})

		// ===== SCENE SELECTION =====
		if total_time < scene2_start {
			// SCENE 1: 0-10 seconds
			scene_time := total_time - scene1_start // 0.0 -> 10.0
			t := scene_time / scene1_duration // 0.0 -> 1.0

			scene1_evaluate_batches(scene1_batches[:], t)
			scene1_render(scene1_batches[:])

			rl.DrawText(
				fmt.ctprintf("Scene 1: Curves | t: %.2f | time: %.1f/%.0f", t, scene_time, scene1_duration),
				10,
				10,
				20,
				rl.WHITE,
			)

		} else if total_time < scene3_start {
			// SCENE 2: 10-15 seconds
			scene_time := total_time - scene2_start // 0.0 -> 5.0

			scene2_update(&scene2, dt)
			scene2_render(&scene2)

			rl.DrawText(
				fmt.ctprintf("Scene 2: Rotating Lines | time: %.1f/%.0f", scene_time, scene2_duration),
				10,
				10,
				20,
				rl.WHITE,
			)

		} else if total_time < (scene3_start + scene3_duration) {
			// SCENE 3: 15-20 seconds
			scene_time := total_time - scene3_start // 0.0 -> 5.0

			rl.DrawText("Scene 3: Coming Soon", 300, 280, 30, rl.YELLOW)

			rl.DrawText(
				fmt.ctprintf("Scene 3 | time: %.1f/%.0f", scene_time, scene3_duration),
				10,
				10,
				20,
				rl.WHITE,
			)

		} else {
			// AFTER ALL SCENES (20+ seconds)
			rl.DrawText("Demo Complete!", 300, 280, 30, rl.GREEN)
			rl.DrawText("Press ESC to quit", 300, 320, 20, rl.GRAY)
		}

		// ===== PARAMETER DEBUG INFO =====
		redness := param_get("Redness_ofCpoints")
		greenness := param_get("Greenness_ofBlines")

		rl.DrawText(
			fmt.ctprintf("Redness_ofCpoints: %.2f (vel: +0.2/s)", redness),
			10,
			70,
			16,
			rl.RED,
		)
		rl.DrawText(
			fmt.ctprintf("Greenness_ofBlines: %.2f (vel: -0.15/s)", greenness),
			10,
			90,
			16,
			rl.GREEN,
		)

		// Show total time
		rl.DrawText(fmt.ctprintf("Total: %.1fs", total_time), 10, 40, 20, rl.GRAY)

		rl.EndDrawing()
	}
}