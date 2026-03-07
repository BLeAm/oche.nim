# 🦅 Oche & Porche: Complete Guide

> **Oche** (Dart) and **Porche** (Python) are revolutionary FFI systems that bridge **Nim** with high-level languages while maintaining **zero-copy performance** and **memory safety**. This guide covers everything from philosophy to advanced usage.

---

## 📚 Table of Contents

- [Philosophy & Architecture](#-philosophy--architecture)
- [Installation & Setup](#-installation--setup)
- [Basic Usage](#-basic-usage)
- [Advanced Features](#-advanced-features)
- [Memory Management](#-memory-management)
- [Benchmarks](#-benchmarks)
- [API Reference](#-api-reference)
- [Troubleshooting](#-troubleshooting)

---

## 🧠 Philosophy & Architecture

### The Problem with Traditional FFI

Traditional FFI approaches suffer from:
- **Serialization Overhead**: JSON/binary conversion kills performance
- **Memory Leaks**: Manual memory management is error-prone
- **Ergonomic Issues**: Foreign objects don't feel native
- **Safety Gaps**: Type mismatches and buffer overflows

### Oche's Solution: Zero-Copy with Safety

Oche/Porche solve these through:

#### 1. **Unified Memory Layout**
All data uses a single ABI: `[int64 length][int32 typeId][int32 flags][data...]`

#### 2. **Split-Ownership Model**
- **Snapshot Mode**: Nim creates data, target language owns and GC manages
- **Shared Mode**: Nim retains ownership, target language can safely mutate

#### 3. **Deep Analysis & Auto-Generation**
Macros analyze your types and generate:
- Memory-safe destructors
- Zero-copy accessors
- Type-safe bindings

#### 4. **POD Optimization**
Plain Old Data structs bypass expensive recursive cleanup.

---

## 🛠️ Installation & Setup

### Prerequisites
- **Nim 2.0+** with ARC/ORC memory management
- **Dart 3.0+** (for Oche) or **Python 3.8+** (for Porche)

### Project Structure
```
your_project/
├── src/
│   ├── main.nim          # Your Nim code with {.oche.}/{.porche.} annotations
│   ├── oche.nim          # Oche library
│   └── benchmark/        # Optional benchmarks
├── libmain.so            # Compiled Nim library
├── nlib.dart             # Generated Dart bindings
└── nlib.py              # Generated Python bindings
```

### Compilation
```bash
# Compile Nim library
nim c --app:lib --out:libmain.so src/main.nim

# Generate bindings (called from main.nim)
generate("nlib.dart")      # For Dart
generatePython("nlib.py")  # For Python
```

---

## 🎯 Basic Usage

### Defining Types

```nim
import oche  # or porche

# Enums work automatically
type Status {.oche.} = enum  # {.porche.} for Python
  Active, Inactive, Pending

# Structs with automatic memory analysis
type User {.oche.} = object
  id: int
  name: string          # Strings are safely managed
  status: Status
  tags: seq[string]     # Sequences work too

type Point {.oche.} = object
  x, y: float           # POD structs are optimized
```

### Defining Functions

```nim
# Basic function
proc greet(name: string): string {.oche.} =
  "Hello, " & name

# Complex return types
proc createUser(id: int): User {.oche.} =
  User(
    id: id,
    name: "User_" & $id,
    status: Active,
    tags: @["new"]
  )

# Shared buffers (live mutation)
proc getUsers(): OcheBuffer[User] {.oche.} =
  newOche[User](100)  # Creates shared buffer

# Options/Nullables
proc findUser(id: int): Option[User] {.oche.} =
  if id == 42:
    some(User(id: 42, name: "Admin"))
  else:
    none(User)
```

### Dart Usage

```dart
import 'nlib.dart';

void main() async {
  // Basic calls
  final greeting = await oche.greet("World");
  print(greeting);  // "Hello, World"

  // Struct handling
  final user = await oche.createUser(42);
  print('User: ${user.name}');  // "User: User_42"

  // Shared buffers
  final users = await oche.getUsers();
  users[0] = User(name: "Modified", status: Status.active);

  // Options
  final maybeUser = await oche.findUser(42);
  if (maybeUser != null) {
    print('Found: ${maybeUser.name}');
  }
}
```

### Python Usage

```python
import nlib

# Basic calls
greeting = nlib.porche.greet("World")
print(greeting)  # "Hello, World"

# Struct handling
user = nlib.porche.createUser(42)
print(f'User: {user["name"]}')  # "User: User_42"

# Shared buffers
users = nlib.porche.getUsers()
users[0] = {"name": "Modified", "status": 0}  # Safe mutation

# Options
maybe_user = nlib.porche.findUser(42)
if maybe_user is not None:
    print(f'Found: {maybe_user["name"]}')

# NumPy integration
import numpy as np
points = nlib.porche.getPoints()
arr = points.to_numpy()  # Zero-copy NumPy array
```

---

## 🔧 Advanced Features

### Memory Views vs Copies

```nim
# View: Zero-copy read-only access
proc getUsersView(): seq[User] {.oche.} =
  # Returns view, memory managed by Dart GC

# Copy: Data ownership transfer
proc getUsersCopy(): seq[User] {.oche.} =
  # Returns copy, Nim can free immediately

# Shared: Live mutation capability
proc getUsersShared(): OcheBuffer[User] {.oche.} =
  # Returns shared buffer for mutation
```

### Custom String Handling

```nim
# Use toOcheStr for strings that persist
var globalName = toOcheStr("Persistent")

proc getGlobalName(): string {.oche.} =
  $globalName  # Safe string return
```

### Error Handling

```nim
proc riskyOperation(): string {.oche.} =
  if rand(1.0) < 0.1:
    raise newException(ValueError, "Random failure")
  "Success"
```

```dart
// Dart catches Nim exceptions
try {
  final result = await oche.riskyOperation();
} catch (e) {
  print('Nim error: $e');
}
```

```python
# Python catches Nim exceptions
try:
    result = nlib.porche.riskyOperation()
except RuntimeError as e:
    print(f'Nim error: {e}')
```

---

## 🧠 Memory Management Deep Dive

### Ownership Models

#### Snapshot Mode (Default)
```nim
proc getData(): seq[int] {.oche.} =
  @[1, 2, 3]  # Nim allocates, transfers ownership to target
```
- Nim allocates memory
- Target language receives ownership
- Automatic cleanup via GC finalizers

#### Shared Mode
```nim
var buffer: OcheBuffer[int]

proc initBuffer(): OcheBuffer[int] {.oche.} =
  buffer = newOche[int](1000)
  buffer

proc modifyBuffer() {.oche.} =
  buffer[0] = 42  # Safe mutation
```
- Nim retains ownership
- Target can mutate safely
- Manual cleanup required

### POD vs Complex Types

```nim
type Simple {.oche.} = object
  x, y: int  # POD: O(1) cleanup

type Complex {.oche.} = object
  name: string  # Not POD: O(N) recursive cleanup
```

### Memory Layout

```
Buffer Layout:
┌─────────────┬─────────────┬─────────────┬─────────────────┐
│   int64     │   int32     │   int32     │     data...     │
│   length    │   typeId    │   flags     │                 │
└─────────────┴─────────────┴─────────────┴─────────────────┘
```

---

## 📊 Benchmarks

### Methodology
We benchmark CPU-intensive tasks comparing:
- **Pure Target**: Native implementation
- **Nim+Oche/Porche**: FFI overhead included

### Results Summary

#### Dart (Oche)
| Benchmark | Pure Dart | Nim+Oche | Speedup |
|-----------|-----------|----------|---------|
| Monte Carlo Pi | 450ms | 380ms | 1.18x |
| Mandelbrot | 1250ms | 980ms | 1.28x |
| N-Body | 890ms | 720ms | 1.24x |

#### Python (Porche)
| Benchmark | Pure Python | Nim+Porche | Speedup |
|-----------|-------------|------------|---------|
| Monte Carlo Pi (10M) | 0.96s | 1.51s | 0.64x |
| Mandelbrot (1000x1000) | 17.26s | 1.13s | 15.22x |

*Dart results on M1 MacBook Pro, Python on Linux x64, 10M iterations*

### Running Benchmarks

```bash
# Dart benchmarks
cd src/benchmark
dart bench.dart

# Python benchmarks
python3 src/benchmark/bench_py.py
```

---

## 📖 API Reference

### Nim Annotations

#### `{.oche.}` / `{.porche.}`
Marks types/functions for export.

#### `toOcheStr(s: string)`
Creates persistent strings.

#### `newOche[T](n: int)`
Creates shared buffers.

### Generated APIs

#### Dart
- `oche.functionName(args)` - Async function calls
- `SharedListView<T>` - Mutable shared buffers
- `NativeListView<T>` - Read-only views

#### Python
- `porche.functionName(args)` - Function calls
- `_SharedView` - Mutable shared buffers with NumPy support

---

## 🔍 Troubleshooting

### Common Issues

#### "Library not found"
- Ensure `libmain.so` is in the same directory
- Check library naming (`libmain.dll` on Windows)

#### Memory Errors
- Use `toOcheStr()` for persistent strings
- Avoid returning stack-allocated data

#### Type Mismatches
- Ensure Nim and target types match exactly
- Check generated bindings for type conversions

### Debug Mode
```bash
# Compile with debug info
nim c --app:lib --debuginfo src/main.nim
```

---

## 🎯 Best Practices

1. **Use Shared Buffers for Large Data**: Zero-copy access
2. **POD Types for Performance**: Bypass expensive cleanup
3. **Error Handling**: Always wrap FFI calls in try-catch
4. **String Management**: Use `toOcheStr()` for persistence
5. **Type Consistency**: Keep Nim and target type definitions in sync

---

## 🚀 Advanced Topics

### Custom Type Mappings
Override default type conversions by modifying emitter code.

### Extending the System
Add new target languages by implementing emitter modules.

### Performance Tuning
- Use POD types when possible
- Minimize cross-language calls
- Batch operations where feasible

---

## 🤝 Contributing

We welcome contributions! Areas of interest:
- New target language support
- Performance optimizations
- Documentation improvements
- Benchmark expansions

---

## 📄 License

MIT License - see project root for details.

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
