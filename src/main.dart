import 'nlib.dart';

void main() async {
  print("--- 🌌 Oche Absolute Ultimate Test 🌌 ---");

  // 1. ทดสอบ Optional (Nullability)
  print("\n1. Testing Optional Support:");

  final score1 = getScore("Bleamz");
  print("  getScore('Bleamz') = $score1 (Expect: 99.9)");

  final score2 = getScore("Unknown");
  print("  getScore('Unknown') = $score2 (Expect: null)");

  final id1 = await findUserIdAsync("Admin");
  print("  findUserIdAsync('Admin') = $id1 (Expect: 1)");

  final id2 = await findUserIdAsync("Guest");
  print("  findUserIdAsync('Guest') = $id2 (Expect: null)");

  // 2. ทดสอบ Async (Isolate)
  print("\n2. Testing Async/Isolate:");
  final stopwatch = Stopwatch()..start();
  print("  [Dart] Calling slowComputeAsync...");
  final fut = slowComputeAsync(10);
  print("  [Dart] Doing other work...");
  final res = await fut;
  print("  [Nim] slowCompute Result: $res");
  print("  [Dart] Total time: ${stopwatch.elapsedMilliseconds}ms");

  print("\n--- ✅ Mission 100% Accomplished ---");
}
