import 'nlib.dart';

void main() {
  const n = 100000;
  print("==========================================");
  print("     🦅 OCHE ZERO-COPY CHALLENGE 🦅     ");
  print("==========================================\n");

  // 1. ทดสอบโหมดปกติ (Copy)
  print("1. [Standard Copy Mode]");
  final sw1 = Stopwatch()..start();
  final list = oche.getPointsCopy(n);
  sw1.stop();
  print("   - Time to fetch $n points: ${sw1.elapsedMilliseconds}ms");
  print("   - Accessing point[500]: (${list[500].x}, ${list[500].y})");

  // 2. ทดสอบโหมด View (Zero-Copy)
  print("\n2. [Zero-Copy View Mode]");
  final sw2 = Stopwatch()..start();
  final view = oche.getPointsView(n);
  sw2.stop();
  print("   - Time to fetch $n points: ${sw2.elapsedMilliseconds}ms");

  final p500 = view[500];
  print("   - Accessing point[500] (Live View): (${p500.x}, ${p500.y})");

  final ratio = sw1.elapsedMilliseconds / sw2.elapsedMilliseconds;
  print("\n>>> Zero-Copy is ${ratio.toStringAsFixed(1)}x faster to return!");

  view.dispose();

  print("\n==========================================");
  print("   🚀 SPEED MEETS CONVENIENCE! 🚀      ");
  print("==========================================");
}
