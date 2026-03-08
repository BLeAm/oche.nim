import ../oche
import std/[math, sequtils]

type 
  Body {.porche.} = object
    x, y, z, vx, vy, vz, mass: float64

  Vec3 {.porche.} = object
    x, y, z: float64

# [1] N-Body
proc nbodyNim(n: int): float64 {.porche.} =
  var bodies = @[
    Body(mass: 39.478), 
    Body(x: 4.84, y: -1.16, z: -0.103, vx: 0.606, vy: 2.812, vz: -0.025, mass: 0.037)
  ]
  let dt = 0.01
  for i in 0..<n:
    let dx = bodies[0].x - bodies[1].x
    let dy = bodies[0].y - bodies[1].y
    let dz = bodies[0].z - bodies[1].z
    let d2 = dx*dx + dy*dy + dz*dz
    let mag = dt / (d2 * sqrt(d2))
    bodies[0].vx -= dx * bodies[1].mass * mag
    bodies[0].x += dt * bodies[0].vx
  return bodies[0].x

# [2] Spectral Norm (แก้จุด error 'j' ตรงนี้ครับ)
proc A(i, j: int): float64 = 1.0 / (((i + j) * (i + j + 1) div 2 + i + 1).float64)

proc spectralNormNim(n: int): float64 {.porche.} =
  var u = newSeqWith(n, 1.0)
  var v = newSeq[float64](n)
  for _ in 0..9:
    for i in 0..<n:
      v[i] = 0.0
      for j in 0..<n: v[i] += A(i, j) * u[j]
    for i in 0..<n:
      u[i] = 0.0
      # แก้จาก 0..<j เป็น 0..<n
      for j in 0..<n: u[i] += A(j, i) * v[j]
  return sqrt(u[0])

# [3] Zero-Copy View
proc generateLargeArrayView(n: int): OcheBuffer[Vec3] {.porche.} =
  result = newOche[Vec3](n) 
  for i in 0..<n:
    result[i] = Vec3(x: i.float, y: i.float * 2.0, z: i.float * 3.0)

generatePython("nlib_full.py")