import oche

proc add(a, b: int): int {.oche.} =
  a + b

proc mul(a, b: int): int {.oche.} =
  a * b

proc tdiv(a, b, c: int): int {.oche.} =
  a div b

proc addFloat(a, b: float): float {.oche.} =
  a + b

proc isEven(n: int): bool {.oche.} =
  n mod 2 == 0

proc greet(name: cstring): cstring {.oche.} =
  # Allocate on the C heap so Dart can safely hold this pointer.
  # Nim's ORC GC won't touch this — Dart must free it via ocheFreeCString.
  let s = "Hello, " & $name
  let buf = cast[cstring](alloc0(s.len + 1))
  copyMem(buf, s.cstring, s.len + 1)
  buf

generate("nlib.dart")
