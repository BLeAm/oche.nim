# 🦅 Oche & Porche: Zero-Copy FFI Engines for Nim ↔ Dart/Python

> **Oche** (Dart) and **Porche** (Python) are industrial-grade, highly-optimized FFI bridges and memory sharing systems designed specifically for **Nim and Dart (Flutter)** or **Nim and Python**. They transcend simple dynamic bindings by employing a **Zero-Copy Serialization Engine** and a **Split-Ownership Lifecycle Model**, delivering maximum performance with an extremely ergonomic API.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Nim](https://img.shields.io/badge/Nim-2.0+-blue.svg)](https://nim-lang.org/)
[![Dart](https://img.shields.io/badge/Dart-3.0+-blue.svg)](https://dart.dev/)
[![Python](https://img.shields.io/badge/Python-3.8+-blue.svg)](https://python.org/)

---

## 🌟 Key Features

### 🚀 Performance
- **Zero-Copy Memory Sharing**: Direct memory access without serialization overhead
- **Unified ABI Layout**: Single binary format: `[int64 length][int32 typeId][int32 flags][data...]`
- **POD Bypass**: O(1) destructors for Plain Old Data structs
- **Deep Recursive Safety**: Automatic memory management for nested structures

### 🔧 Ergonomics
- **Native List Parity**: Shared buffers behave identically to native `List<T>` in Dart/Python
- **Split-Ownership Model**:
  - **Snapshot Mode**: Nim hands memory to target language with automatic GC integration
  - **Shared Live Buffer**: Nim retains ownership while allowing safe mutations
- **Type Safety**: Full compile-time type checking across language boundaries

### 🛡️ Safety
- **Memory Safety**: No leaks, no dangling pointers, no double-frees
- **Exception Propagation**: Seamless error handling across FFI boundaries
- **Thread Safety**: Designed for concurrent access patterns

---

## 📦 Installation

### For Dart (Oche)
```bash
# Add to your pubspec.yaml
dependencies:
  ffi: ^2.0.0
```

### For Python (Porche)
```bash
# Install ctypes (usually included) and numpy (optional)
pip install numpy
```

---

## 🚀 Quick Start

### Nim Side
```nim
import oche  # or porche for Python

type User {.oche.} = object  # or {.porche.} for Python
  id: int
  name: string

proc createUser(id: int): User {.oche.} =  # or {.porche.}
  User(id: id, name: "User_" & $id)

generate("nlib.dart")  # or generatePython("nlib.py")
```

### Dart Side
```dart
import 'nlib.dart';

void main() async {
  final user = await oche.createUser(42);
  print('User: ${user.name}');  // User: User_42
}
```

### Python Side
```python
import nlib

user = nlib.porche.createUser(42)
print(f'User: {user["name"]}')  # User: User_42
```

---

## 📊 Benchmarks

See our comprehensive benchmarks comparing pure implementations vs Nim+Oche/Porche:

- **Monte Carlo Pi**: CPU-bound mathematical computation
- **Mandelbrot Fractal**: Complex graphics computation
- **N-Body Simulation**: Physics simulation with floating-point operations

Results show **2-5x performance improvements** for compute-intensive tasks while maintaining memory safety.

---

## 📚 Documentation

- **[Guide](GUIDE.md)**: Complete usage guide with examples and philosophy
- **[API Reference](GUIDE.md#api-reference)**: Detailed API documentation
- **[Benchmarks](src/benchmark/)**: Performance comparisons and methodology

---

## 🏗️ Architecture

Oche/Porche consists of three layers:

1. **Macro Layer (Nim)**: Transforms annotated code into FFI-compatible exports
2. **Shared Library**: Zero-copy memory sharing with unified ABI
3. **Generator Layer**: Auto-generates ergonomic bindings for target languages

---

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

Built with ❤️ using Nim's powerful macro system and modern language features.
    Active, Inactive, Pending

  Tag {.oche.} = object
    name: string
    id: int

  User {.oche.} = object
    username: string
    status: Status
    primaryTag: Tag
```
> **🧠 Behind The Curtains**: If a `string` is present inside a struct, Oche's macro will dynamically transform it into a `cstring` under the hood! This allows flawless Dart UTF-8 alignment natively while keeping Nim's strict type safety happy.

### 🔵 2. Functions & Strings (Nim)

When instantiating or assigning Strings manually to Structs exported to Dart, you **Must** use `toOcheStr("...")` to place the string accurately on the FFI-compliant Custom Heap. 

```nim
proc createUser(name: string, tagId: int): User {.oche.} =
  User(
    username: toOcheStr(name), # ⚠️ REQUIRED for Nested Strings!
    status: Active,
    primaryTag: Tag(name: toOcheStr("Tag_" & $tagId), id: tagId)
  )
```

In Dart, this is an instantaneous, ergonomic call:

```dart
final user = oche.createUser('JohnDoe', 42);
print("Hello ${user.username}"); // 'JohnDoe'
```

### 🟢 3. Snapshot / Copy Sequence (Nim -> Dart)

When you return a standard `seq[T]` in Nim, Oche will perform an **Ownership Handoff**. Dart's Garbage Collector handles the cleanup.

```nim
proc getPointsCopy(n: int): seq[Point] {.oche.} =
  for i in 0..<n: result.add(Point(x: i.float, y: i.float))
```

Dart Side:
```dart
final copied = oche.getPointsCopy(3);
print(copied[0].x); 
// Dart's GC automatically handles freeing via Finalizers!
```

### 🟣 4. View Mode (Zero-Copy Read Only)

If Nim owns massive data that lasts forever (e.g., globals, parsed game level maps) and you want Dart to just **peek** at it without cloning bytes:

```nim
var cachedPoints: seq[Point]
proc getPointsView(n: int): seq[Point] {.oche: view.} =
  cachedPoints = newSeq[Point](n)
  return cachedPoints
```
> By appending `{.oche: view.}`, Dart knows this `NativeListView` is read-only and *never* GC-deleted.

### 🔴 5. Shared Live Buffer (The FFI Holy Grail)

Want Nim to own memory, while Dart Mutates it live directly in RAM? Use `OcheBuffer[T]`.

```nim
var globalUsers: OcheBuffer[User]

proc initSharedUsers(n: int): OcheBuffer[User] {.oche.} =
  globalUsers = newOche[User](n)
  for i in 0..<n:
    globalUsers[i] = User(username: toOcheStr("User"), status: Pending, primaryTag: Tag(..))
  return globalUsers

proc printSharedUser() {.oche.} =
  echo "Live Data: ", globalUsers[0].username
```

In Dart:
```dart
final sharedUsers = oche.initSharedUsers(2);

// Live Mutation directly passing deep through NUser* pointer offsets
sharedUsers[0] = User(
  username: 'DartMaster',
  status: Status.Active,
  primaryTag: Tag(name: 'Hero', id: 999)
);

// Nim instantly sees 'DartMaster' in RAM!
oche.printSharedUser(); 
```
*(When Dart sets a whole new Struct on the array, Oche **auto-traces** the old Nested Strings, frees them natively in Nim (`_ocheFreeInner`), and injects the new references. Zero Memory Leak.)*

### ⚡ 6. The Native Accelerator (Advanced SIMD)

When dealing with extreme workloads (e.g., 4K Image Filters, N-Body Particle Physics, or 100M Collision Checks), Oche allows Nim to drop down to the lowest possible CPU level. 

By requesting the `.dataPtr` from an `OcheBuffer[T]`, you gain access to the raw unchecked C-Array. Nim's compiler (`-d:danger`) will automatically unroll the loop and apply **SIMD Vectorization**, effectively making your code run up to **7x faster** than Pure Dart.

```nim
var imgBuffer: OcheBuffer[Pixel]

proc processImageGrayscale() {.oche.} =
  let p = imgBuffer.dataPtr # Unleash raw pointer!
  let n = imgBuffer.len
  for i in 0 ..< n: # Runs at brutal C/C++ SIMD speeds
    p[i].r = 255
```
*(Tip: Combine this with Oche's support for `uint8` and `float32` primitives to densely pack your memory structs for game engines!)*

### 🔄 7. Asynchronous Execution (Isolates)

Oche generates **synchronous** FFI bindings by default to maximize sub-millisecond execution speeds with zero overhead. 

If your task is exceptionally heavy (like traversing 10,000,000 nodes or decoding 4K video) and threatens to drop frames on the Flutter UI thread, you should run the Oche call in the background using Dart 3's modern `Isolate.run()`:

```dart
// 1. Synchronous (Fastest, blocks Main Thread momentarily)
final energy = oche.nbodyNim(100000); 

// 2. Asynchronous (Background execution, UI remains perfectly smooth)
final asyncEnergy = await Isolate.run(() => oche.nbodyNim(100000));
```
*Because Oche manages data in Native C-RAM, passing these pointers across Dart Isolates causes practically zero serialization overhead!*

---

## 📝 Safety Overview & Best Practices
1. **Never forget `toOcheStr()`** for explicit String initialization into FFI Structs. 
2. `seq[T]` implies a `Copy` of ownership from Nim to Dart GC.
3. `seq[T] {.oche: view.}` implies Nim owns it, and Dart views it indefinitely.
4. `OcheBuffer[T]` implies Nim owns it, but Dart can dynamically read *and write* to it immediately via the `SharedListView` class in Dart.
5. Finish your Nim code by writing `generate("nlib.dart")` at the bottom to flush the bindings out!

**Welcome to the absolute fastest way to bridge Nim and Dart. Enjoy the speed. 🦅🏎️💨**
