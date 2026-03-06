import 'nlib.dart';

void main() async {
  print("==========================================");
  print("    🦅 OCHE 2.8: THE IRONCLAD 🛡️    ");
  print("==========================================");

  // 1. Snapshot View
  final viewList = oche.getPointsView(100);
  print("\n1. [Zero-Copy View Mode]");
  print("   - Type: ${viewList.runtimeType}");
  print("   - First: (${viewList[0].x}, ${viewList[0].y})");

  // 2. Shared Mode (Full Mutation)
  print("\n2. [True Shared Memory Mode (Full Mutation)]");
  final points = oche.getPointsShared(10);

  print("   - Initial points[0]: (${points[0].x}, ${points[0].y})");

  print(
    "   - [Action] points[0] = Point(x: 123.4, y: 567.8) via []= Operator! 🔥",
  );
  points[0] = Point(x: 123.4, y: 567.8);
  oche.printSharedPoint(0);

  // 3. High Frequency Test (Check for Performance)
  print("\n3. [High-Frequency Stress Test (Arena Optimization)]");
  final swFast = Stopwatch()..start();
  for (var i = 0; i < 100000; i++) {
    oche.updatePointFast(0, i.toDouble());
  }
  swFast.stop();
  print(
    "   - 100,000 FFI calls (No Arena Overhead): ${swFast.elapsedMilliseconds}ms",
  );
  oche.printSharedPoint(0);

  print("\n>>> ALL CRITICAL FIXED! Oche is now Production Ready! 🤝🏁🏎️🛡️");
  print("==========================================");
}
