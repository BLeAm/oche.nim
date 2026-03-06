import ../oche
import std/[math, sequtils]

# 1. N-Body
type Body = object
  x, y, z, vx, vy, vz, mass: float64

const SOLAR_MASS = 4 * PI * PI
const DAYS_PER_YEAR = 365.24

proc advance(bodies: var seq[Body], dt: float64) =
  for i in 0..<bodies.len:
    for j in i + 1 ..< bodies.len:
      let dx = bodies[i].x - bodies[j].x
      let dy = bodies[i].y - bodies[j].y
      let dz = bodies[i].z - bodies[j].z
      let d2 = dx*dx + dy*dy + dz*dz
      let mag = dt / (d2 * sqrt(d2))
      bodies[i].vx -= dx * bodies[j].mass * mag
      bodies[i].vy -= dy * bodies[j].mass * mag
      bodies[i].vz -= dz * bodies[j].mass * mag
      bodies[j].vx += dx * bodies[i].mass * mag
      bodies[j].vy += dy * bodies[i].mass * mag
      bodies[j].vz += dz * bodies[i].mass * mag
  for i in 0..<bodies.len:
    bodies[i].x += dt * bodies[i].vx
    bodies[i].y += dt * bodies[i].vy
    bodies[i].z += dt * bodies[i].vz

proc nbodyNim(n: int): float64 {.oche.} =
  var bodies = @[
    Body(mass: SOLAR_MASS),
    Body(x: 4.84, y: -1.16, z: -0.103, vx: 1.66e-3 * DAYS_PER_YEAR, vy: 7.69e-3 * DAYS_PER_YEAR, vz: -6.90e-5 * DAYS_PER_YEAR, mass: 9.54e-4 * SOLAR_MASS)
  ]
  for i in 1..n: advance(bodies, 0.01)
  return bodies[0].x

# 2. Fannkuch-Redux
proc fannkuchNim(n: int): int {.oche.} =
  var p = newSeq[int](n); var q = newSeq[int](n); var s = newSeq[int](n)
  for i in 0..<n: p[i] = i; s[i] = i
  var maxFlips = 0; var sign = 1
  while true:
    var q0 = p[0]
    if q0 != 0:
      for i in 1..<n: q[i] = p[i]
      var flips = 1
      while true:
        var qq = q[q0]
        if qq == 0: (if flips > maxFlips: maxFlips = flips); break
        q[q0] = q0
        if q0 >= 3:
          var i = 1; var j = q0 - 1
          while i < j: swap(q[i], q[j]); inc i; dec j
        q0 = qq; inc flips
    if sign == 1: swap(p[0], p[1]); sign = -1
    else:
      swap(p[1], p[2]); sign = 1
      for i in 2..<n:
        let sx = s[i]
        if sx != 0: s[i] = sx - 1; break
        if i == n - 1: return maxFlips
        s[i] = i; let t = p[0]
        for j in 0..i: p[j] = p[j+1]
        p[i+1] = t

# 3. Spectral-Norm
proc A(i, j: int): float64 = 1.0 / ((i + j) * (i + j + 1) div 2 + i + 1).float64

proc multiplyAv(v: seq[float64], Av: var seq[float64]) =
  for i in 0..<v.len:
    Av[i] = 0.0
    for j in 0..<v.len: Av[i] += A(i, j) * v[j]

proc multiplyAtv(v: seq[float64], Atv: var seq[float64]) =
  for i in 0..<v.len:
    Atv[i] = 0.0
    for j in 0..<v.len: Atv[i] += A(j, i) * v[j]

proc spectralNormNim(n: int): float64 {.oche.} =
  var u = newSeqWith(n, 1.0); var v = newSeq[float64](n); var tmp = newSeq[float64](n)
  for i in 0..9:
    multiplyAv(u, tmp); multiplyAtv(tmp, v)
    multiplyAv(v, tmp); multiplyAtv(tmp, u)
  var vBv, vv = 0.0
  for i in 0..<n: vBv += u[i] * v[i]; vv += v[i] * v[i]
  return sqrt(vBv / vv)

# 4. Binary-Trees (Allocation Test)
type Node = ref object
  left, right: Node

proc makeTree(depth: int): Node =
  if depth <= 0: return Node(left: nil, right: nil)
  return Node(left: makeTree(depth - 1), right: makeTree(depth - 1))

proc checkTree(node: Node): int =
  if node.left.isNil: return 1
  return 1 + checkTree(node.left) + checkTree(node.right)

proc binaryTreesNim(depth: int): int {.oche.} =
  let tree = makeTree(depth)
  return checkTree(tree)

# 5. Mandelbrot
proc mandelbrotNim(n: int): int {.oche.} =
  var count = 0
  for y in 0..<n:
    let cy = -1.5 + 3.0 * y.float / n.float
    for x in 0..<n:
      let cx = -2.0 + 3.0 * x.float / n.float
      var zx = 0.0; var zy = 0.0; var i = 0
      while zx*zx + zy*zy <= 4.0 and i < 1000:
        let t = zx*zx - zy*zy + cx
        zy = 2.0 * zx * zy + cy; zx = t; inc i
      if i == 1000: inc count
  return count

generate("nlib_suite.dart")
