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
  ("Hello, " & $name).cstring

generate("nlib.dart")
