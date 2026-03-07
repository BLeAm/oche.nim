import std/options
import oche

# ==========================================
# 1. Enums
# ==========================================
type 
  Status {.oche.} = enum
    Active, Inactive, Pending

# ==========================================
# 2. POD Structs (Plain Old Data)
# ==========================================
type
  Point {.oche.} = object
    x, y: float

# ==========================================
# 3. Complex Structs (Strings & Nested)
# ==========================================
type
  Tag {.oche.} = object
    name: string
    id: int

  User {.oche.} = object
    username: string
    status: Status
    primaryTag: Tag

# ==========================================
# Global Shared Buffers
# ==========================================
var globalPoints: OcheBuffer[Point]
var globalUsers: OcheBuffer[User]

# ==========================================
# Basic Primitives & Strings
# ==========================================
proc addNumbers(a: int, b: int): int {.oche.} = a + b
proc addNumbersPy(a: int, b: int): int {.porche.} = a + b

proc greet(name: string): string {.oche.} = "Hello, " & name
proc greetPy(name: string): string {.porche.} = "Hello, " & name

# ==========================================
# Returning Structs & Enums
# ==========================================
proc createUser(name: string, tagId: int): User {.oche.} =
  User(
    username: toOcheStr(name), # Use toOcheStr for FFI safety!
    status: Active,
    primaryTag: Tag(name: toOcheStr("Tag_" & $tagId), id: tagId)
  )
proc createUserPy(name: string, tagId: int): User {.porche.} =
  User(
    username: toOcheStr(name),
    status: Active,
    primaryTag: Tag(name: toOcheStr("Tag_" & $tagId), id: tagId)
  )

# ==========================================
# Passing Sequences (Dart -> Nim)
# ==========================================
proc sumPoints(points: seq[Point]): float {.oche.} =
  for p in points: result += p.x + p.y

# ==========================================
# Returning Sequences (Snapshot / Copy Mode)
# ==========================================
# The generated Dart code will manage the lifecycle of this sequence via GC Finalizers.
proc getPointsCopy(n: int): seq[Point] {.oche.} =
  for i in 0..<n: result.add(Point(x: i.float, y: i.float))
proc getPointsCopyPy(n: int): seq[Point] {.porche.} =
  for i in 0..<n: result.add(Point(x: i.float, y: i.float))

proc maybePoint(which: int): Option[Point] {.porche.} =
  if which == 0: none[Point]() else: some(Point(x: 1.0, y: 2.0))

# ==========================================
# Returning Sequences (Zero-Copy View Mode)
# ==========================================
# Nim retains ownership. Useful for read-only massive datasets.
var cachedPoints: seq[Point]
proc getPointsView(n: int): seq[Point] {.oche: view.} =
  cachedPoints = newSeq[Point](n)
  for i in 0..<n: cachedPoints[i] = Point(x: i.float, y: (i*2).float)
  return cachedPoints

# ==========================================
# Shared Live Buffers (Mutation enabled)
# ==========================================
proc initSharedPoints(n: int): OcheBuffer[Point] {.oche.} =
  globalPoints = newOche[Point](n)
  for i in 0..<n: globalPoints[i] = Point(x: i.float, y: i.float)
  return globalPoints

proc printSharedPoint(idx: int) {.oche.} =
  if idx < globalPoints.len:
    echo "Nim sees Point[", idx, "]: (", globalPoints[idx].x, ", ", globalPoints[idx].y, ")"

proc initSharedUsers(n: int): OcheBuffer[User] {.oche.} =
  globalUsers = newOche[User](n)
  for i in 0..<n:
    globalUsers[i] = User(
      username: toOcheStr("User_" & $i),
      status: Pending,
      primaryTag: Tag(name: toOcheStr("Tag_" & $i), id: i)
    )
  return globalUsers

proc printSharedUser(idx: int) {.oche.} =
  if idx < globalUsers.len:
    let u = globalUsers[idx]
    echo "Nim sees User[", idx, "] = '", u.username, "', Status: ", u.status, ", Tag: '", u.primaryTag.name, "'"

# Generate Dart bindings!
generate("nlib.dart")
# Generate Python bindings (porche)
generatePython("nlib.py")
