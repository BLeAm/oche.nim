# Oche

Nim FFI codegen for Python and Dart. Write Nim procs once, get idiomatic bindings for both languages — with a memory-aware ownership model that supports zero-copy paths to numpy and Dart TypedData.

```nim
# olib.nim
proc dotProduct(a, b: OcheArray[float64]): float64 {.oche, porche.} =
  var sum = 0.0
  for i in 0..<min(a.len, b.len): sum += a[i] * b[i]
  sum

generate("olib.dart")
generatePython("olib.py")
```

```python
# Python — zero-copy from numpy
import numpy as np
from olib import porche

a = np.array([1.0, 2.0, 3.0, 4.0])
b = np.array([2.0, 3.0, 4.0, 5.0])
print(porche.dotProduct(a, b))  # 40.0
```

```dart
// Dart — zero-copy from TypedData
final a = Float64List.fromList([1.0, 2.0, 3.0, 4.0]);
final b = Float64List.fromList([2.0, 3.0, 4.0, 5.0]);
print(oche.dotProduct(a, b)); // 40.0
```

---

## Why Oche?

| | nimpy | ffigen | Oche |
|---|---|---|---|
| Target | Python only | Dart only (from C header) | Python + Dart |
| Source | Nim | C header | Nim |
| Memory model | copy | copy | copy / view / share |
| Zero-copy numpy/TypedData | ✗ | ✗ | ✓ |
| ABI mismatch detection | ✗ | ✗ | ✓ |

---

## Installation

Oche is a set of Nim source files — no package manager needed.

```
oche.nim        # main macro: {.oche.}, {.porche.}, generate(), generatePython()
oche_core.nim   # compile-time IR shared by both emitters
oche_dart.nim   # Dart FFI emitter
oche_python.nim # Python ctypes emitter
```

Copy all four files into your project (or a shared location on `--path`).

**Requirements:** Nim 2.x, standard library only.

---

## Quickstart

### 1. Write your Nim library

```nim
# mylib.nim
import oche
import std/options

type
  Color {.oche, porche.} = enum
    Red, Green, Blue

  Point {.oche, porche.} = object
    x: float64
    y: float64

proc makePoint(x, y: float64): Point {.oche, porche.} =
  Point(x: x, y: y)

proc addPoints(a, b: Point): Point {.oche, porche.} =
  Point(x: a.x + b.x, y: a.y + b.y)

# At the bottom — generates binding files at compile time
generate("mylib.dart")
generatePython("mylib.py")
```

### 2. Compile to shared library

```bash
nim c --app:lib --gc:arc -d:release mylib.nim
# produces: libmylib.so (Linux) / libmylib.dylib (macOS) / mylib.dll (Windows)
# and generates: mylib.dart, mylib.py
```

### 3. Use from Python

```python
from mylib import porche, Color

p = porche.makePoint(3.0, 4.0)
print(p.x, p.y)  # 3.0 4.0

p2 = porche.makePoint(1.0, 2.0)
p3 = porche.addPoints(p, p2)
print(p3.x)  # 4.0
```

### 4. Use from Dart

```dart
import 'mylib.dart';

void main() {
  final p = oche.makePoint(3.0, 4.0);
  print('${p.x} ${p.y}');  // 3.0 4.0

  final p2 = oche.makePoint(1.0, 2.0);
  final p3 = oche.addPoints(p, p2);
  print(p3.x);  // 4.0
}
```

---

## Pragma reference

### Types

```nim
type
  MyEnum {.oche, porche.} = enum   # export to Dart + Python
    A, B, C

  MyStruct {.oche, porche.} = object  # export struct layout
    x: float64
    name: string   # string fields become cstring in ABI, managed automatically
```

Use `{.oche.}` for Dart only, `{.porche.}` for Python only, or both for both targets.

### Procs — three return modes

```nim
# Copy mode (default): Nim allocates, foreign lang gets an owned copy
proc makeUser(name: string, age: int): User {.oche, porche.} = ...

# View mode: return points into Nim-managed memory — no copy, no ownership transfer
# Caller must not hold reference longer than the Nim-side data lives
proc getPointsView(): seq[Point] {.oche: view, porche: view.} = ...

# Share mode: return OcheBuffer — Nim-allocated heap block, caller calls .free()
proc makeIntBuffer(n: int): OcheBuffer[int] {.oche, porche.} = ...
```

---

## Ownership model

Oche has three types for crossing the language boundary, each with distinct ownership semantics:

### `OcheBuffer[T]` — Nim owns, caller holds reference

Nim allocates a contiguous block with a 16-byte header (`len int64`, `typeId int32`, `flags int32`) followed by element data. The foreign language receives a `SharedListView` (Dart) or `SharedListView` (Python) that wraps this pointer.

**Caller is responsible for calling `.free()`** when done. A Dart `Finalizer` is registered as a safety net but `.free()` should be called explicitly for deterministic cleanup.

```nim
proc makeParticles(n: int): OcheBuffer[Particle] {.oche, porche.} =
  var buf = newOche[Particle](n)
  for i in 0..<n: buf[i] = Particle(x: float64(i), ...)
  buf
```

