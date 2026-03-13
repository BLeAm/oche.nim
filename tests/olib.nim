## olib.nim — Comprehensive oche feature test library
## Tests: copy/view/share modes, structs, nested structs, enums,
##        strings, Option, primitives, seq, OcheArray, OchePtr,
##        OcheBuffer as input param, mutation, freeze, error handling.
import oche
import std/options

# ─── Enums ────────────────────────────────────────────────────────────────────

type
  Color {.oche.} = enum
    Red, Green, Blue

  Status {.oche.} = enum
    Pending, Active, Closed

# ─── Structs ─────────────────────────────────────────────────────────────────

type
  Point {.oche.} = object
    x: float64
    y: float64

  # POD struct with enum field
  Particle {.oche.} = object
    x: float64
    y: float64
    mass: float64
    color: Color

  # Non-POD struct (has string)
  User {.oche.} = object
    name: string
    age:  int
    status: Status

  # Nested struct (inline)
  Tagged {.oche.} = object
    point: Point
    label: string

# ─── Globals (for view/share modes) ──────────────────────────────────────────

var gPoints: seq[Point]
var gUsers: seq[User]

# FIX: แยก global สำหรับแต่ละ proc ที่ return OcheBuffer[int]
# เดิมใช้ gBuf ร่วมกันระหว่าง makeIntBuffer และ doubleIntBuffer
# ทำให้ doubleIntBuffer ทับ pointer ที่ makeIntBuffer return ไปแล้ว
var gIntBuf: OcheBuffer[int]
var gDoubleBuf: OcheBuffer[int]
var gFloatBuf {.global.}: OcheBuffer[float64]
var gNegBuf {.global.}: OcheBuffer[int]

var gParticleBuf: OcheBuffer[Particle]
var gUserBuf: OcheBuffer[User]

# ─── Copy mode procs ──────────────────────────────────────────────────────────

proc makePoint(x, y: float64): Point {.oche.} =
  Point(x: x, y: y)

proc makeUser(name: string, age: int): User {.oche.} =
  User(name: name.toOcheStr, age: age, status: Active)

proc makeTagged(label: string, x, y: float64): Tagged {.oche.} =
  Tagged(point: Point(x: x, y: y), label: label.toOcheStr)

proc makeParticle(x, y, mass: float64, color: Color): Particle {.oche.} =
  Particle(x: x, y: y, mass: mass, color: color)

proc getColor(): Color {.oche.} = Green

proc getStatus(u: User): Status {.oche.} =
  u.status

proc addPoints(a, b: Point): Point {.oche.} =
  Point(x: a.x + b.x, y: a.y + b.y)

proc greetUser(u: User): string {.oche.} =
  "Hello, " & $u.name & "! Age: " & $u.age

# ─── Option procs ─────────────────────────────────────────────────────────────

proc maybePoint(give: bool): Option[Point] {.oche.} =
  if give: some(Point(x: 1.5, y: 2.5)) else: none(Point)

proc maybeUser(name: string): Option[User] {.oche.} =
  if name.len > 0:
    some(User(name: name.toOcheStr, age: 99, status: Active))
  else:
    none(User)

# ─── Primitive procs ──────────────────────────────────────────────────────────

proc addInts(a, b: int): int {.oche.} = a + b

proc mulFloat(a, b: float64): float64 {.oche.} = a * b

proc echoStr(s: string): string {.oche.} = "echo: " & s

proc sumSeq(values: seq[int]): int {.oche.} =
  var total = 0
  for v in values: total += v
  return total

# ─── seq copy mode ────────────────────────────────────────────────────────────

proc makePointList(n: int): seq[Point] {.oche.} =
  result = newSeq[Point](n)
  for i in 0..<n:
    result[i] = Point(x: float64(i), y: float64(i) * 2.0)

proc makeUserList(n: int): seq[User] {.oche.} =
  result = newSeq[User](n)
  for i in 0..<n:
    result[i] = User(name: ("user" & $i).toOcheStr, age: i * 10, status: Active)

# ─── seq view mode ────────────────────────────────────────────────────────────

proc getPointsView(): seq[Point] {.oche: view.} =
  gPoints = @[Point(x: 1.0, y: 2.0), Point(x: 3.0, y: 4.0), Point(x: 5.0, y: 6.0)]
  gPoints

