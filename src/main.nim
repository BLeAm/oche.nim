import oche
import std/options
import os

type
  # บังคับขนาดให้เป็น 4 bytes เพื่อให้ตรงกับ Dart ffi.Int32() และป้องกัน Alignment Shift
  UserRole {.oche.} = enum
    Admin, Editor, Viewer

  Point {.oche.} = object
    x, y: float

  User {.oche.} = object
    id: int
    name: cstring
    status: UserRole
    position: Point

proc greet(name: string): string {.oche.} =
  if name == "": raise newException(ValueError, "Name cannot be empty!")
  return "Greetings, " & name & " from Nim!"

proc getMultipliers(base: int, count: int): seq[int] {.oche.} =
  result = @[]
  for i in 1..count:
    result.add(base * i)

proc sumPoints(points: seq[Point]): float {.oche.} =
  result = 0
  for p in points:
    result += (p.x + p.y)

proc findUserById(id: int): Option[User] {.oche.} =
  if id == 42:
    some(User(id: 42, name: "Master Bleamz", status: Admin, position: Point(x: 1.1, y: 2.2)))
  else:
    none(User)

proc isPrime(n: int): bool {.oche.} =
  if n <= 1: return false
  for i in 2 ..< n:
    if n mod i == 0: return false
  return true

proc heavyTask(seconds: int): string {.oche.} =
  sleep(seconds * 1000)
  return "Heavy task finished after " & $seconds & "s"

# Generate Dart code
generate("nlib.dart")
