# Oche

Nim FFI codegen for Python and Dart. Write Nim procs once, get idiomatic bindings for both languages — with a memory-aware ownership model that supports zero-copy paths to numpy and Dart TypedData.

```nim
# olib.nim
import oche

proc dotProduct(a, b: OcheArray[float64]): float64 {.oche.} =
  var sum = 0.0
  for i in 0..<min(a.len, b.len): sum += a.dataPtr[i] * b.dataPtr[i]
  sum

generate()
```

```python
# Python — zero-copy from numpy
import numpy as np
from olib import oche

a = np.array([1.0, 2.0, 3.0, 4.0])
b = np.array([2.0, 3.0, 4.0, 5.0])
print(oche.dotProduct(a, b))  # 40.0
```

```dart
// Dart — one memcpy from TypedData
import 'olib.dart';

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
oche.nim        # main macro: {.oche.}, generate()
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
  Color {.oche.} = enum
    Red, Green, Blue

  Point {.oche.} = object
    x: float64
    y: float64

proc makePoint(x, y: float64): Point {.oche.} =
  Point(x: x, y: y)

proc addPoints(a, b: Point): Point {.oche.} =
  Point(x: a.x + b.x, y: a.y + b.y)

# At the bottom — generates binding files at compile time
generate()
```

### 2. Compile to shared library

```bash
nim c --app:lib --gc:arc -d:release mylib.nim
# produces: libmylib.so (Linux) / libmylib.dylib (macOS) / mylib.dll (Windows)
# and generates: mylib.dart, mylib.py
```

### 3. Use from Python

```python
from mylib import oche, Color

p = oche.makePoint(3.0, 4.0)
print(p.x, p.y)  # 3.0 4.0

p2 = oche.makePoint(1.0, 2.0)
p3 = oche.addPoints(p, p2)
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

## generate()

```nim
generate()                              # emit <stem>.dart and <stem>.py (auto-named)
generate(dart="path/api.dart")          # Dart only
generate(python="path/api.py")          # Python only
generate(dart="a.dart", python="b.py")  # both, custom paths
```

Call once at the bottom of the file after all `{.oche.}` annotations.
The filename stem is derived from the callsite source file (`olib.nim` → `olib.dart` + `olib.py`).

---

## Pragma reference

### Types

```nim
type
  MyEnum {.oche.} = enum   # export to all targets (Dart + Python)
    A, B, C

  MyStruct {.oche.} = object
    x: float64
    name: string   # string fields become cstring in ABI, managed automatically
```

### Procs — three return modes

```nim
# Copy mode (default): Nim allocates, foreign side gets an owned copy
proc makeUser(name: string, age: int): User {.oche.} = ...

# View mode: return points into Nim-managed memory — no copy, no ownership transfer
proc getPointsView(): seq[Point] {.oche: view.} = ...

# Share mode: return OcheBuffer — Nim-allocated heap block, caller calls .free()
proc makeIntBuffer(n: int): OcheBuffer[int] {.oche.} = ...
```

---

## Ownership model

Oche has three types for crossing the language boundary, each with distinct ownership semantics:

### `OcheBuffer[T]` — Nim owns, caller holds reference

Nim allocates a contiguous block with a 16-byte header (`len int64`, `typeId int32`, `flags int32`) followed by element data. The foreign language receives a `SharedListView` that wraps this pointer.

**Caller is responsible for calling `.free()`** when done. A Dart `Finalizer` and Python `__del__` are registered as safety nets but `.free()` should be called explicitly for deterministic cleanup.

```nim
proc makeParticles(n: int): OcheBuffer[Particle] {.oche.} =
  result = newOche[Particle](n)
  for i in 0..<n: result[i] = Particle(x: float64(i))
```

```python
buf = oche.makeParticles(100)
arr = buf.to_numpy()   # zero-copy view for POD types
arr['x'] *= 2.0        # writes directly into Nim memory
buf.free()
```

```dart
final buf = oche.makeParticles(100);
final arr = buf.toFloat64List()!;  // zero-copy typed view
arr[0] = 99.0;
buf.free();
```

**Memory layout:**
```
offset 0   int64   length (number of elements)
offset 8   int32   typeId (used by ocheFreeDeep for non-POD cleanup)
offset 12  int32   flags
offset 16  T[]     element data
```

### `OcheArray[T]` — caller owns, Nim reads

Used for input parameters where the caller has an existing contiguous buffer.
Nim receives `ptr + len` — the emitter injects `len` automatically, so the caller
just passes the array.

```nim
proc multiTwo(a: OcheArray[int]) {.oche.} =
  for i in 0..<a.len:
    a.dataPtr[i] *= 2   # .dataPtr = ptr UncheckedArray[T], compiler-visible for SIMD