```python
buf = porche.makeParticles(100)
print(buf[0].x)
arr = buf.to_numpy()   # zero-copy view for POD types
buf.free()
```

**Memory layout:**
```
offset 0   int64   length (number of elements)
offset 8   int32   typeId (used by ocheFreeDeep for non-POD cleanup)
offset 12  int32   flags
offset 16  T[]     element data
```

### `OcheArray[T]` — caller owns, Nim reads

Used for input parameters where the caller has an existing contiguous buffer (numpy array, Dart TypedData). Nim receives a pointer + length, never copies, never frees.

```nim
proc dotProduct(a, b: OcheArray[float64]): float64 {.oche, porche.} =
  var sum = 0.0
  for i in 0..<min(a.len, b.len): sum += a[i] * b[i]
  sum
```

Python: pass `numpy.ndarray` or `array.array`  
Dart: pass `Float64List`, `Int64List`, etc.

### `OchePtr[T]` — caller owns native memory, true zero-copy

For cases where the caller allocates with `malloc`/`calloc` and manages lifetime entirely. No length metadata on the wire — caller passes `len` as a separate parameter.

```nim
proc sumIntsPtr(arr: OchePtr[int]): int {.oche, porche.} =
  var total = 0
  for v in arr: total += v
  total
```

Python: pass `numpy.ndarray` or `ctypes` pointer  
Dart: pass `ffi.Pointer<ffi.Int64>` (from `calloc`)

---

## Type mapping

| Nim | Python | Dart |
|-----|--------|------|
| `int` / `int64` | `int` | `int` |
| `float64` | `float` | `double` |
| `float32` | `float` | `double` |
| `bool` | `bool` | `bool` |
| `string` | `str` | `String` |
| `enum` | `IntEnum` subclass | `enum` |
| `object` | class with fields | class + NativeStruct |
| `seq[T]` (copy) | `List[T]` | `List<T>` |
| `seq[T]` (view) | `NativeListView[T]` | `NativeListView<T>` |
| `OcheBuffer[T]` | `SharedListView[T]` | `SharedListView<T>` |
| `OcheArray[T]` | `numpy.ndarray` / `array` | `TypedData` |
| `OchePtr[T]` | `numpy.ndarray` / ctypes ptr | `ffi.Pointer<T>` |
| `Option[T]` | `T \| None` | `T?` |

---

## Error handling

Exceptions raised in Nim are caught at the FFI boundary and stored in a thread-local error slot. The generated binding checks this slot after every call and raises in the host language.

```nim
proc riskyDivide(a, b: int): int {.oche, porche.} =
  if b == 0: raise newException(ValueError, "division by zero")
  a div b
```

```python
try:
    porche.riskyDivide(1, 0)
except RuntimeError as e:
    print(e)  # NimError: division by zero
```

```dart
try {
  oche.riskyDivide(1, 0);
} catch (e) {
  print(e);  // NimError: division by zero
}
```

> **Note:** The exception type is not currently propagated — the host language always sees `RuntimeError` (Python) or a generic exception (Dart). The original message is preserved.

---

## ABI safety

Oche embeds a hash of all exported struct layouts and proc signatures at compile time (`ocheAbiHash`). When the generated binding is imported, it checks that the loaded `.so` hash matches. A mismatch means the library was recompiled without regenerating the bindings.

```
RuntimeError: Oche ABI mismatch: .so was compiled with hash 'a1b2c3d4'
but bindings expect 'deadbeef'. Recompile Nim and regenerate bindings.
```

---

## numpy integration (Python)

For POD types (no string fields), `SharedListView` and `NativeListView` expose `.to_numpy()` which returns a zero-copy `numpy.ndarray` view over the Nim buffer.

```python
buf = porche.makeParticles(1000)
arr = buf.to_numpy()      # dtype matches Particle struct layout
print(arr['x'][0])        # field access by name
arr['x'] *= 2.0           # mutate in place — writes through to Nim memory
buf.free()
```

`to_numpy()` returns `None` for non-POD types (structs with string fields).

---

## Scope and non-goals

Oche is an **in-process FFI binding generator**. It is not:

- A serialization format (not Arrow, not Flatbuffers)
- A concurrency primitive — thread safety is the caller's responsibility
- A cross-process or cross-machine protocol

The memory model is intentionally simple: one allocator (Nim's), one process, explicit ownership. Concurrency across Dart Isolates or Python threads sharing the same buffer is undefined behavior unless the caller provides external synchronization.

---

## Running the tests

```bash
# compile
nim c --app:lib --gc:arc -d:release olib.nim

# Python
python orun.py

# Dart
dart pub add ffi        # one-time
dart run orun.dart
```

Expected: `128/128 passed` (Python), `97/97 passed` (Dart).

---

## Known limitations

- No callback/closure support — cannot pass Python/Dart lambdas to Nim
- Exception type is not propagated, only the message
- `NativeListView` negative indexing is supported in Python but not yet in Dart
- No JS/WASM emitter
- Thread safety is the caller's responsibility (by design — see Scope)
