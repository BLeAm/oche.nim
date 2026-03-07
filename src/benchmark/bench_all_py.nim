import ../oche
import std/[math, sequtils]

# --- Shared Structures ---
type 
  Body {.porche.} = object
    x, y, z, vx, vy, vz, mass: float64

  Vec3 {.porche.} = object
    x, y, z: float64

# [1] N-Body Simulation (Logic จาก bench2.nim)
const SOLAR_MASS = 4 * PI * PI
const DAYS_PER_YEAR = 365.24

proc nbodyNim(n: int): float64 {.porche.} =
  var bodies = @[
    Body(mass: SOLAR_MASS),
    Body(x: 4.84, y: -1.16, z: -0.103, vx: 1.66e-3 * DAYS_PER_YEAR, 
         vy: 7.69e-3 * DAYS_PER_YEAR, vz: -6.90e-5 * DAYS_PER_YEAR, 
         mass: 9.54e-4 * SOLAR_MASS)
  ]
  let dt = 0.01
  for i in 0..<n:
    for j in 0..<bodies.len:
      for k in j+1..<bodies.len:
        let dx = bodies[j].x - bodies[k].x
        let dy = bodies[j].y - bodies[k].y
        let dz = bodies[j].z - bodies[k].z
        let d2 = dx*dx + dy*dy + dz*dz
        let mag = dt / (d2 * sqrt(d2))
        bodies[j].vx -= dx * bodies[k].mass * mag
        bodies[k].vx += dx * bodies[j].mass * mag
    for j in 0..<bodies.len:
      bodies[j].x += dt * bodies[j].vx
  return bodies[0].x

# [2] Spectral Norm (Logic จาก bench_suite.nim)
proc A(i, j: int): float64 = 1.0 / ((i + j) * (i + j + 1) div 2 + i + 1).float64

proc spectralNormNim(n: int): float64 {.porche.} =
  var u = newSeqWith(n, 1.0)
  var v = newSeq[float64](n)
  for _ in 0..9:
    # Simplified power method for benchmark
    for i in 0..<n:
      v[i] = 0.0
      for j in 0..<n: v[i] += A(i, j) * u[j]
    for i in 0..<n:
      u[i] = 0.0
      for j in 0..<n: u[i] += A(j, i) * v[j]
  return sqrt(u[0])

# [3] Zero-Copy View (Logic จาก bench3.nim)
var cachedArray: seq[Vec3]
proc generateLargeArrayView(n: int): seq[Vec3] {.porche: view.} =
  cachedArray = newSeq[Vec3](n)
  for i in 0..<n:
    cachedArray[i] = Vec3(x: i.float, y: i.float * 2.0, z: i.float * 3.0)
  return cachedArray

generatePython("nlib_all_bench.py")