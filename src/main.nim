import oche

type
  Point {.oche.} = object
    x, y: float

# โหมดปกติ: จะถูก Copy กลับไปเป็น List ใน Dart
proc getPointsCopy(n: int): seq[Point] {.oche.} =
  result = newSeq[Point](n)
  for i in 0..<n:
    result[i] = Point(x: i.float, y: i.float * 2)

# โหมด View: Dart จะอ่าน Memory ตรงๆ (Zero-Copy)
proc getPointsView(n: int): seq[Point] {.oche: view.} =
  result = newSeq[Point](n)
  for i in 0..<n:
    result[i] = Point(x: i.float, y: i.float * 2)

generate("nlib.dart")
