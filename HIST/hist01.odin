package main

import "core:fmt"
import "core:math"
import "core:math/rand"

import rl "vendor:raylib"

//ADD: Cubic Hermite, Kochanek–Bartels (TCB)

Vec2 :: [2]f32

Curve_Type :: enum {
	Bezier,
	Catmull_Rom,
	Linear,
}

Curve :: struct {
	type:           Curve_Type,
	control_points: [4]Vec2, // Enough for cubic curves
	color:          rl.Color,
}

Curve_Batch :: struct {
	type:    Curve_Type,
	curves:  [dynamic]^Curve,
	results: [dynamic]Vec2, // Store evaluated positions
}

// Generate random test curves
generate_test_curves :: proc(count: int) -> [dynamic]Curve {
	curves := make([dynamic]Curve, 0, count)

	for i in 0 ..< count {
		curve: Curve

		// Random type distribution
		r := rand.float32()
		if r < 0.5 {
			curve.type = .Bezier // 50% Bezier
		} else if r < 0.8 {
			curve.type = .Catmull_Rom // 30% Catmull
		} else {
			curve.type = .Linear // 20% Linear
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
batch_curves_by_type :: proc(curves: []Curve) -> [dynamic]Curve_Batch {
	batches := make([dynamic]Curve_Batch)

	// Create batches for each type
	bezier_batch := Curve_Batch {
		type = .Bezier,
	}
	catmull_batch := Curve_Batch {
		type = .Catmull_Rom,
	}
	linear_batch := Curve_Batch {
		type = .Linear,
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

// Evaluate all batches
evaluate_batches :: proc(batches: []Curve_Batch, t: f32) {
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
			}

			append(&batch.results, result)
		}
	}
}

main :: proc() {
	rl.InitWindow(800, 600, "Let's Go!")
	defer rl.CloseWindow()

	// ===== BEFORE LOOP: GENERATE & BATCH =====
	curves := generate_test_curves(100)
	defer delete(curves)

	batches := batch_curves_by_type(curves[:])
	defer {
		for batch in batches {
			delete(batch.curves)
			delete(batch.results)
		}
		delete(batches)
	}

	rl.SetTargetFPS(60)

	for !rl.WindowShouldClose() {
		// Time parameter cycles 0 -> 1
		t := math.mod_f32(f32(rl.GetTime()) * 0.1, 1.0)

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{20, 20, 30, 255})

		// Evaluate all curves at time t
		evaluate_batches(batches[:], t)

		// Draw results
		for batch in batches {
			for result, i in batch.results {
				curve := batch.curves[i]
				rl.DrawCircleV(result, 5, curve.color)
			}
		}

		// UI
		rl.DrawText(fmt.ctprintf("Curves: %d | t: %.2f", len(curves), t), 10, 10, 20, rl.WHITE)

		rl.EndDrawing()
	}
}
