import 'nlib_bench.dart';
import 'dart:math' as math;

// --- DART PURE IMPLEMENTATIONS ---

final _rand = math.Random();

double monteCarloPiDart(int iterations) {
  var count = 0;
  for (var i = 1; i <= iterations; i++) {
    final x = _rand.nextDouble();
    final y = _rand.nextDouble();
    if (x * x + y * y <= 1.0) {
      count++;
    }
  }
  return 4.0 * (count / iterations);
}

List<int> mandelbrotDart(int width, int height, int maxIter) {
  final result = List<int>.filled(width * height, 0);
  for (var y = 0; y < height; y++) {
    final cy = -1.5 + 3.0 * y / height;
    for (var x = 0; x < width; x++) {
      final cx = -2.0 + 3.0 * x / width;
      var zx = 0.0;
      var zy = 0.0;
      var count = 0;
      while (zx * zx + zy * zy <= 4.0 && count < maxIter) {
        final temp = zx * zx - zy * zy + cx;
        zy = 2.0 * zx * zy + cy;
        zx = temp;
        count++;
      }
      result[y * width + x] = count;
    }
  }
  return result;
}

// --- BENCHMARK HARNESS ---

void runBench(String name, Function pure, Function oche) {
  print("\n[*] BENCHMARK: $name");

  final sw1 = Stopwatch()..start();
  final res1 = pure();
  sw1.stop();
  final t1 = sw1.elapsedMicroseconds;
  print("  - Pure Dart: ${sw1.elapsedMilliseconds}ms");

  final sw2 = Stopwatch()..start();
  final res2 = oche();
  sw2.stop();
  final t2 = sw2.elapsedMicroseconds;
  print("  - Nim+Oche:   ${sw2.elapsedMilliseconds}ms");

  final ratio = (t1 / t2).toStringAsFixed(2);
  final winner = t1 > t2 ? "Nim" : "Dart";
  print("  >> Winner: $winner (Faster by $ratio x)");
}

void main() {
  print("==========================================");
  print("     🦅 THE OCHE CHALLENGE SUITE 🦅    ");
  print("==========================================\n");

  // CASE A: Pure Loop Logic (10 Million Iterations)
  const iters = 10000000;
  runBench(
    "Monte Carlo Pi ($iters iterations)",
    () => monteCarloPiDart(iters),
    () => monteCarloPiNim(iters),
  );

  // CASE B: Complex Graphics Math (1000x1000)
  runBench(
    "Mandelbrot Fractal (1000x1000 pixels)",
    () => mandelbrotDart(1000, 1000, 1000),
    () => mandelbrotNim(1000, 1000, 1000),
  );

  print("\n==========================================");
  print("   🏁 CHALLENGE COMPLETE! 🏁      ");
  print("==========================================");
}
