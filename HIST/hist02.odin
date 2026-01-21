package main

import "core:fmt"
import "core:math"
import "core:math/rand"

import rl "vendor:raylib"

// REFACTOR NOTES:
// - Added Cubic Hermite and Kochanek-Bartels (TCB) curve types
// - All scene structures prefixed with Scene1_ / Scene2_ for multi-scene support
// - Scene1: Curve batching with SIMD-ready architecture (0-10 sec)
// - Scene2: Rotating lines with continuous time (10-20 sec)
// - Hermite uses endpoints + tangent vectors
// - TCB simplified (tension=0) is equivalent to Catmull-Rom
// - Scenes switch every 10 seconds automatically

Vec2 :: [2]f32

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
		line.pivot = {
			rand.float32() * 800,
			rand.float32() * 600,
		}

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
		rotated := Vec2 {
			vec.x * cos_a - vec.y * sin_a,
			vec.x * sin_a + vec.y * cos_a,
		}

		// Update end point
		line.end = line.pivot + rotated
	}
}

// Render Scene2
scene2_render :: proc(scene: ^Scene2) {
	for line in scene.lines {
		rl.DrawLineEx(line.start, line.end, 2, line.color)
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
	TCB,  // Kochanek-Bartels
}

Scene1_Curve :: struct {
	type:           Scene1_Curve_Type,
	control_points: [4]Vec2, // Enough for cubic curves
	color:          rl.Color,
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

		// Random control points in screen space
		for j in 0 ..< 4 {
			curve.control_points[j] = {
				rand.float32() * 800, // x: 0-800
				rand.float32() * 600, // y: 0-600
			}
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
// p0, p3 = endpoints, p1, p2 = tangent vectors
evaluate_hermite :: proc(t: f32, p0, p1, p2, p3: Vec2) -> Vec2 {
	t2 := t * t
	t3 := t2 * t
	
	// Hermite basis functions
	h00 := 2*t3 - 3*t2 + 1
	h10 := t3 - 2*t2 + t
	h01 := -2*t3 + 3*t2
	h11 := t3 - t2
	
	// Use p0 and p3 as endpoints, p1 and p2 as tangents
	m0 := p1 - p0  // Start tangent
	m1 := p3 - p2  // End tangent
	
	return h00 * p0 + h10 * m0 + h01 * p3 + h11 * m1
}

// Evaluate Kochanek-Bartels (TCB) spline
// Simplified version using tension=0, continuity=0, bias=0 (equivalent to Catmull-Rom)
evaluate_tcb :: proc(t: f32, p0, p1, p2, p3: Vec2) -> Vec2 {
	// For simplicity, using Cardinal spline with tension=0
	// This makes it equivalent to Catmull-Rom
	// Full TCB would have tension, continuity, bias parameters
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

main :: proc() {
	rl.InitWindow(800, 600, "Multi-Scene Demo")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	// ===== HARDCODED SCENE DURATIONS =====
	scene1_duration: f32 : 10.0  // 10 seconds
	scene2_duration: f32 : 5.0   // 5 seconds  
	scene3_duration: f32 : 5.0   // 5 seconds
	total_duration := scene1_duration + scene2_duration + scene3_duration  // 20s

	// Scene start times
	scene1_start: f32 : 0.0
	scene2_start := scene1_start + scene1_duration  // 10.0
	scene3_start := scene2_start + scene2_duration  // 15.0

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

	// TODO: scene3 will go here

	for !rl.WindowShouldClose() {
		total_time := f32(rl.GetTime())
		dt := rl.GetFrameTime()

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{20, 20, 30, 255})

		// ===== SCENE SELECTION (SIMPLE IF-ELSE) =====
		if total_time < scene2_start {
			// SCENE 1: 0-10 seconds
			scene_time := total_time - scene1_start  // 0.0 -> 10.0
			t := scene_time / scene1_duration        // 0.0 -> 1.0

			scene1_evaluate_batches(scene1_batches[:], t)

			for batch in scene1_batches {
				for result, i in batch.results {
					curve := batch.curves[i]
					rl.DrawCircleV(result, 5, curve.color)
				}
			}

			rl.DrawText(
				fmt.ctprintf("Scene 1: Curves | t: %.2f | time: %.1f/%.0f", t, scene_time, scene1_duration),
				10, 10, 20, rl.WHITE,
			)

		} else if total_time < scene3_start {
			// SCENE 2: 10-15 seconds
			scene_time := total_time - scene2_start  // 0.0 -> 5.0

			scene2_update(&scene2, dt)
			scene2_render(&scene2)

			rl.DrawText(
				fmt.ctprintf("Scene 2: Rotating Lines | time: %.1f/%.0f", scene_time, scene2_duration),
				10, 10, 20, rl.WHITE,
			)

		} else if total_time < (scene3_start + scene3_duration) {
			// SCENE 3: 15-20 seconds
			scene_time := total_time - scene3_start  // 0.0 -> 5.0

			// TODO: Scene 3 rendering goes here
			rl.DrawText("Scene 3: Coming Soon", 300, 280, 30, rl.YELLOW)

			rl.DrawText(
				fmt.ctprintf("Scene 3 | time: %.1f/%.0f", scene_time, scene3_duration),
				10, 10, 20, rl.WHITE,
			)

		} else {
			// AFTER ALL SCENES (20+ seconds)
			rl.DrawText("Demo Complete!", 300, 280, 30, rl.GREEN)
			rl.DrawText("Press ESC to quit", 300, 320, 20, rl.GRAY)
		}

		// Show global time
		rl.DrawText(
			fmt.ctprintf("Total: %.1fs", total_time),
			10, 40, 20, rl.GRAY,
		)

		rl.EndDrawing()
	}
}