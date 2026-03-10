# oche — Developer Guide

---

## Table of contents

1. [Mental model](#1-mental-model)
2. [Annotating types](#2-annotating-types)
3. [Annotating procs](#3-annotating-procs)
4. [Return modes in depth](#4-return-modes-in-depth)
   - 4.1 [Copy mode — single struct](#41-copy-mode--single-struct)
   - 4.2 [Copy mode — seq](#42-copy-mode--seq)
   - 4.3 [View mode — seq](#43-view-mode--seq-nativelistview)
   - 4.4 [Shared mode — OcheBuffer](#44-shared-mode--ochebuffer)
   - 4.5 [Option](#45-option)
   - 4.6 [Strings](#46-strings)
   - 4.7 [Primitives and enums](#47-primitives-and-enums)
5. [Input param types](#5-input-param-types)
   - 5.1 [Struct params](#51-struct-params)
   - 5.2 [seq params](#52-seq-params)
   - 5.3 [OcheArray — fast array input](#53-ochearray--fast-array-input)
   - 5.4 [OchePtr — true zero-copy input](#54-ocheptr--true-zero-copy-input)
6. [T vs TView — the ownership split](#6-t-vs-tview--the-ownership-split)
7. [Memory management rules](#7-memory-management-rules)
8. [String fields](#8-string-fields)
9. [Nested structs](#9-nested-structs)
10. [Enums](#10-enums)
11. [numpy / typed-data integration](#11-numpy--typed-data-integration)
12. [Error handling](#12-error-handling)
13. [Full example — benchmark harness](#13-full-example--benchmark-harness)
14. [Generated file structure](#14-generated-file-structure)

---

## 1. Mental model

```
┌──────────────┐   {.oche, porche.}   ┌────────────────────────────┐
│   mylib.nim  │  ──────────────────► │  compile-time IR (oche_core)│
│  (your code) │                      └────────────┬───────────────┘
└──────────────┘                                   │
                                       ┌───────────┴───────────┐
                                       ▼                       ▼
                               generate()            generatePython()
                               tlib.dart             tlib.py
```

**Everything happens at Nim compile time.** No reflection, no runtime overhead. The generated files contain plain `ctypes` / `dart:ffi` code with no dependency on oche at runtime.

### Ownership: two worlds

```
Nim RAM                          │  Python / Dart GC
─────────────────────────────────┼──────────────────────────────
OcheBuffer[T]  (Nim owns)        │  T  plain object  (GC owns)
seq[T] view    (Nim owns)        │  TView (borrowed — do not outlive source)
                                 │  NativeListView / SharedListView (managed)
```

The key rule: **`T` (plain class/object) is always safe to hold forever. `TView` must not outlive the Nim buffer it points into.**

---

## 2. Annotating types

```nim
# Dart only
type Point {.oche.} = object
  x, y: float64

# Dart + Python
type User {.oche, porche.} = object
  name: string    # string fields are handled automatically
  age:  int
```

### Supported field types

| Nim field type | Python | Dart |
|---|---|---|
| `int` / `int64` | `int` | `int` |
| `float` / `float64` | `float` | `double` |
| `float32` | `float` | `double` |
| `uint8` | `int` | `int` |
| `bool` | `bool` | `bool` |
| `string` | `str` (nullable) | `String` |
| Another `{.oche.}` struct | nested plain object | nested class |
| `{.oche.}` enum | `int` | enum class |

---

## 3. Annotating procs

```nim
# Dart only, copy mode
proc makePoint(x, y: float64): Point {.oche.} = Point(x: x, y: y)

# Both, copy mode
proc initUser(name: string, age: int): User {.oche, porche.} =
  User(name: name.toOcheStr, age: age)

# Both, view / zero-copy mode (for seq and OcheBuffer returns)
proc getUsers(): seq[User] {.oche: view, porche: view.} = myGlobalSeq

# Generate at end of file
generate("tlib.dart")
generatePython("tlib.py")
```

`toOcheStr` copies a Nim managed string into an unmanaged C heap string that oche can hand off safely across the FFI boundary.

---

## 4. Return modes in depth

### 4.1 Copy mode — single struct

```nim
proc initUser(name: string, age: int): User {.oche, porche.} =
  User(name: name.toOcheStr, age: age)
```

| | Python | Dart |
|---|---|---|
| Returned type | `User` plain object | `User` class |
| Ownership | Python / Dart GC | Python / Dart GC |
| Mutable | ✅ | ✅ |
| Free | automatic | automatic |

```python
u = porche.initUser("Alice", 30)
u.name = "Bob"    # mutable — Dart string, no ocheStr* involved
u.age  = 31
print(u)          # User(name='Bob', age=31)
```

```dart
final u = oche.initUser("Alice", 30);
u.name = "Bob";
u.age  = 31;
```

> **Note:** `{.porche: view.}` on a single struct return is silently ignored and falls back to copy mode. A Nim proc that returns a struct by value gives you a stack copy — there is no persistent buffer to borrow from.

---

### 4.2 Copy mode — seq

```nim
proc listUsers(): seq[User] {.oche, porche.} =
  @[User(name: "a".toOcheStr, age: 1), User(name: "b".toOcheStr, age: 2)]
```

Returns a fully copied `List[User]` / `List<User>`. Every element is unpacked from Nim RAM into a GC-owned object before the Nim allocation is freed.

```python
users = porche.listUsers()   # List[User]
users[0].name = "changed"    # safe — fully GC-owned
```

---

### 4.3 View mode — seq (`NativeListView`)

```nim
var cache: seq[User]   # global — must outlive the view

proc getCachedUsers(): seq[User] {.oche: view, porche: view.} =
  cache
```

| | Python | Dart |
|---|---|---|
| Returned type | `NativeListView` | `NativeListView<UserView>` |
| Element type | `UserView` (borrowed) | `UserView` (borrowed) |
| Mutable | ❌ read-only | ❌ read-only |
| Free | GC finalizer (auto) | GC `Finalizer` (auto) |

```python
view = porche.getCachedUsers()
u = view[0]           # UserView — zero-copy window into Nim RAM
print(u.name)         # read
u2 = u.freeze()       # copy out → User plain object, safe to keep
view.to_numpy()       # POD structs only — returns numpy structured array
```

```dart
final view = oche.getCachedUsers();
final u = view[0];         // UserView
print(u.name);             // read
final u2 = u.freeze();     // copy out → User, safe to keep
```

**⚠️ Never store a `UserView` beyond the lifetime of its parent `NativeListView`.**

---

### 4.4 Shared mode — OcheBuffer

```nim
var buf: OcheBuffer[User]   # global — Nim owns this memory

proc initUserBuffer(n: int): OcheBuffer[User] {.oche, porche.} =
  buf = newOche[User](n)
  return buf
```

| | Python | Dart |
|---|---|---|
| Returned type | `SharedListView` | `SharedListView<UserView>` |
| Element type | `UserView` (borrowed) | `UserView` (borrowed) |
| Mutable | ✅ read-write | ✅ read-write |
| Free | **`.free()` required** | **`.free()` required** |

```python
# Explicit free
buf = porche.initUserBuffer(10)
buf[0].name = "Alice"
buf.free()

# Context manager (preferred)
with porche.initUserBuffer(10) as buf:
    buf[0].name = "Alice"
    arr = buf.to_numpy()   # zero-copy numpy view (POD structs only)
# auto-freed on exit
```

```dart
final buf = oche.initUserBuffer(10);
buf[0].name = "Alice";
buf.free();   // must call manually — no context manager in Dart
```

**When to use `OcheBuffer` vs `seq` view:**
- `OcheBuffer` — when Nim needs to keep the buffer alive across multiple calls (e.g. audio buffer, simulation state).
- `seq` view — when you just want to expose an existing Nim seq cheaply.

---

### 4.5 Option

```nim
proc findUser(id: int): Option[User] {.oche, porche.} =
  if id == 1: some(User(name: "Alice".toOcheStr, age: 30))
  else: none(User)
```

```python
u = porche.findUser(1)   # User | None
u = porche.findUser(99)  # None
```

```dart
final u = oche.findUser(1);   // User?
```

---

### 4.6 Strings

```nim
proc greet(name: string): string {.oche, porche.} =
  "Hello, " & name
```

Returned strings are copied to GC memory and Nim's allocation is freed immediately. No manual management needed.

---

### 4.7 Primitives and enums

```nim
proc add(a, b: int): int {.oche, porche.} = a + b

type Color {.oche, porche.} = enum Red, Green, Blue
proc getColor(): Color {.oche, porche.} = Green
```

Primitives pass by value. Enums marshal as `int32` on the wire and are reconstructed as the enum type on the receiving side.

---

## 5. Input param types

### 5.1 Struct params

Functions accepting a struct param accept **both** the plain class and the view:

```python
u1 = porche.initUser("Alice", 30)   # User plain
buf = porche.initUserBuffer(1)
u2 = buf[0]                         # UserView

porche.printUser(u1)   # ✅ User
porche.printUser(u2)   # ✅ UserView — both work
```

```dart
oche.printUser(u);    // User or UserView — both accepted
```

Internally oche packs the struct into a temporary C struct for the call.

---

### 5.2 seq params

```nim
proc sum(values: seq[int]): int {.oche, porche.} =
  values.foldl(a + b, 0)
```

The list is copied element-by-element into a temporary C array. Fine for moderate sizes. For large arrays, prefer `OcheArray` or `OchePtr`.

---

### 5.3 OcheArray — fast array input

```nim
proc muliTwoFast(list: OcheArray[int]): OcheBuffer[int] {.oche, porche.} =
  let out = newOche[int](list.len)
  for i in 0..<list.len: out[i] = list[i] * 2
  return out
```

| Language | Accepts | Transfer |
|---|---|---|
| Python | `numpy` array or `array.array` | zero-copy (pointer + len) |
| Dart | `Int64List` / `Float64List` | 1× `memcpy` via `setAll` |

```python
import numpy as np
narr = np.array(range(1_000_000), dtype=np.int64)
result = porche.muliTwoFast(narr)   # zero-copy input, SharedListView output
```

```dart
final narr = Int64List.fromList(bulk);
final result = oche.muliTwoFast(narr);   // 1× memcpy input
```

---

### 5.4 OchePtr — true zero-copy input

```nim
proc muliTwoPtr(list: OchePtr[int]): OcheBuffer[int] {.oche, porche.} =
  let out = newOche[int](list.len)
  for i in 0..<list.len: out[i] = list[i] * 2
  return out
```

| Language | Accepts | Transfer |
|---|---|---|
| Python | `numpy` array, `array.array`, or raw ctypes pointer | zero-copy |
| Dart | `ffi.Pointer<Int64>` (calloc / malloc) | **zero-copy — no staging at all** |

```python
result = porche.muliTwoPtr(narr)   # zero-copy both directions
```

```dart
// Persistent buffer — allocate once, reuse many times
final buf = calloc<Int64>(n);
for (var i = 0; i < n; i++) buf[i] = i;
final result = oche.muliTwoPtr(buf, n);
calloc.free(buf);
```

**Use `OchePtr` when:**
- You have a long-lived native buffer (audio pipeline, video frame, sensor stream).
- You want to avoid even a single staging copy.

---

## 6. T vs TView — the ownership split

Every exported struct generates **two** representations:

| | `User` | `UserView` |
|---|---|---|
| Lives in | Python / Dart GC heap | **Nim RAM** (borrowed) |
| Fields | mutable Python/Dart values | mutable windows into Nim RAM |
| String setter | replaces Dart string | `ocheStrFree` + `ocheStrAlloc` |
| Lifetime | forever (GC) | tied to parent buffer |
| `freeze()` | — | copies into `User` |
| Used in | single return, seq copy | seq view, OcheBuffer |

```python
# TView → T via freeze()
view = porche.getCachedUsers()
u = view[0].freeze()   # safe to keep after view is gone
```

```dart
final u = view[0].freeze();   // User — GC-owned
```

---

## 7. Memory management rules

| Type | Python | Dart |
|---|---|---|
| `T` plain / `User` | GC automatic | GC automatic |
| `List[T]` copy | GC automatic | GC automatic |
| `NativeListView` | GC finalizer (auto) | GC `Finalizer` (auto) |
| `SharedListView` | **`.free()`** or `with` block | **`.free()`** |
| `TView` element from `SharedListView` | never free individually | never free individually |
| string field setter on `TView` | oche handles `ocheStrFree`/`ocheStrAlloc` | oche handles `_ocheStrFree`/`_ocheStrAlloc` |

**Python convenience — context manager:**
```python
with porche.initUserBuffer(100) as buf:
    process(buf)
# automatically freed
```

**Dart — manual only:**
```dart
final buf = oche.initUserBuffer(100);
try { process(buf); } finally { buf.free(); }
```

---

## 8. String fields

String fields in structs require careful handling across the FFI boundary. oche manages this automatically:

- **Nim side:** use `toOcheStr` to convert a Nim GC string to a `cstring` on the unmanaged heap.
- **Getter:** reads the C pointer lazily and decodes UTF-8.
- **Setter on `TView`:** calls `ocheStrFree` on the old pointer, allocates a new one with `ocheStrAlloc`.
- **Setter on `T` (plain):** standard Python/Dart string assignment — no C heap involved.
- **`freeze()`:** calls `toDartString()` / `decode('utf-8')` to produce a GC-owned string copy.
- **`__del__` / destructor on owned `TView`:** frees all string fields before freeing the struct buffer.

```nim
type Person {.oche, porche.} = object
  first, last: string

proc makePerson(f, l: string): Person {.oche, porche.} =
  Person(first: f.toOcheStr, last: l.toOcheStr)
```

```python
p = porche.makePerson("John", "Doe")
p.first = "Jane"   # plain Dart string reassignment — no leak
```

---

## 9. Nested structs

```nim
type
  Address {.oche, porche.} = object
    city: string

  Person {.oche, porche.} = object
    name: string
    addr: Address
```

Nested structs are embedded inline (not as pointers) in the C struct layout. Accessors return a `AddressView` that points into the parent struct's memory — the parent owns it.

```python
p = porche.makePerson(...)
print(p.addr.city)   # AddressView — reads from embedded memory
city_copy = p.addr.city  # str — GC-owned copy via property getter
```

---

## 10. Enums

```nim
type Status {.oche, porche.} = enum
  Pending, Active, Closed

proc getStatus(): Status {.oche, porche.} = Active
```

```python
s = porche.getStatus()   # int (0 / 1 / 2)
print(s == porche.Status.Active)  # True
```

```dart
final s = oche.getStatus();   // Status enum
print(s == Status.Active);    // true
```

---

## 11. numpy / typed-data integration

### NativeListView.to_numpy() — read-only copy

```python
view = porche.getCachedInts()    # NativeListView
arr = view.to_numpy()            # numpy array — copy (Nim may free anytime)
```

### SharedListView.to_numpy() — zero-copy writable view

```python
with porche.getBuffer() as buf:
    arr = buf.to_numpy()         # zero-copy view into Nim RAM
    arr *= 2                     # modifies Nim memory directly
```

`to_numpy()` returns `None` for non-POD structs (i.e. structs with string fields).

### Dart typed data

```dart
// NativeListView<int> from seq[int] {.view.}
final list = oche.getInts();
// standard List iteration — no special numpy equivalent
for (final v in list) print(v);
```

---

## 12. Error handling

If a Nim proc raises an exception, oche catches it, stores the message, and re-raises it on the calling side:

```python
try:
    result = porche.riskyOp()
except RuntimeError as e:
    print(e)   # "NimError: ..."
```

```dart
try {
  final result = oche.riskyOp();
} catch (e) {
  print(e);   // Exception: NimError: ...
}
```

On the Nim side, no special annotation is needed — all exported procs are automatically wrapped.

---

## 13. Full example — benchmark harness

The following mirrors the `toc2.nim` / `toc.py` / `toc.dart` benchmark that ships with oche.

**Nim (`toc2.nim`)**
```nim
import oche

var intBuffer: OcheBuffer[int]

proc muliTwo(list: seq[int]): OcheBuffer[int] {.oche, porche.} =
  intBuffer = newOche[int](list.len)
  for i in 0..<list.len: intBuffer[i] = list[i] * 2
  return intBuffer

proc muliTwoFast(list: OcheArray[int]): OcheBuffer[int] {.oche, porche.} =
  intBuffer = newOche[int](list.len)
  for i in 0..<list.len: intBuffer[i] = list[i] * 2
  return intBuffer

proc muliTwoPtr(list: OchePtr[int]): OcheBuffer[int] {.oche, porche.} =
  intBuffer = newOche[int](list.len)
  for i in 0..<list.len: intBuffer[i] = list[i] * 2
  return intBuffer

generate("tlib.dart")
generatePython("tlib.py")
```

**Python (`toc.py`)**
```python
from tlib import porche
import numpy as np

bulk = list(range(10_000_000))
narr = np.array(bulk, dtype=np.int64)

# seq path — copies list into C array
result = porche.muliTwo(bulk)

# OcheArray path — zero-copy from numpy (pointer + len directly to Nim)
result = porche.muliTwoFast(narr)

# OchePtr path — zero-copy, same as OcheArray for numpy
result = porche.muliTwoPtr(narr)
```

**Dart (`toc.dart`)**
```dart
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'tlib.dart';

final bulk = List.generate(10000000, (i) => i);

// seq path — element-by-element copy
final r1 = oche.muliTwo(bulk);

// OcheArray path — 1× memcpy via setAll
final narr = Int64List.fromList(bulk);
final r2 = oche.muliTwoFast(narr);

// OchePtr path — true zero-copy, caller manages native buffer
final buf = calloc<Int64>(10000000);
for (var i = 0; i < 10000000; i++) buf[i] = i;
final r3 = oche.muliTwoPtr(buf, 10000000);
calloc.free(buf);
```

---

## 14. Generated file structure

Both `tlib.py` and `tlib.dart` are self-contained. Here is a map of what gets generated:

### Python (`tlib.py`)

```
_struct_types        # {name: ctypes Structure class}
_struct_field_meta   # {name: {field: (kind, extra)}}
_struct_view_types   # {name: XxxView class}
_struct_plain_types  # {name: Xxx plain class}
_OFF_Xxx_field       # byte offsets for each field

class XxxView         # zero-copy view — fields are direct memory reads/writes
  .freeze()           # → Xxx (GC-owned deep copy)
  .__del__()          # frees strings then buffer if owned

class Xxx             # GC-owned plain class — mutable Python object
  ._from_view(v)      # static: construct from XxxView

class Porche          # all exported procs as methods
  .funcName(...)

porche = Porche()     # singleton

class NativeListView  # seq view — read-only, auto-freed by finalizer
  .__getitem__        # returns XxxView (zero-copy)
  .to_list()          # → List[Xxx] (copy)
  .to_numpy()         # → numpy array (copy for structs, view for primitives)

class SharedListView  # OcheBuffer — read-write, Nim owns
  .__getitem__        # returns XxxView (zero-copy)
  .__setitem__        # accepts Xxx or XxxView
  .to_numpy()         # zero-copy writable numpy view (POD only)
  .free()             # release Nim buffer
  .__enter__/__exit__ # context manager
```

### Dart (`tlib.dart`)

```
final class NXxx extends ffi.Struct   # C struct layout

extension type XxxView(NXxx _ref)     # zero-copy view
  .fieldName getter/setter
  .freeze()   → Xxx
  ._packInto(Pointer<NXxx>)

class Xxx                             # GC-owned mutable class
  .fieldName (mutable)
  ._pack / ._packManual / ._unpack

class Oche                            # all exported procs as methods
  .funcName(...)

final oche = Oche()                   # singleton

class NativeListView<T>               # seq view — read-only, Finalizer auto-frees
  .operator []   → TView (zero-copy)
  .free()        # eager release

class SharedListView<T>               # OcheBuffer — read-write, Nim owns
  .operator []   → TView (zero-copy)
  .operator []=  # accepts T or TView
  .free()        # must call manually
```
