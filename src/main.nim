import oche

type
  Point {.oche.} = object
    x, y: float

var globalBuffer: OcheBuffer[Point]

# 1. Standard Copy
proc getPointsCopy(n: int): seq[Point] {.oche.} =
  result = newSeq[Point](n)
  for i in 0..<n:
    result[i] = Point(x: i.float, y: i.float * 2)

# 2. Snapshot View (Read-Only)
proc getPointsView(n: int): seq[Point] {.oche: view.} =
  result = newSeq[Point](n)
  for i in 0..<n:
    result[i] = Point(x: i.float, y: i.float * 2)

# 3. Live Shared Buffer (Mutable + Auto ID + High Freq Optimization)
proc getPointsShared(n: int): OcheBuffer[Point] {.oche.} =
  globalBuffer = newOche[Point](n) # Using the new smart template!
  for i in 0..<n:
    globalBuffer[i] = Point(x: i.float, y: i.float * 2)
  return globalBuffer

# High frequency call test (Should be Lightning Fast, No Arena!)
proc updatePointFast(idx: int, x: float) {.oche.} =
  if idx < globalBuffer.len:
    globalBuffer[idx].x = x

proc printSharedPoint(idx: int) {.oche.} =
  if idx < globalBuffer.len:
    let p = globalBuffer[idx]
    echo "Nim (Live): globalBuffer[", idx, "] is now (", p.x, ", ", p.y, ")"

generate("nlib.dart")
