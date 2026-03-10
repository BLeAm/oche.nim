# oche

> **Nim FFI codegen for Python and Dart** — write fast Nim, call it from Python or Dart with zero boilerplate.

oche reads annotated Nim types and procs at **compile time** and generates a complete, idiomatic binding file (`nlib.dart` / `nlib.py`) that handles all marshalling, memory management, and lifetime tracking automatically. The Python companion is called **porche**.

---

## Why oche?

| | Pure Python / Dart | ctypes / dart:ffi by hand | **oche** |
|---|---|---|---|
| Speed | slow | native | native |
| Boilerplate | none | enormous | **none** |
| Memory safety | GC | manual | **automatic** |
| Zero-copy arrays | ✗ | possible | **built-in** |
| String fields | trivial | painful | **automatic** |
| Struct mutation | trivial | painful | **automatic** |

---

## Quick start

```nim
# mylib.nim
import oche

type
  User {.oche, porche.} = object   # export to Dart and Python
    name: string
    age:  int

proc initUser(name: string, age: int): User {.oche, porche.} =
  User(name: name.toOcheStr, age: age)

proc greetUser(u: User): string {.oche, porche.} =
  "Hello, " & $u.name

generate("mylib.dart")
generatePython("mylib.py")
```

```bash
nim c --app:lib --out:libmylib.so mylib.nim
```

**Python**
```python
from mylib import porche

u = porche.initUser("Alice", 30)
print(u.name)          # Alice
u.name = "Bob"         # mutable field
print(porche.greetUser(u))
```

**Dart**
```dart
import 'mylib.dart';

final u = oche.initUser("Alice", 30);
print(u.name);         // Alice
u.name = "Bob";        // mutable field
print(oche.greetUser(u));
```

---

## Return type cheat-sheet

| Nim return type | Python type | Dart type | Mutable | Freed by |
|---|---|---|---|---|
| `T` (struct) | `T` plain object | `T` class | ✅ | GC |
| `string` | `str` | `String` | — | GC |
| `seq[T]` copy | `List[T]` | `List<T>` | ✅ | GC |
| `seq[T]` `{.view.}` | `NativeListView` | `NativeListView<TView>` | ❌ read-only | GC finalizer |
| `OcheBuffer[T]` | `SharedListView` | `SharedListView<TView>` | ✅ | **`.free()` required** |
| `Option[T]` | `T \| None` | `T?` | ✅ | GC |

`TView` is a zero-copy window into Nim RAM. Call `.freeze()` on any `TView` to copy it into a GC-owned `T`.

---

## Input param cheat-sheet

| Nim param type | Python accepts | Dart accepts | Copies? |
|---|---|---|---|
| `T` (struct) | `T` or `TView` | `T` or `TView` | yes — pack to C struct |
| `string` | `str` | `String` | yes — UTF-8 |
| `seq[T]` | `list` | `List<T>` | yes — element loop |
| `OcheArray[T]` | numpy / `array.array` | `Int64List` etc. | 1× memcpy |
| `OchePtr[T]` | numpy / ctypes ptr | `ffi.Pointer<T>` | **zero-copy** |

---

## Pragma reference

```nim
# Types
type Foo {.oche.}          = object ...   # Dart only
type Foo {.oche, porche.}  = object ...   # Dart + Python

# Procs — copy mode (default)
proc f(...) {.oche.}                      # Dart only
proc f(...) {.oche, porche.}              # Dart + Python

# Procs — view / zero-copy mode
proc f(...) {.oche: view.}                # Dart only, zero-copy return
proc f(...) {.oche: view, porche: view.}  # Dart + Python, zero-copy return
```

---

## Project layout

```
oche.nim          # macros: {.oche.}, {.porche.}, generate(), generatePython()
oche_core.nim     # compile-time IR (OcheType, OcheStruct, OcheObject …)
oche_dart.nim     # Dart emitter
oche_python.nim   # Python / ctypes emitter
```

---

## Requirements

- Nim ≥ 2.0
- Dart: `ffi: ^2.0.0` in `pubspec.yaml`
- Python: standard library only (`ctypes`); numpy optional for zero-copy array paths

---

## License

MIT
