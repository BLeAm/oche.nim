import ../oche

type
  Vec3 {.oche.} = object
    x, y, z: float

# ===============================================
# SCENARIO 1: Large Array Generation & Summation
# ===============================================

# 1.1 Copy Mode (Old FFI Way - High Overhead)
proc generateLargeArrayCopy(n: int): seq[Vec3] {.oche.} =
  result = newSeq[Vec3](n)
  for i in 0..<n:
    result[i] = Vec3(x: i.float, y: (i*2).float, z: (i*3).float)

# 1.2 View Mode (Zero-Copy Read-Only)
var cachedArray: seq[Vec3]
proc generateLargeArrayView(n: int): seq[Vec3] {.oche: view.} =
  cachedArray = newSeq[Vec3](n)
  for i in 0..<n:
    cachedArray[i] = Vec3(x: i.float, y: (i*2).float, z: (i*3).float)
  return cachedArray

# ===============================================
# SCENARIO 2: Particle System Update (Mutation)
# ===============================================

var particleBuffer: OcheBuffer[Vec3]

proc initParticles(n: int): OcheBuffer[Vec3] {.oche.} =
  particleBuffer = newOche[Vec3](n)
  for i in 0..<n:
    particleBuffer[i] = Vec3(x: 0, y: 0, z: 0)
  return particleBuffer

proc nimUpdateParticles(dt: float) {.oche.} =
  for i in 0..<particleBuffer.len:
    particleBuffer[i].x += dt
    particleBuffer[i].y += dt * 2.0
    particleBuffer[i].z += dt * 3.0

generate("nlib_bench3.dart")