proc getUsersView(): seq[User] {.oche: view.} =
  gUsers = newSeq[User](3)
  for i in 0..<3:
    gUsers[i] = User(name: ("view_user" & $i).toOcheStr, age: (i+1)*11, status: Active)
  gUsers

# ─── OcheBuffer (share mode) ──────────────────────────────────────────────────

proc makeIntBuffer(n: int): OcheBuffer[int] {.oche.} =
  gIntBuf = newOche[int](n)
  for i in 0..<n: gIntBuf[i] = i * 3
  gIntBuf

proc makeParticleBuffer(n: int): OcheBuffer[Particle] {.oche.} =
  gParticleBuf = newOche[Particle](n)
  for i in 0..<n:
    gParticleBuf[i] = Particle(x: float64(i), y: float64(i)*0.5,
                               mass: 1.0 + float64(i)*0.1,
                               color: Color(i mod 3))
  gParticleBuf

proc makeUserBuffer(n: int): OcheBuffer[User] {.oche.} =
  gUserBuf = newOche[User](n)
  for i in 0..<n:
    gUserBuf[i] = User(name: ("buf_user" & $i).toOcheStr, age: i+20, status: Active)
  gUserBuf

# ─── OcheBuffer as INPUT param ────────────────────────────────────────────────

proc sumIntBuffer(buf: OcheBuffer[int]): int {.oche.} =
  ## Accept an existing SharedListView/OcheBuffer and sum its values.
  var total = 0
  for i in 0..<buf.len: total += buf[i]
  total

proc doubleIntBuffer(buf: OcheBuffer[int]): OcheBuffer[int] {.oche.} =
  ## Take a buffer, return a new buffer with every element doubled.
  # FIX: ใช้ gDoubleBuf แยกจาก gIntBuf เพื่อไม่ให้ทับ pointer ที่ makeIntBuffer return ไปแล้ว
  gDoubleBuf = newOche[int](buf.len)
  for i in 0..<buf.len: gDoubleBuf[i] = buf[i] * 2
  gDoubleBuf

proc countActiveUsers(buf: OcheBuffer[User]): int {.oche.} =
  ## Count users with Active status in a User buffer.
  var count = 0
  for i in 0..<buf.len:
    if buf[i].status == Active: inc count
  count

# ─── OcheArray (fast array input) ─────────────────────────────────────────────

proc multiplyArray(arr: OcheArray[float64], factor: float64): OcheBuffer[float64] {.oche.} =
  gFloatBuf = newOche[float64](arr.len)
  for i in 0..<arr.len: gFloatBuf[i] = arr[i] * factor
  gFloatBuf

proc dotProduct(a, b: OcheArray[float64]): float64 {.oche.} =
  ## Dot product of two arrays (must be same length).
  var sum = 0.0
  let n = min(a.len, b.len)
  for i in 0..<n: sum += a[i] * b[i]
  sum

# ─── OchePtr (true zero-copy input) ───────────────────────────────────────────

proc sumIntsPtr(arr: OchePtr[int]): int {.oche.} =
  var total = 0
  for v in arr: total += v
  total

proc negateIntsPtr(arr: OchePtr[int]): OcheBuffer[int] {.oche.} =
  ## Return a new buffer with every element negated.
  gNegBuf = newOche[int](arr.len)
  for i in 0..<arr.len: gNegBuf[i] = -arr[i]
  gNegBuf

# ─── Error handling ───────────────────────────────────────────────────────────

proc riskyDivide(a, b: int): int {.oche.} =
  if b == 0: raise newException(ValueError, "division by zero")
  a div b

proc riskyUser(name: string): User {.oche.} =
  if name.len == 0: raise newException(ValueError, "name cannot be empty")
  User(name: name.toOcheStr, age: 1, status: Active)

# ─── Mutation via view / share ────────────────────────────────────────────────

proc resetPoint(p: Point): Point {.oche.} =
  ## Returns a zeroed copy — used to verify struct param pass-by-value.
  Point(x: 0.0, y: 0.0)

# ─── Generate ─────────────────────────────────────────────────────────────────

generate()