```

```python
oche.multiTwo(narr)           # pass numpy array — len injected automatically
```

```dart
oche.multiTwo(Int64List.fromList([1, 2, 3]));  // one memcpy, then pointer to Nim
```

**Nim-side access:**
- `a.len` — number of elements (injected by emitter from caller)
- `a.dataPtr` — `ptr UncheckedArray[T]`, use for tight loops (compiler can vectorize)
- `a[i]` — bounds-checked read (returns value, not var — use `a.dataPtr[i]` to mutate)

### `OchePtr[T]` — caller owns native memory, true zero-copy in Dart

Same wire format as `OcheArray` (`ptr + len`) and the Nim proc signature is also
identical — neither type needs an explicit `len` parameter in Nim. The distinction
is entirely in how the **Dart emitter** handles memory before the call.

`OcheArray` in Dart performs a C-level memcpy into an arena buffer before calling Nim
— necessary because Dart's VM is a moving GC and TypedData pointers can be relocated
mid-call. `OchePtr` skips this: caller allocates via `calloc` (outside VM heap), so
the pointer is stable and goes directly to Nim. Because `ffi.Pointer<T>` has no
`.length`, the Dart caller must pass `len` explicitly.

```nim
proc sumIntsPtr(p: OchePtr[int]): int {.oche.} =
  for i in 0..<p.len: result += p.dataPtr[i]  # .len available, same as OcheArray
```

```python
oche.sumIntsPtr(narr)   # same as OcheArray — len injected automatically
```

```dart
final buf = calloc<ffi.Int64>(5);
oche.sumIntsPtr(buf, 5);   // len required — calloc pointer has no .length
calloc.free(buf);
```

**When to use `OchePtr` over `OcheArray`:**
Only when the buffer is large enough that a memcpy per call is unacceptable, or when
Dart and Nim need to share memory and see each other's mutations real-time. In Python
there is no practical difference between the two.

---

## Type mapping

| Nim | Python | Dart |
|-----|--------|------|
| `int` / `int64` | `int` | `int` |
| `float64` | `float` | `double` |
| `float32` | `float` | `double` |
| `bool` | `bool` | `bool` |
| `string` | `str` | `String` |
| `enum` | class with int attrs | `enum` |
| `object` | `Xxx` / `XxxView` | `Xxx` / `XxxView` |
| `seq[T]` (copy) | `List[T]` | `List<T>` |
| `seq[T]` (view) | `NativeListView` | `NativeListView<T>` |
| `OcheBuffer[T]` | `SharedListView` | `SharedListView<T>` |
| `OcheArray[T]` | `numpy.ndarray` / `array` | `TypedData` (one memcpy) |
| `OchePtr[T]` | `numpy.ndarray` / ctypes ptr | `ffi.Pointer<T>` (zero-copy) |
| `Option[T]` | `T \| None` | `T?` |

---

## Error handling

Exceptions raised in Nim are caught at the FFI boundary and re-raised in the host language.

```nim
proc riskyDivide(a, b: int): int {.oche.} =
  if b == 0: raise newException(ValueError, "division by zero")
  a div b
```

```python
try:
    oche.riskyDivide(1, 0)
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

> **Note:** The exception type is not propagated — the host language always sees `RuntimeError` (Python) or a generic `Exception` (Dart). The original message is preserved.

---

## ABI safety

Oche embeds a hash of all exported struct layouts and proc signatures at compile time.
When the generated binding is loaded, it compares against the hash exported by the `.so`.
A mismatch means the library was recompiled without regenerating the bindings.

```
RuntimeError: Oche ABI mismatch: .so was compiled with hash 'a1b2c3d4'
but bindings expect 'deadbeef'. Recompile Nim and regenerate bindings.
```

---

## numpy integration (Python)

For POD types (no string fields), `SharedListView.to_numpy()` returns a zero-copy
writable `numpy.ndarray` view over Nim memory.

```python
buf = oche.makeParticles(1000)
arr = buf.to_numpy()      # dtype matches Particle struct layout
arr['x'] *= 2.0           # mutates Nim memory directly — no copy
buf[0].x                  # sees the numpy mutation
buf.free()
```

`to_numpy()` returns `None` for non-POD types (structs with string fields).

---

## TypedData integration (Dart)

For primitive `OcheBuffer` types, Oche generates a **typed extension method** on the
`SharedListView` returned by each proc — no casting required:

```dart
final buf = oche.makeIntBuffer(6);
final arr = buf.toInt64List()!;  // typed_data.Int64List — compile-time safe

arr[5] = 777;    // writes into Nim memory
buf[5];          // returns 777
buf.free();
```

The method name matches the Dart typed list: `toInt64List()`, `toFloat64List()`,
`toInt32List()`, etc. For struct buffers no typed method is generated.

---

## Running the tests

```bash
# compile
nim c --app:lib --gc:arc -d:release --passC:"-march=native" olib.nim

# Python (128 tests)
python orun.py

# Dart (121 tests)
dart pub add ffi   # one-time
dart run orun.dart
```

---

## Known limitations

- No callback/closure support — cannot pass Python/Dart lambdas to Nim
- Exception type is not propagated, only the message
- `NativeListView` in Dart has no native negative indexing (Python supports `view[-1]`)
- No JS/WASM emitter
- Thread safety is the caller's responsibility (by design)