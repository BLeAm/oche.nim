# Oche — Nim ↔ Dart FFI Bridge

Oche (โอเช) is a compile-time macro library for Nim that automatically generates Dart FFI bindings. Annotate your types and functions with `{.oche.}`, call `generate("nlib.dart")`, and get a fully working Dart library with zero-copy views, shared mutable buffers, and automatic deep memory management.

```nim
# main.nim
type
  Tag {.oche.} = object
    name: string
    id: int

proc getTags(n: int): OcheBuffer[Tag] {.oche.} = ...

generate("nlib.dart")
```

```dart
// main.dart — auto-generated
final tags = oche.getTags(100);
print(tags[0].name);   // zero-copy read
tags[0].id = 42;       // direct mutation in Nim's memory
```

---

## How It Works

Oche operates entirely at compile time. The `{.oche.}` macro:

1. Records your type and function signatures into compile-time tables
2. Transforms the Nim function into an FFI-compatible export with error handling
3. On `generate(...)`, emits a complete `.dart` file with FFI structs, extension types, and wrapper classes

All shared memory uses a fixed 16-byte header: `[int64 length][int32 typeId][int32 flags][data...]`

---

## Installation

Copy `oche.nim` into your project alongside your main source file. No package manager required.

**Compile the Nim shared library:**
```bash
nim c -d:danger --app:lib --out:libmain.so main.nim
# Windows: libmain.dll  |  macOS: libmain.dylib
```

**Run the Dart side:**
```bash
dart pub add ffi
dart main.dart
```

---

## API Reference

### Defining Types

Apply `{.oche.}` to `object` and `enum` declarations before any functions that use them.

```nim
type
  Status {.oche.} = enum
    Active, Inactive, Pending

  Tag {.oche.} = object
    name: string   # automatically converted to cstring in FFI layer
    id: int

  User {.oche.} = object
    username: string
    status: Status
    primaryTag: Tag  # nested structs are fully supported
```

Dart receives corresponding `NUser` (FFI struct), `UserView` (zero-copy extension type), and `User` (immutable Dart class).

---

### Strings in Structs

When constructing a struct that will live in FFI memory, use `toOcheStr()` for string fields. This allocates the string on the C heap so Nim's GC won't touch it.

```nim
proc getUser(): User {.oche.} =
  User(
    username: toOcheStr("Alice"),       # ⚠️ required for struct string fields
    primaryTag: Tag(name: toOcheStr("Admin"), id: 1),
    status: Active
  )
```

String parameters to functions do **not** need `toOcheStr` — only struct fields that will outlive the function call.

---

### Return Modes

Oche supports three memory ownership models depending on your use case.

#### Copy — `seq[T]`

Nim allocates, copies data into an FFI buffer, hands ownership to Dart. Dart's GC frees it automatically via a `Finalizer`.

```nim
proc getPoints(n: int): seq[Point] {.oche.} =
  result = newSeq[Point](n)
  for i in 0..<n: result[i] = Point(x: i.float, y: i.float)
```

```dart
final points = oche.getPoints(100);  // List<Point> — Dart owns it
print(points[0].x);
// freed automatically when GC collects `points`
```

> **Limitation:** `seq[T]` copy uses `copyMem`, which is a shallow copy. Structs containing strings (`seq[User]`) will have dangling string pointers after the source seq is freed. Use `OcheBuffer` instead for structs with strings.

---

#### View — `seq[T] {.oche: view.}`

Nim owns the data permanently (e.g. a global). Dart gets a read-only `NativeListView<T>` pointing directly into Nim's memory — no copy, no allocation.

```nim
var cachedMap: seq[Tile]

proc getMap(): seq[Tile] {.oche: view.} =
  cachedMap = loadMap()
  return cachedMap
```

```dart
final map = oche.getMap();   // NativeListView<TileView> — read-only
print(map[500].id);
map.dispose();               // or let Finalizer handle it
```

