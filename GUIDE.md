# 🦅 Oche: The High-Performance Nim-Dart FFI Bridge

Oche (อ่านว่า "โอ-เช่") คือ Library Generator ที่ช่วยสร้างสะพานเชื่อมระหว่าง **Nim** และ **Dart (Flutter)** โดยเน้นที่ประสิทธิภาพสูงสุด (Low-latency), ความปลอดภัยของหน่วยความจำ (Memory Safety), และประสบการณ์การพัฒนาที่ราบรื่น (Modern Ergonomics)

---

## 🏗️ Architecture Overview

สถาปัตยกรรมของ Oche แบ่งออกเป็น 3 ส่วนหลัก:

### 1. The Macro Layer (Nim)
เมื่อคุณใส่ `{.oche.}` ไว้ที่หน้า `proc`, `type`, หรือ `enum`, Macro จะทำการ:
- **Wrap Logic:** หุ้มฟังก์ชันจริงด้วย `try-except` เพื่อดักจับ Error
- **Memory Translation:** แปลงประเภทข้อมูลซับซ้อน (seq, string, Option) ให้กลายเป็น Raw Pointers ที่ Dart เข้าใจ
- **Exporting:** ทำการ `exportc` เพื่อให้ฟังก์ชันถูกมองเห็นจากภายนอก Shared Library

### 2. The Shared Library (.so)
หัวใจของประสิทธิภาพคือ Shared Library ที่ Nim Compile ออกมา ข้อมูลจะถูกส่งผ่านหน่วยความจำโดยตรง (Direct Memory Address) โดยไม่มีการแปลงเป็น JSON หรือ Serialization ใดๆ

### 3. The Generator Layer (Dart)
Oche จะสร้างไฟล์ `nlib.dart` ซึ่งประกอบด้วย:
- **FFI Bindings:** การเชื่อมต่อระดับ Low-level กับฟังก์ชันใน Nim
- **Async Wrappers:** การสถาปนาฟังก์ชันเวอร์ชัน `Async` ที่รันบน **Dart Isolate** อัตโนมัติ
- **Error Propagation:** ระบบตรวจสอบ `_checkError()` หลังการเรียกทุกครั้ง เพื่อโยน Exception กลับไปหาผู้ใช้

---

## 🚀 Key Features & Examples

### 1. Basic Types & Strings
Oche จัดการเรื่องหน่วยความจำของ String ให้โดยอัตโนมัติ คุณไม่ต้องกังวลเรื่องการล้าง Memory (`dealloc`) เพราะเราใช้ระบบ `try-finally` ในฝั่ง Dart

```nim
proc greet(name: string): string {.oche.} =
  "Hello, " & name
```

### 2. Complex Objects (Structs)
คุณสามารถส่งโครงสร้างข้อมูลซับซ้อนข้ามไปมาได้

```nim
type 
  User {.oche.} = object
    id: int
    name: string

proc createPlayer(id: int): User {.oche.} =
  User(id: id, name: "Player_" & $id)
```

### 3. Enums (Type-safe)
เชื่อมต่อ Enum ของ Nim เข้ากับ Enum ของ Dart โดยตรง

```nim
type 
  Status {.oche.} = enum
    Active, Inactive

proc getStatus(): Status {.oche.} = Active
```

### 4. Optional / Nullability (New!)
รองรับ `Option[T]` จาก Nim ให้กลายเป็น `T?` ใน Dart

```nim
import std/options

proc findValue(key: string): Option[int] {.oche.} =
  if key == "secret": some(42)
  else: none(int)
```

### 5. Multi-threading (Async Support)
ฟังก์ชันที่ถูก gen จะมีเวอร์ชัน `Async` เสมอ เพื่อไม่ให้ UI ค้าง

```dart
// ใน Dart
final result = await findValueAsync("secret"); // รันใน Isolate อื่นอัตโนมัติ
```

### 6. Robust Error Handling
หาก Nim เกิด Error, Dart จะได้รับเป็น `Exception`

```nim
proc dangerZone() {.oche.} =
  raise newException(ValueError, "Something went wrong in Nim!")
```
```dart
// ใน Dart
try {
  dangerZone();
} catch (e) {
  print(e); // Output: Exception: NimError: Something went wrong in Nim!
}
```

---

## 💡 Performance Optimization Tips

- **Zero-copy for Lists:** สำหรับ `seq[T]` Oche ใช้ `asTypedList` ใน Dart ซึ่งเป็นการเข้าถึงหน่วยความจำก้อนเดียวกับ Nim โดยตรง (ไม่มีการ Copy ข้อมูลใหญ่ๆ)
- **Release Build:** เมื่อใช้งานจริง อย่าลืม Compile Nim ด้วย `-d:release` เพื่อความเร็วสูงสุด
- **Arena Allocation:** Oche ใช้ `using((arena) { ... })` ใน Dart เพื่อจัดการหน่วยความจำชั่วคราวอย่างมีประสิทธิภาพ

---

## 🛠️ How to Compile

1. **Compile Nim:**
   ```bash
   nim c --app:lib --out:libmain.so main.nim
   ```
2. **Run Dart:**
   ```bash
   dart main.dart
   ```

---

**Oche: Bridging the gap between Nim's power and Dart's elegance.**
