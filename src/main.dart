import 'nlib.dart';

void main() {
  const n = 100000;
  print("==========================================");
  print("    🦅 OCHE SHARED MEMORY CHALLENGE 🦅    ");
  print("==========================================\n");

  // 1. Standard Copy
  print("1. [Standard Copy Mode]");
  final sw1 = Stopwatch()..start();
  final list = oche.getPointsCopy(n);
  sw1.stop();
  print("   - Time to fetch $n points: ${sw1.elapsedMilliseconds}ms");

  // 2. View Mode
  print("\n2. [Zero-Copy View Mode]");
  final sw2 = Stopwatch()..start();
  final view = oche.getPointsView(n);
  sw2.stop();
  print("   - Time to fetch $n points: ${sw2.elapsedMilliseconds}ms");
  view.dispose();

  // 3. True Shared Memory (Mutable)
  print("\n3. [True Shared Memory Mode (Mutable)]");
  final sw3 = Stopwatch()..start();
  final shared = oche.getPointsShared(10);
  sw3.stop();
  print("   - Time to fetch 10 shared points: ${sw3.elapsedMilliseconds}ms");
  print(
    "   - Initial value (Dart): points[0] = (${shared[0].x}, ${shared[0].y})",
  );
  oche.printSharedPoint(0);

  print("   - [Action] Mutating points[0] to (777.7, 555.5) in Dart...");
  shared[0].x = 777.7;
  shared[0].y = 555.5;

  print("   - New value (Dart): points[0] = (${shared[0].x}, ${shared[0].y})");
  oche.printSharedPoint(0);

  print(
    "\n>>> VOILA! Nim sees the change because they share the same memory! 🚀🤝",
  );

  shared.dispose();

  print("\n==========================================");
  print("   🔥 BEYOND ZERO-COPY: SHARED CORE 🔥   ");
  print("==========================================");
}
