import 'nlib_bench3.dart';

void runBench(String name, Function testCase) {
  print("\n[*] BENCHMARK: $name");
  final sw = Stopwatch()..start();
  testCase();
  sw.stop();
  print("  - Time: ${sw.elapsedMilliseconds}ms");
}

void main() {
  print("==========================================");
  print("     🏃‍♂️ OCHE ZERO-COPY BENCHMARK 🏃‍♂️    ");
  print("==========================================\n");

  const SIZE = 10000000; // 10 Million Items

  print(">>> SCENARIO 1: Generate & Sum 10M Objects <<<\n");

  // 1. Pure Dart creation and summation
  runBench("Pure Dart (Object Creation & Sum)", () {
    final list = List.generate(
      SIZE,
      (i) => Vec3(x: i.toDouble(), y: i * 2.0, z: i * 3.0),
      growable: false,
    );
    double sum = 0;
    for (var i = 0; i < list.length; i++) {
      sum += list[i].x + list[i].y + list[i].z;
    }
  });

  // 2. Nim -> Dart (Copy Mode)
  runBench("Oche Copy Mode (Old FFI Way / Deep Copy)", () {
    final list = oche.generateLargeArrayCopy(SIZE);
    double sum = 0;
    for (var i = 0; i < list.length; i++) {
      sum += list[i].x + list[i].y + list[i].z;
    }
  });

  // 3. Nim -> Dart (Zero-Copy View Mode)
  runBench("Oche Zero-Copy View Mode (The New Way!)", () {
    final view = oche.generateLargeArrayView(SIZE);
    double sum = 0;
    for (var i = 0; i < view.length; i++) {
      sum += view[i].x + view[i].y + view[i].z;
    }
  });

  print("\n>>> SCENARIO 2: Particle Update (Mutation of 10M Vec3) <<<\n");

  // Pure Dart updating particles
  runBench("Pure Dart Mutable", () {
    final particles = List.generate(
      SIZE,
      (i) => Vec3(x: 0, y: 0, z: 0),
      growable: false,
    );
    for (var i = 0; i < particles.length; i++) {
      particles[i] = Vec3(
        x: particles[i].x + 0.16,
        y: particles[i].y + 0.32,
        z: particles[i].z + 0.48,
      );
    }
  });

  // Oche Native Code Memory Shared Update
  runBench("Oche Shared Buffer (Nim Updates Memory in C)", () {
    final shared = oche.initParticles(SIZE);
    oche.nimUpdateParticles(0.16); // Direct RAM update
  });

  print("\n==========================================");
  print("   🏁 BENCHMARK COMPLETE! 🏁      ");
  print("==========================================");
}
