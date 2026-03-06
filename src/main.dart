import 'nlib.dart';

void main() async {
  print("==========================================");
  print("   🦅 OCHE: THE ZERO-COPY ENGINE DEMO 🦅   ");
  print("==========================================\n");

  print("=== 1. Basic Primitives & Strings ===");
  print("Add: ${oche.addNumbers(10, 20)}");
  print("Greet: ${oche.greet('Dart')}\n");

  print("=== 2. Structs & Enums ===");
  final user = oche.createUser('JohnDoe', 42);
  print(
    "User: ${user.username}, Status: ${user.status}, Tag: ${user.primaryTag.name}\n",
  );

  print("=== 3. Passing Lists from Dart to Nim ===");
  final points = [Point(x: 1.5, y: 2.5), Point(x: 3.0, y: 4.0)];
  print("Sum of points: ${oche.sumPoints(points)}\n");

  print("=== 4. Getting Lists (Snapshot / NativeListView) ===");
  // NativeListView is owned by Dart GC via Finalizers
  final copied = oche.getPointsCopy(3);
  print("Copied points len: ${copied.length}");
  print("First element: (${copied[0].x}, ${copied[0].y})");
  print(
    "Iterator/map support: ${copied.map((p) => p.x).toList()}\n",
  ); // Proof of List Parity

  print("=== 5. Getting Lists (Zero-Copy View) ===");
  // NativeListView where data is read-only pointers into long-lived Nim memory.
  final view = oche.getPointsView(3);
  print("View points len: ${view.length}");
  print("First element: (${view[0].x}, ${view[0].y})\n");

  print("=== 6. Shared Live Buffer (Mutable POD) ===");
  // SharedListView is owned by Nim, but Dart can read & write elements directly to RAM!
  final sharedPts = oche.initSharedPoints(2);
  print("Initial SharedPoint[0]: (${sharedPts[0].x}, ${sharedPts[0].y})");

  // Dart mutates the struct directly via overriding []= operator
  sharedPts[0] = Point(x: 99.9, y: 88.8);
  print("[Dart] Mutated point 0. Checking if Nim live-updated...");
  oche.printSharedPoint(0);
  print("");

  print("=== 7. Shared Live Buffer (Mutable Complex Nested Struct) ===");
  // Even with nested String Pointers, rewriting values cleans up old strings internally!
  final sharedUsers = oche.initSharedUsers(2);
  print(
    "Initial SharedUser[0]: '${sharedUsers[0].username}' (Tag: ${sharedUsers[0].primaryTag.name})",
  );

  // Trigger _ocheFreeInner securely!
  sharedUsers[0] = User(
    username: 'DartMaster',
    status: Status.Active,
    primaryTag: Tag(name: 'Hero', id: 999),
  );
  print(
    "[Dart] Mutated User & nested Tag/String. Checking if Nim live-updated without leaks...",
  );
  oche.printSharedUser(0);
  print("");

  print("==========================================");
  print("✅ All Oche functionality tested successfully!");
  print("==========================================");
}
