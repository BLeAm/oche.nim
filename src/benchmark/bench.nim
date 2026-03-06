import ../oche
import std/math
import std/random

# CASE A: Monte Carlo Pi (Pure Logic - 100 Million Iterations)
proc monteCarloPiNim(iterations: int): float {.oche.} =
  var count = 0
  var x, y: float
  # ใช้ RNG ที่เร็วที่สุดสำหรับ Benchmarking
  for i in 1..iterations:
    x = rand(1.0)
    y = rand(1.0)
    if x*x + y*y <= 1.0:
      inc count
  return 4.0 * (count.float / iterations.float)

# CASE B: Mandelbrot Set (Complex Math - 1000x1000)
proc mandelbrotNim(width, height, maxIter: int): seq[int] {.oche.} =
  result = newSeq[int](width * height)
  for y in 0..<height:
    let cy = -1.5 + 3.0 * y.float / height.float
    for x in 0..<width:
      let cx = -2.0 + 3.0 * x.float / width.float
      var zx = 0.0
      var zy = 0.0
      var count = 0
      while zx*zx + zy*zy <= 4.0 and count < maxIter:
        let temp = zx*zx - zy*zy + cx
        zy = 2.0 * zx * zy + cy
        zx = temp
        inc count
      result[y * width + x] = count

generate("nlib_bench.dart")
