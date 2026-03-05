import 'nlib.dart';

void main() async {
  print("==========================================");
  print("   🦅 OCHE PURE DART EXPERIENCE 🦅   ");
  print("==========================================\n");

  // 1. เรียกฟังก์ชันปกติ (ใช้ UserRole.Admin ตามที่แก้ใน Nim)
  print("1. [Friendly Objects]");
  final user = User(
    id: 101,
    name: "Dart Hero",
    status: UserRole.Admin,
    position: Point(x: 100.0, y: 200.0),
  );
  print(
    "   Created Dart Object: ${user.name} at (${user.position.x}, ${user.position.y})",
  );

  // 2. ส่ง List ของออบเจกต์ปกติ
  print("\n2. [Automatic Mapping]");
  final points = [Point(x: 1, y: 1), Point(x: 2, y: 2), Point(x: 3, y: 3)];
  final totalSum = sumPoints(points);
  print("   Sum of 3 points: $totalSum");

  // 3. รับออบเจกต์กลับจาก Nim (ข้อมูลถูก copy มาแล้ว ปลอดภัย 100%)
  print("\n3. [Safe Returns]");
  final result42 = findUserById(42);
  if (result42 != null) {
    print("   Found User 42: ${result42.name}, Status: ${result42.status}");
    print("   Position: (${result42.position.x}, ${result42.position.y})");
  }

  // 4. Async
  print("\n4. [Async Isolation]");
  final asyncRes = await heavyTaskAsync(1);
  print("   Async Result: $asyncRes");

  print("\n==========================================");
  print("     ✅ NO FFI IMPORTS IN USER CODE!      ");
  print("==========================================");
}