The data is valid as long as the Nim global is alive. Do not mutate `cachedMap` on the Nim side while Dart holds the view.

---

#### Shared Buffer — `OcheBuffer[T]`

Nim owns and retains the buffer. Dart can read **and write** directly into Nim's memory. No copy in either direction.

```nim
var users: OcheBuffer[User]

proc getUsers(n: int): OcheBuffer[User] {.oche.} =
  users = newOche[User](n)
  for i in 0..<n:
    users[i] = User(username: toOcheStr("User_" & $i), status: Active,
                    primaryTag: Tag(name: toOcheStr("Tag_" & $i), id: i))
  return users

proc printUser(idx: int) {.oche.} =
  echo users[idx].username, " / ", users[idx].primaryTag.name
```

```dart
final users = oche.getUsers(5);  // SharedListView<UserView>

// Assign a full new struct — Oche frees old nested strings before writing new ones
users[0] = User(
  username: 'Cheetah',
  primaryTag: Tag(name: 'SuperFast', id: 99),
  status: Status.active,
);

oche.printUser(0);  // prints: Cheetah / SuperFast
```

Nim sees the mutation immediately. No `dispose()` needed — Nim owns the memory.

---

### Finishing Up

Call `generate()` at the end of your Nim file, after all type and function declarations:

```nim
generate("nlib.dart")
```

This emits the complete Dart binding file on every compile.

---

## Memory Management

| Return type | Who owns memory | Dart frees? | Mutable from Dart? |
|---|---|---|---|
| `seq[T]` | Dart (after handoff) | Yes, via Finalizer | No |
| `seq[T] {.oche: view.}` | Nim (permanent) | No | No |
| `OcheBuffer[T]` | Nim | No | Yes |
| Single value / Option | Dart (after handoff) | Yes, via try/finally | No |

**Deep free:** When a struct contains strings or nested structs with strings, Oche generates per-type `ocheFreeInner` procs that recursively free nested pointers before deallocating the container. This is called automatically before any mutation via `[]=` on a `SharedListView`.

**POD optimization:** Structs with no string or pointer fields are flagged as POD. Their buffers skip the O(N) inner-free loop and go straight to `dealloc`.

---

## Known Limitations

- **`seq[non-POD]`** (e.g. `seq[User]`) uses shallow `copyMem`. String pointers will dangle after the Nim seq is freed. Use `OcheBuffer[User]` instead.
- **`toOcheStr()` is manual.** Forgetting it on a struct string field compiles fine but produces a dangling pointer at runtime. A future version may enforce this at compile time.
- **Thread safety is not addressed.** Concurrent reads/writes to a `SharedListView` from Dart isolates and Nim threads are unsafe without external locking.
- **Tested on Linux and macOS.** Windows `.dll` support is included in the generated path logic but has not been systematically tested.
- **No async wrappers.** Functions are synchronous FFI calls. Wrapping in `Isolate.run()` on the Dart side is the current workaround for long-running Nim calls.

---

## Type Reference

| Nim type | Dart FFI type | Dart user type |
|---|---|---|
| `int` / `int64` | `ffi.Int64` | `int` |
| `float` / `float64` | `ffi.Double` | `double` |
| `bool` | `ffi.Bool` | `bool` |
| `string` / `cstring` | `ffi.Pointer<Utf8>` | `String` |
| `enum` | `ffi.Int32` | `enum` |
| `object` | `ffi.Struct` (NType) | `TypeView` + `Type` |
| `seq[T]` | `ffi.Pointer<ffi.Void>` | `List<T>` |
| `seq[T] {.oche: view.}` | `ffi.Pointer<ffi.Void>` | `NativeListView<TView>` |
| `OcheBuffer[T]` | `ffi.Pointer<ffi.Void>` | `SharedListView<TView>` |
| `Option[T]` | `ffi.Pointer<ffi.Void>` | `T?` |
