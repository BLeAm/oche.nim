import oche

type
  User {.oche.} = object
    id: int
    score: float

  People {.oche.} = object
    id: int
    age: int

  Employer {.oche.} = object
    secretary: People

proc add(a, b: int): int {.oche.} = a + b

proc sum(vals: seq[int]): int {.oche.} =
  for v in vals: result += v

proc getRange(n: int): seq[int] {.oche.} =
  for i in 0 ..< n: result.add i

proc getTopPlayers(): seq[User] {.oche.} =
  result.add User(id: 1, score: 99.5)
  result.add User(id: 2, score: 88.0)

proc createEmployer(id, age: int): Employer {.oche.} =
  result.secretary.id = id
  result.secretary.age = age

proc greet(name: string): string {.oche.} =
  "Hello, " & name # Seamless String!

generate("nlib.dart")
