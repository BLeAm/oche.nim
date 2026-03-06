import ../oche
import std/math

# --- CASE 1: N-Body Simulation ---
# (เน้น Floating Point & ODE Integration)

type Body = object
  x, y, z, vx, vy, vz, mass: float64

const
  DAYS_PER_YEAR = 365.24
  SOLAR_MASS = 4 * PI * PI

proc offsetMomentum(bodies: var seq[Body]) =
  var px, py, pz = 0.0
  for b in bodies:
    px += b.vx * b.mass
    py += b.vy * b.mass
    pz += b.vz * b.mass
  bodies[0].vx = -px / SOLAR_MASS
  bodies[0].vy = -py / SOLAR_MASS
  bodies[0].vz = -pz / SOLAR_MASS

proc advance(bodies: var seq[Body], dt: float64) =
  for i in 0..<bodies.len:
    var b = bodies[i]
    for j in i + 1 ..< bodies.len:
      let b2 = bodies[j]
      let dx = b.x - b2.x
      let dy = b.y - b2.y
      let dz = b.z - b2.z
      let distanceSq = dx*dx + dy*dy + dz*dz
      let distance = sqrt(distanceSq)
      let mag = dt / (distanceSq * distance)
      
      bodies[i].vx -= dx * b2.mass * mag
      bodies[i].vy -= dy * b2.mass * mag
      bodies[i].vz -= dz * b2.mass * mag
      
      bodies[j].vx += dx * b.mass * mag
      bodies[j].vy += dy * b.mass * mag
      bodies[j].vz += dz * b.mass * mag
    bodies[i].x += dt * bodies[i].vx
    bodies[i].y += dt * bodies[i].vy
    bodies[i].z += dt * bodies[i].vz

proc nbodyNim(iterations: int): float64 {.oche.} =
  var bodies = @[
    Body(mass: SOLAR_MASS), # Sun
    Body(x: 4.84143144246472090e+00, y: -1.16032004402742839e+00, z: -1.03622044486121090e-01,
         vx: 1.66007664274403694e-03 * DAYS_PER_YEAR, vy: 7.69901118419740425e-03 * DAYS_PER_YEAR, vz: -6.90460016972063023e-05 * DAYS_PER_YEAR,
         mass: 9.54791938424326609e-04 * SOLAR_MASS), # Jupiter
    # (เพิ่มดาวเคราะห์อื่นๆ แบบย่อเพื่อ Benchmark)
  ]
  offsetMomentum(bodies)
  for i in 1..iterations:
    advance(bodies, 0.01)
  
  # คืนค่าพลังงานรวม (Total Energy)
  var e = 0.0
  for i in 0..<bodies.len:
    let b = bodies[i]
    e += 0.5 * b.mass * (b.vx*b.vx + b.vy*b.vy + b.vz*b.vz)
    for j in i + 1 ..< bodies.len:
      let b2 = bodies[j]
      let dx = b.x - b2.x
      let dy = b.y - b2.y
      let dz = b.z - b2.z
      e -= (b.mass * b2.mass) / sqrt(dx*dx + dy*dy + dz*dz)
  return e

# --- CASE 2: Fannkuch-Redux ---
# (เน้น Array Manipulation & Permutation)

proc fannkuchNim(n: int): int {.oche.} =
  var p, q, s: seq[int]
  p = newSeq[int](n)
  q = newSeq[int](n)
  s = newSeq[int](n)
  for i in 0..<n: p[i] = i; s[i] = i
  
  var maxFlips = 0
  var sign = 1
  var check = 0
  
  while true:
    var q0 = p[0]
    if q0 != 0:
      for i in 1..<n: q[i] = p[i]
      var flips = 1
      while true:
        var qq = q[q0]
        if qq == 0:
          if flips > maxFlips: maxFlips = flips
          break
        q[q0] = q0
        if q0 >= 3:
          var i = 1; var j = q0 - 1
          while i < j: swap(q[i], q[j]); inc i; dec j
        q0 = qq
        inc flips
    
    # Permutation next
    if sign == 1: swap(p[0], p[1]); sign = -1
    else:
      swap(p[1], p[2]); sign = 1
      for i in 2..<n:
        let sx = s[i]
        if sx != 0: s[i] = sx - 1; break
        if i == n - 1: return maxFlips
        s[i] = i
        let t = p[0]
        for j in 0..i: p[j] = p[j+1]
        p[i+1] = t

# --- CASE 3: Heavy Image Processing ---
# (Grayscale Conversion on a 4K image 3840x2160 = ~8.2M pixels)

type
  Pixel {.oche.} = object
    r, g, b, a: uint8

var imgBuffer: OcheBuffer[Pixel]

proc initImage(w, h: int): OcheBuffer[Pixel] {.oche.} =
  let size = w * h
  imgBuffer = newOche[Pixel](size)
  for i in 0 ..< size:
    imgBuffer[i] = Pixel(r: (i mod 256).uint8, g: ((i div 2) mod 256).uint8, b: 64, a: 255)
  return imgBuffer

proc processImageGrayscale() {.oche.} =
  let p = imgBuffer.dataPtr
  let n = imgBuffer.len
  for i in 0 ..< n:
    let r = p[i].r.float32
    let g = p[i].g.float32
    let b = p[i].b.float32
    let avg = (r * 0.3f + g * 0.59f + b * 0.11f).uint8
    p[i].r = avg
    p[i].g = avg
    p[i].b = avg

# --- CASE 4: Physics Collision Detection ---
# O(N^2) complexity checks on 10,000 entities (100M checks)

type
  Entity {.oche.} = object
    x, y, radius: float32
    colliding: bool

var entities: OcheBuffer[Entity]

proc initEntities(n: int): OcheBuffer[Entity] {.oche.} =
  entities = newOche[Entity](n)
  let p = entities.dataPtr
  for i in 0 ..< n:
    p[i] = Entity(x: (i mod 1000).float32, y: (i div 100).float32, radius: 5.0f, colliding: false)
  return entities

proc detectCollisions() {.oche.} =
  let p = entities.dataPtr
  let n = entities.len
  for i in 0 ..< n: p[i].colliding = false
  for i in 0 ..< n:
    for j in i + 1 ..< n:
      let dx = p[i].x - p[j].x
      let dy = p[i].y - p[j].y
      let distSq = dx*dx + dy*dy
      let limit = p[i].radius + p[j].radius
      if distSq < limit * limit:
        p[i].colliding = true
        p[j].colliding = true

generate("nlib_bench2.dart")
