# Oche — Comprehensive Guide

> This document explains every concept in Oche from first principles:
> why each design decision was made, how it works internally, and when
> to use each feature. Written for the author (and future readers) who
> want to understand the system deeply, not just use it.

---

## Table of Contents

1. [What Oche is and isn't](#1-what-oche-is-and-isnt)
2. [How codegen works](#2-how-codegen-works)
3. [Pragma reference](#3-pragma-reference)
4. [The three return modes](#4-the-three-return-modes)
5. [The three input types](#5-the-three-input-types)
6. [OcheBuffer vs OcheArray vs OchePtr — the full picture](#6-ochebuffer-vs-ochearray-vs-ocheptr--the-full-picture)
7. [Struct handling](#7-struct-handling)
8. [Enums](#8-enums)
9. [Strings](#9-strings)
10. [Option return](#10-option-return)
11. [Error handling](#11-error-handling)
12. [Memory management in detail](#12-memory-management-in-detail)
13. [ABI safety](#13-abi-safety)
14. [numpy integration (Python)](#14-numpy-integration-python)
15. [TypedData integration (Dart)](#15-typeddata-integration-dart)
16. [What Oche does not solve](#16-what-oche-does-not-solve)
17. [Known limitations](#17-known-limitations)

---

## 1. What Oche is and isn't

Oche is an **in-process FFI binding generator**. You write Nim procs and types,
annotate them with pragmas, call `generate()` at the bottom of the file,
and Oche emits `.dart` and `.py` binding files at compile
time. The output files wrap a compiled `.so` / `.dylib` / `.dll` and expose
every annotated proc as a native method.

**What it is:**
- A compile-time macro that reads Nim type information and emits glue code
- A memory layout protocol so Python and Dart can read/write Nim-allocated
  memory without copying (for view and share modes)
- A thin ownership model: three levels, each with clear rules about who
  allocates and who frees

**What it is not:**
- A serialization format (no schema evolution, no IPC, no cross-process)
- A concurrency primitive — thread safety is 100% the caller's responsibility
- A cross-machine protocol
- A replacement for Arrow, Flatbuffers, or Cap'n Proto (different problem)

The scope is intentionally narrow: **one process, one allocator (Nim's), two
foreign language frontends**.

---

## 2. How codegen works

At compile time, Nim's macro system runs and builds an internal IR (Intermediate
Representation) of everything annotated with `{.oche.}` or `{.oche.}`.

The IR lives in two compile-time tables in `oche_core.nim`:

```
structBanks   Table[string, OcheStruct]   # all annotated object types
enumBanks     Table[string, OcheEnum]     # all annotated enum types
ooBanks       seq[OcheObject]             # procs for both Dart and Python
ooBanksPython seq[OcheObject]             # mirror of ooBanks (same contents)
```

When you call `generate()`, the macro walks these tables and emits binding
files as strings written to disk. It also injects several helper procs into
the compiled `.so`:

| Exported symbol | Purpose |
|---|---|
| `ocheFree(p)` | free a single heap block |
| `ocheFreeDeep(p)` | free a buffer + inner strings (non-POD) |
| `ocheFreeInner(p, typeId)` | free only inner strings of one element |
| `ocheStrAlloc(s)` | allocate a heap copy of a cstring |
| `ocheStrFree(p)` | free a heap cstring |
| `ocheGetError()` | retrieve and clear the last Nim exception message |
| `ocheAbiHash()` | return the ABI fingerprint for this compilation |
| `ocheAllocBytes(n)` | allocate n bytes (used by Python for struct packing) |

These are the only symbols the generated bindings depend on, plus the
user-defined proc names.

---

## 3. Pragma reference

### On types

```nim
type
  MyEnum {.oche.} = enum   # register for all targets
  MyPoint {.oche.} = object
    x: float64
    y: float64
```

Same syntax for `object` types. The pragma must appear on the type definition
itself. Types that are used in annotated procs but are not themselves annotated
will still be exported (they are registered in structBanks when the proc is
processed), but it is cleaner to annotate them explicitly.

### On procs

```nim
proc myProc(...) {.oche.}           # export to all targets (Dart + Python)
proc myProc(...): seq[T] {.oche: view.}  # view mode — zero-copy seq return
```

The pragma value (`:view`) controls the return mode for seq returns.
For non-seq returns the value is ignored. See section 4 for details.

### generate()

```nim
generate()                              # emit <stem>.dart and <stem>.py
generate(dart="path/api.dart")          # Dart only
generate(python="path/api.py")          # Python only
generate(dart="a.dart", python="b.py")  # both, custom paths
```

Call once at the bottom of the file after all `{.oche.}` annotations.
The filename stem (e.g. `olib` from `olib.nim`) is used for auto-naming when
a target is not explicitly disabled.

---

## 4. The three return modes

Every annotated proc returns data in one of three modes. The mode is determined
by the return type and the pragma value.

### Copy mode (default)

```nim
proc makeUser(name: string, age: int): User {.oche.}
proc makePointList(n: int): seq[Point] {.oche.}
```

Nim computes the result, then **copies all data** into a heap block that is
transferred to the foreign language. The foreign side owns the memory and is
responsible for freeing it (for structs this happens automatically via
Python's `__del__` or Dart's GC; for seq/buffers the caller calls `.free()`).

**When to use:** When the result is small, or when the foreign side needs to
hold it longer than the Nim-side data would live.

**Python result types:**
- Primitive (`int`, `float`, `bool`, `string`) → plain Python value
- `struct` → `User` (plain Python class, GC-owned, no manual free needed)
- `seq[struct]` → `List[User]` (list of plain Python objects, GC-owned)
- `seq[int]` → `List[int]`

**Dart result types:**
- Primitive → Dart value
- `struct` → `User` (Dart class, GC-owned)
- `seq[struct]` → `List<User>`

### View mode

```nim
proc getPointsView(): seq[Point] {.oche: view.}
```

Nim returns a **pointer into its own memory** — no copy. The foreign side
gets a `NativeListView` that reads directly from Nim RAM.

**Rules:**
- Read-only: `view[i] = x` raises an error
- The Nim-side data must outlive the view — if the Nim global is reassigned
  or goes out of scope, the view becomes a dangling pointer
- Typically used when Nim owns a persistent global seq that is updated and
  re-exposed

**Python result type:** `NativeListView`
- Supports `len()`, `[i]`, `[-1]`, `[a:b]`, `for x in view`, `reversed()`
- `.freeze()` on an element returns a plain Python copy of that element
- `.to_numpy()` for POD types (returns a **copy** — view mode data can be
  freed at any time, so numpy gets a snapshot)

**Dart result type:** `NativeListView<PointView>`
- Supports `length`, `[i]`, `for` loop, `.freeze()`
- No negative indexing in Dart (Python supports it)

**View mode on a single struct return:**
If you write `{.oche: view.}` on a proc that returns a single struct (not seq),
Oche downgrades it to copy mode automatically and emits a compile-time warning.
A single struct is stack-allocated in Nim — returning a pointer to it would be
a dangling pointer immediately.

### Share mode (OcheBuffer return)

```nim
proc makeIntBuffer(n: int): OcheBuffer[int] {.oche.}
proc makeParticles(n: int): OcheBuffer[Particle] {.oche.}
```

Nim allocates a heap block with a 16-byte header followed by the element data.
The foreign side gets a `SharedListView` that wraps a pointer to this block.
**Both sides can read and write the same memory.** No copy happens.

**Memory layout of the block:**
```
offset  0  int64   number of elements (len)
offset  8  int32   typeId (which struct type, used by ocheFreeDeep)
offset 12  int32   flags (reserved)
offset 16  T[]     element data, tightly packed
```

**Rules:**
- Caller **must** call `.free()` when done (or use Python's `with` statement)
- Nim must keep the Nim-side `OcheBuffer` variable alive (in a global or field)
  for as long as the foreign side holds the `SharedListView`
- Both sides can mutate: Nim via `buf[i] = val`, Python/Dart via `slv[i] = val`

**Python result type:** `SharedListView`
- Supports `len()`, `[i]`, `[i] = v`, `[-1]`, `[a:b]`, `[a:b] = vals`
- `.free()` — explicit free (preferred)
- `__del__` — GC safety net (do not rely on this for timing)
- `with oche.makeIntBuffer(n) as buf:` — context manager
- `.to_numpy()` — zero-copy writable numpy view into Nim RAM (POD only)
- `.freeze()` on element — deep copy to Python-owned object

**Dart result type:** `SharedListView<T>`
- Supports `length`, `[i]`, `[i] = v`
- `.free()` — explicit free
- `Finalizer` registered as safety net
- `.toTypedData()` — zero-copy view as Int64List/Float64List etc.
- `.freeze()` on element — deep copy to Dart-owned object

---

## 5. The three input types

These types are used for **parameters**, not return values. They control
how the foreign language passes array data to Nim.

### `seq[T]` parameter

```nim
proc sumSeq(values: seq[int]): int {.oche.}
```

The foreign side passes a Python list or Dart `List`. Oche allocates a
temporary C array, copies the elements in, calls Nim, then frees the temp
array. This is the most convenient option but involves a copy.

**Python:** accepts `list`, `numpy.ndarray` (fast path, zero-copy if dtype
matches), or `array.array` (fast path via buffer protocol)

**Dart:** allocates arena, copies via `_packInto`

### `OcheArray[T]` parameter

```nim
proc dotProduct(a, b: OcheArray[float64]): float64 {.oche.}
```

Designed for **numeric arrays that already exist as contiguous buffers**.
Nim receives `ptr + len`, never copies, never frees.

**Python behaviour:**
- `numpy.ndarray` → true zero-copy (pointer grabbed directly from numpy buffer)
- `array.array` → zero-copy via buffer protocol
- plain `list` → **raises TypeError** (OcheArray requires a contiguous buffer)

**Dart behaviour:**
- TypedData (`Float64List`, `Int64List`, etc.) → **single memcpy** into arena-
  allocated native memory, then pointer passed to Nim. Not truly zero-copy in
  Dart because Dart VM GC may move managed heap objects — the memcpy "pins" the
  data before the FFI call.

**When to use over seq[T]:**
When the caller already has a numpy array or TypedData and you want to avoid
constructing a Python list just to pass it in. For Python this gives genuine
zero-copy. For Dart it gives one fast C-level memcpy instead of a per-element
Dart loop.

### `OchePtr[T]` parameter

```nim
proc sumIntsPtr(arr: OchePtr[int]): int {.oche.}
proc negateIntsPtr(arr: OchePtr[int]): OcheBuffer[int] {.oche.}
```

True zero-copy in both Python and Dart. Caller must provide memory that
lives **outside** the VM managed heap.

**Python behaviour:**
- `numpy.ndarray` → zero-copy (same as OcheArray)
- `ctypes.Array` or `ctypes.POINTER` → zero-copy, pointer passed directly
- `array.array` → zero-copy via buffer protocol

**Dart behaviour:**
- `ffi.Pointer<T>` allocated with `calloc` → zero-copy, pointer passed directly
  (no arena, no memcpy — this is the only path to true zero-copy in Dart)

**When to use over OcheArray:**
Only when you need true zero-copy in Dart. The cost is that the Dart caller
must manage `calloc` memory manually, and the Nim proc must accept `len` as a
separate explicit parameter. In Python the performance difference between
OcheArray and OchePtr is negligible — both give zero-copy with numpy.

**Default recommendation:** use `OcheArray` unless you specifically need Dart
zero-copy or C interop without a length concept. `OcheArray` is strictly more
convenient: `.len` is free, caller API is simpler, and Dart callers do not need
`calloc`.

---

## 6. OcheBuffer vs OcheArray vs OchePtr — the full picture

This section answers the question: "which one do I use?"

### On the wire (what gets passed to Nim)

| Type | Wire format | Values |
|------|------------|--------|
| `OcheBuffer[T]` as param | `void*` (single pointer to header block) | pointer to 16-byte header + data |
| `OcheBuffer[T]` as return | `void*` (pointer returned from Nim) | same layout |
| `OcheArray[T]` | `ptr T, int64 len` (two args) | pointer to element 0, count |
| `OchePtr[T]` | `ptr T, int64 len` (two args) | pointer to element 0, count |

OcheArray and OchePtr are **identical on the wire**. The distinctions exist
only in the emitter and in what the caller can pass:

- **OcheArray**: emitter injects `len` automatically from the array object.
  Nim receives `ptr + len` and reconstructs `OcheArray[T]` with `.data` and
  `.len` accessible. Caller never manually passes a length argument.
- **OchePtr**: emitter does NOT inject `len`. Nim must declare `len` as an
  explicit separate parameter. Caller must pass it manually.

```nim
# OcheArray — caller passes array only, len is injected automatically
proc multiTwo(a: OcheArray[int]) {.oche.} =
  for i in 0..<a.len:      # .len is available — injected by emitter
    a.dataPtr[i] *= 2     # .dataPtr is ptr UncheckedArray[T], mutable via pointer

# OchePtr — caller must pass len explicitly
proc sumIntsPtr(p: OchePtr[int], n: int) {.oche.} =
  let arr = cast[ptr UncheckedArray[int]](p)
  for i in 0..<n: result += arr[i]
```

```python
# Python callers:
oche.multiTwo(narr)           # OcheArray — just the array
oche.sumIntsPtr(narr, len(narr))  # OchePtr — must pass len too
```

### Ownership matrix

| | Who allocates | Who frees | Can be return type | Can be param type |
|---|---|---|---|---|
| Copy mode | Nim (copies to heap) | foreign side (GC or .free()) | ✓ | — |
| View mode | Nim (existing memory) | nobody (Nim owns) | ✓ | — |
| `OcheBuffer` | Nim | foreign side (.free()) | ✓ primary | ✓ (pass existing buf) |
| `OcheArray` | foreign side | foreign side | ✗ | ✓ primary |
| `OchePtr` | foreign side (calloc) | foreign side (calloc.free) | ✗ | ✓ (zero-copy Dart) |

### Decision guide

```
Do you need Nim to allocate the array?
  YES → OcheBuffer (return type)
  NO  → you have an existing array to pass in:
          Is Python zero-copy enough and Dart one-memcpy OK?
            YES → OcheArray (simpler for Dart callers)
          Do you need true zero-copy in Dart too?
            YES → OchePtr (caller uses calloc in Dart)
```

### The Python near-equivalence of OcheArray and OchePtr

In Python both types accept numpy arrays and both are zero-copy. The only
practical difference is:
- `OchePtr` also accepts `ctypes.POINTER` and `ctypes.Array` directly
- `OcheArray` rejects plain Python lists (raises TypeError)
- `OchePtr` rejects plain Python lists too

If your proc will only ever be called from Python with numpy, it does not
matter much which you pick. Pick `OcheArray` for clarity unless you
specifically want the ctypes pointer path or need zero-copy in Dart.

---

## 7. Struct handling

### POD vs non-POD

Oche classifies each struct at compile time:

- **POD** (Plain Old Data): all fields are numeric types, bools, enums, or
  nested POD structs. No strings.
- **non-POD**: has at least one `string` field, or a nested non-POD struct.

This matters for:
- `to_numpy()` — available only for POD types
- Memory layout — non-POD structs contain `cstring` (pointer) fields, so
  their layout is not directly mappable to a numpy dtype
- `ocheFreeDeep` — must walk the buffer and free each string before
  freeing the block

### Declaring a struct

```nim
type
  Point {.oche.} = object
    x: float64
    y: float64

  User {.oche.} = object
    name: string   # becomes cstring in the ABI
    age:  int
    status: Status
```

`string` fields are silently converted to `cstring` in the compiled struct
layout. Oche generates `XxxView` classes in Python and Dart that wrap the
raw pointer and decode strings on field access.

### Two struct representations in Python

For every struct `Xxx`, the Python binding has **two classes**:

**`XxxView`** — zero-copy, wraps a raw address
- Field reads go directly to Nim memory via ctypes
- Field writes go directly to Nim memory
- `.freeze()` → returns `Xxx` (deep copy into Python-owned object)
- Used in view mode, share mode, and as input params

**`Xxx`** — plain Python class, Python-owned
- Returned from copy-mode procs
- Fields are regular Python attributes, no FFI involved
- When passed as an input param, Oche packs it into a ctypes struct first

### Two struct representations in Dart

**`XxxView`** — wraps `ffi.Pointer<NXxx>`
- Field reads/writes go through FFI struct accessors
- `.freeze()` → returns `Xxx` (Dart-owned object)

**`Xxx`** — plain Dart class
- Returned from copy-mode procs

### Nested structs

```nim
type
  Tagged {.oche.} = object
    point: Point   # inline — not a pointer
    label: string
```

Nested structs are embedded inline (not pointed to). The `Tagged_t` ctypes
struct will have a `Point_t` field at the correct offset. Accessing
`tagged_view.point` returns a `PointView` pointed at the inline memory.

---

## 8. Enums

```nim
type
  Color {.oche.} = enum
    Red, Green, Blue
```

Enums are compiled with `{.size: 4.}` — always 32-bit int on the wire.
The Nim values (0, 1, 2, ...) map directly.

**Python:** `Color` is a plain class with class attributes `Red = 0`, `Green = 1`, etc. Not a proper Python `IntEnum` — comparisons use `==` on integers.

**Dart:** `Color` is a Dart `enum`. The generated code uses `.index` for the
wire value and `Color.values[raw]` to decode.

---

## 9. Strings

`string` parameters and return values cross the FFI boundary as null-terminated
C strings (`cstring`/`char*`). Oche handles allocation on both sides.

### Input strings (param)

```nim
proc greetUser(u: User): string {.oche.}
# User.name is a string field
```

When passing a struct with string fields, the generated code calls
`ocheStrAlloc(s)` to create a Nim-heap copy of each string. The copy is freed
when `ocheFreeDeep` runs on the result or when the struct's lifetime ends.

### Return strings

```nim
proc echoStr(s: string): string {.oche.}
```

Nim returns a Nim-heap copy of the string (`toOcheStr`). The generated binding
reads it, decodes to a Python `str` / Dart `String`, then calls `ocheFree` on
the raw pointer. The foreign side only ever sees a decoded string value.

### The `toOcheStr` helper

```nim
proc makeUser(name: string, age: int): User {.oche.} =
  User(name: name.toOcheStr, age: age, status: Active)
```

`toOcheStr` allocates a Nim-heap copy of the string and returns a `cstring`.
This is necessary because the foreign side will hold a pointer to this string
after the proc returns. **You must use `toOcheStr` for every string field in a
returned struct.** If you assign a Nim `string` directly, the pointer will
become invalid when the string's memory is reclaimed.

---

## 10. Option return

```nim
proc maybePoint(give: bool): Option[Point] {.oche.}
proc maybeUser(name: string): Option[User] {.oche.}
```

`Option[T]` maps to nullable in both targets:
- Python: `T | None`
- Dart: `T?`

On the wire Oche uses a null pointer to signal `none`. The generated code
checks for null before decoding.

---

## 11. Error handling

Any exception raised in a Nim proc is caught at the FFI boundary:

```nim
var lastOcheError {.threadvar.}: string

# inside the generated FFI wrapper:
try:
  # ... your proc body ...
except Exception as e:
  lastOcheError = e.msg
  return default(ReturnType)
```

The foreign side calls `ocheGetError()` after every FFI call. If a message
is waiting, it raises in the host language.

**Python:** raises `RuntimeError("NimError: " + message)`  
**Dart:** throws a Dart `Exception` with the same message

**Current limitation:** the exception *type* is not propagated, only the
message string. Both targets always raise a generic error type. The original
message is preserved verbatim.

---

## 12. Memory management in detail

### The four free functions

`ocheFree(p)` — raw dealloc. Used for:
- Standalone string return values (after decoding)
- Single copy-mode struct returns (after unpacking fields)

`ocheFreeDeep(p)` — buffer-aware dealloc. Used for:
- `OcheBuffer` (SharedListView) cleanup: walks every element and frees inner
  strings if typeId matches a non-POD struct, then frees the block
- NativeListView cleanup (view mode seq): frees the Nim-side wrapper block
  (not the pointed-to data, which Nim owns separately)

`ocheFreeInner(p, typeId)` — frees only the inner strings of one element at
address `p`. Used when mutating a non-POD element in a SharedListView
(must free old strings before writing new ones).

`ocheStrFree(p)` — frees a single Nim-heap string pointer.

### Lifetime rules for Nim globals

In view mode and share mode, Nim-side data must stay alive as long as the
foreign side holds a reference. The standard pattern is a module-level global:

```nim
var gPoints: seq[Point]  # keeps the seq alive

proc getPointsView(): seq[Point] {.oche: view.} =
  gPoints = @[Point(x: 1.0, y: 2.0), ...]
  gPoints  # returns pointer into gPoints
```

If `gPoints` is reassigned (e.g. by calling `getPointsView` again), any
existing `NativeListView` on the foreign side becomes a dangling pointer.
This is a correctness issue Oche cannot solve — it is the caller's
responsibility to ensure the view is not used after the backing data changes.

### Python context manager

```python
with oche.makeIntBuffer(100) as buf:
    buf[0] = 42
    process(buf)
# buf.free() called automatically here
```

`.free()` is idempotent — calling it twice is safe.

---

## 13. ABI safety

Every time you compile, Oche computes a hash of all exported struct layouts and
proc signatures:

```
S:Point,x:float64,y:float64
S:User,name:string,age:int,status:Status
F:makePoint(float64,float64):Point
...
```

This hash is:
1. Embedded as a comment in the generated `.dart` / `.py` file
2. Exported from the `.so` as `ocheAbiHash() → cstring`

When the binding is loaded, it calls `ocheAbiHash()` and compares. If the
`.so` was recompiled without regenerating the binding files, this check fails:

```
RuntimeError: Oche ABI mismatch: .so was compiled with hash 'a1b2c3d4'
but bindings expect 'deadbeef'. Recompile Nim and regenerate bindings.
```

The check uses a simple djb2-style hash — not cryptographic, but sufficient
to detect accidental mismatches. Older `.so` files without `ocheAbiHash`
skip the check gracefully.

---

## 14. numpy integration (Python)

### Zero-copy write path (SharedListView)

For POD types, `SharedListView.to_numpy()` returns a writable numpy view
**directly into Nim RAM**:

```python
buf = oche.makeParticleBuffer(1000)
arr = buf.to_numpy()  # dtype: [('x', '<f8'), ('y', '<f8'), ('mass', '<f8'), ('color', '<i4')]

arr['x'] *= 2.0       # writes directly into Nim memory, no copy
arr['mass'] += 1.0

buf[0].x              # reads the same memory — sees the numpy mutation
buf.free()
```

If the buffer is freed while numpy still holds the view, reading from numpy
will access freed memory. Always free after you're done with the numpy array.

### Read-only copy path (NativeListView)

For view mode (`NativeListView`), `to_numpy()` returns a **copy**:

```python
view = oche.getPointsView()
arr = view.to_numpy()   # returns a copy — safe to hold after view goes away
```

This is because view-mode data can be replaced at any time by the Nim side.

### Non-POD types

`to_numpy()` returns `None` for structs with string fields. Strings are
pointers — there is no safe numpy dtype that represents them.

### OcheArray / OchePtr input from numpy

```python
import numpy as np
a = np.array([1.0, 2.0, 3.0, 4.0], dtype=np.float64)
b = np.array([2.0, 3.0, 4.0, 5.0], dtype=np.float64)

result = oche.dotProduct(a, b)  # zero-copy — numpy pointer passed directly
```

Oche checks that the array is contiguous (`array.data.contiguous`). If not,
it calls `np.ascontiguousarray` first. The numpy array must outlive the Nim
call (it does, because the call is synchronous).

---

## 15. TypedData integration (Dart)

### OcheBuffer → typed extension methods

For each proc that returns `OcheBuffer[T]` where T is a primitive, Oche
generates a **typed extension method** specific to that proc's return type.
This avoids manual casting and gives compile-time type safety:

```dart
// Generated extension (example for makeIntBuffer):
// extension makeIntBufferExt on SharedListView<int> {
//   typed_data.Int64List? toInt64List() { ... }
// }

final buf = oche.makeIntBuffer(6);
final arr = buf.toInt64List()!;   // Int64List — no cast needed ✓

arr[5] = 777;         // writes into Nim memory — zero-copy
buf[5];               // returns 777 — same memory
buf.free();
```

The method name is derived from the Dart typed list class:

| Nim type | Method | Returns |
|---|---|---|
| `int` / `int64` | `toInt64List()` | `typed_data.Int64List?` |
| `int32` | `toInt32List()` | `typed_data.Int32List?` |
| `float64` / `float` | `toFloat64List()` | `typed_data.Float64List?` |
| `float32` | `toFloat32List()` | `typed_data.Float32List?` |
| `uint8` / `byte` | `toUint8List()` | `typed_data.Uint8List?` |
| struct (any) | — not generated — | use `SharedListView<XxxView>` directly |

`toTypedData()` (the untyped base method returning `typed_data.TypedData?`)
is still available on `SharedListView` as a fallback but requires a cast.
The typed extension methods are preferred.

### OcheArray input from TypedData

```dart
final a = Float64List.fromList([1.0, 2.0, 3.0, 4.0]);
final b = Float64List.fromList([2.0, 3.0, 4.0, 5.0]);
final dot = oche.dotProduct(a, b);
```

Dart VM GC may move managed heap objects, so OcheArray parameters in Dart
always involve **one memcpy** via `_ptr.asTypedList(n).setAll(0, data)`.
This is a single C-level memcpy, not a per-element Dart loop — fast in
practice.

### OchePtr input — true zero-copy in Dart

```dart
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

final buf = calloc<ffi.Int64>(5);
for (var i = 0; i < 5; i++) buf[i] = i + 1;

final sum = oche.sumIntsPtr(buf, 5);  // pointer passed directly, no copy

calloc.free(buf);  // caller manages lifetime
```

`calloc` allocates outside the Dart VM heap, so the GC cannot move it.
The pointer goes to Nim with no arena, no memcpy. This is the only way to
achieve true zero-copy in Dart.

---

## 16. What Oche does not solve

**Thread safety.** Nim globals used for view/share mode lifetimes are not
protected. If two threads call the same proc simultaneously they will race on
the global. Oche does not provide locks, atomics, or isolation. The caller
must provide external synchronization.

**Cross-Isolate sharing (Dart).** Dart Isolates do not share memory normally.
Passing an OcheBuffer pointer between Isolates is possible but dangerous and
not supported. Each Isolate that calls Nim gets its own view of any globals.

**Exception type propagation.** Only the message is preserved. The Python/Dart
side always receives a generic error.

**Callback/closure support.** You cannot pass a Python lambda or Dart closure
to a Nim proc. There is no callback mechanism.

**Nim GC and ARC/ORC with shared pointers.** When using `--gc:arc` or
`--gc:orc` (recommended), Nim's reference counting does not see `OcheBuffer`
pointers held by the foreign side. If a global is reassigned, Nim's ARC may
reclaim the old buffer while the foreign side still holds a reference. This
is a correctness issue the caller must manage by keeping globals alive.

---

## 17. Known limitations

| Limitation | Impact | Notes |
|---|---|---|
| No callback support | Cannot pass functions from Python/Dart to Nim | Fundamental — would require a separate mechanism |
| Exception type not propagated | Python always gets RuntimeError, Dart gets Exception | Message is preserved |
| Dart NativeListView has no negative indexing | `view[-1]` works in Python but not Dart | Python emitter handles it, Dart emitter does not |
| No JS/WASM emitter | Only Python and Dart | Nim compiles to JS but no emitter written yet |
| Global aliasing in user code | If two procs share one global OcheBuffer var, reassigning one invalidates the other's return | Design issue in user code (olib.nim), not in Oche itself |
| No seq[T] return in view mode for single struct | Downgraded to copy mode automatically with a warning | Stack safety — pointer to stack struct would dangle |
| non-POD structs cannot be used with to_numpy() | Returns None for structs with strings | Strings are pointers — no safe numpy dtype |
| Thread safety is caller's responsibility | Concurrent calls to procs that share Nim globals will race | By design — Oche is not a concurrency primitive |