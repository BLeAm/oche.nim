import oche

type
  Point {.oche.} = object
    x, y: float

var globalShared: OcheShared[Point]

# 1. Standard Copy
proc getPointsCopy(n: int): seq[Point] {.oche.} =
  result = newSeq[Point](n)
  for i in 0..<n:
    result[i] = Point(x: i.float, y: i.float * 2)

# 2. View Mode (Zero-Copy from a seq - still has 1 initial copy to FFI buffer)
proc getPointsView(n: int): seq[Point] {.oche: view.} =
  result = newSeq[Point](n)
  for i in 0..<n:
    result[i] = Point(x: i.float, y: i.float * 2)

# 3. Shared Mode (True Zero-Copy & Mutable)
proc getPointsShared(n: int): OcheShared[Point] {.oche.} =
  globalShared = newOcheShared[Point](n)
  for i in 0..<n:
    globalShared[i] = Point(x: i.float, y: i.float * 2)
  return globalShared

proc printSharedPoint(idx: int) {.oche.} =
  if idx < globalShared.len:
    let p = globalShared[idx]
    echo "Nim: globalShared[", idx, "] is now (", p.x, ", ", p.y, ")"

generate("nlib.dart")
