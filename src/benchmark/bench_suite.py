from nlib_suite import porche
import math
import time

class Body:
  def __init__(self, x, y, z, vx, vy, vz, mass):
    self.x = x
    self.y = y
    self.z = z
    self.vx = vx
    self.vy = vy
    self.vz = vz
    self.mass = mass


SOLAR_MASS = 4 * math.pi * math.pi

def nbody_python(n: int) -> float:
  bodies = [
    Body(0, 0, 0, 0, 0, 0, SOLAR_MASS),
    Body(4.84, -1.16, -0.103, 1.66e-3 * 365.24, 7.69e-3 * 365.24, -6.90e-5 * 365.24, 9.54e-4 * SOLAR_MASS)
  ]
  for _ in range(n):
    for i in range(len(bodies)):
      for j in range(i + 1, len(bodies)):
        dx = bodies[i].x - bodies[j].x
        dy = bodies[i].y - bodies[j].y
        dz = bodies[i].z - bodies[j].z
        d2 = dx*dx + dy*dy + dz*dz
        mag = 0.01 / (d2 * math.sqrt(d2))
        bodies[i].vx -= dx * bodies[j].mass * mag
        bodies[i].vy -= dy * bodies[j].mass * mag
        bodies[i].vz -= dz * bodies[j].mass * mag
        bodies[j].vx += dx * bodies[i].mass * mag
        bodies[j].vy += dy * bodies[i].mass * mag
        bodies[j].vz += dz * bodies[i].mass * mag
    for i in range(len(bodies)):
      bodies[i].x += 0.01 * bodies[i].vx
      bodies[i].y += 0.01 * bodies[i].vy
      bodies[i].z += 0.01 * bodies[i].vz
  return bodies[0].x

def fannkuch_python(n: int) -> int:
  p = list(range(n))
  q = [0] * n
  s = list(range(n))
  max_flips = 0
  sign = 1
  while True:
    q0 = p[0]
    if q0 != 0:
      for i in range(1, n):
        q[i] = p[i]
      flips = 1
      while True:
        qq = q[q0]
        if qq == 0:
          if flips > max_flips:
            max_flips = flips
          break
        q[q0] = q0
        if q0 >= 3:
          i = 1
          j = q0 - 1
          while i < j:
            q[i], q[j] = q[j], q[i]
            i += 1
            j -= 1
        q0 = qq
        flips += 1
    if sign == 1:
      t = p[0]
      p[0] = p[1]
      p[1] = t
      sign = -1
    else:
      t = p[1]
      p[1] = p[2]
      p[2] = t
      sign = 1
      for i in range(2, n):
        sx = s[i]
        if sx != 0:
          s[i] = sx - 1
          break
        if i == n - 1:
          return max_flips
        s[i] = i
        p0   = p[0]
        for j in range(i):
          p[j] = p[j + 1]
        p[i] = p0
def A(i, j: int) -> float:
  return 1.0 / ((i + j) * (i + j + 1) // 2 + i + 1)
def spectral_norm_python(n: int) -> float:
  u = [1.0] * n
  v = [0.0] * n
  tmp = [0.0] * n
  for _ in range(10):
    for i in range(n):
      tmp[i] = 0.0
      for j in range(n):
        tmp[i] += A(i, j) * u[j]
    for i in range(n):
      v[i] = 0.0
      for j in range(n):
        v[i] += A(j, i) * tmp[j]
    for i in range(n):
      tmp[i] = 0.0
      for j in range(n):
        tmp[i] += A(i, j) * v[j]
    for i in range(n):
      u[i] = 0.0
      for j in range(n):
        u[i] += A(j, i) * tmp[j]
  vBv = 0.0
  vv = 0.0
  for i in range(n):
    vBv += u[i] * v[i]
    vv += v[i] * v[i]
  return math.sqrt(vBv / vv)

class Node:
  def __init__(self, left=None, right=None):
    self.left = left
    self.right = right

def make_tree(d: int) -> Node:
  if d <= 0:
    return Node()
  return Node(make_tree(d - 1), make_tree(d - 1))

def check_tree(n: Node) -> int:
  if n.left is None:
    return 1
  return 1 + check_tree(n.left) + check_tree(n.right)

def binary_trees_python(d: int) -> int:
  tree = make_tree(d)
  return check_tree(tree)

def mandelbrot_python(n: int) -> int:
  count = 0
  for y in range(n):
    cy = -1.5 + 3.0 * y / n
    for x in range(n):
      cx = -2.0 + 3.0 * x / n
      zx = 0.0
      zy = 0.0
      i = 0
      while zx * zx + zy * zy <= 4.0 and i < 1000:
        t = zx * zx - zy * zy + cx
        zy = 2.0 * zx * zy + cy
        zx = t
        i += 1
      if i == 1000:
        count += 1
  return count

def run(name, pyFn, nimFn):
  print(f"\n[*] {name}")
  sw1 = time.time()
  pyFn()
  sw1 = time.time() - sw1
  print(f"  - Pure Python: {sw1 * 1000:.2f}ms")
  sw2 = time.time()
  nimFn()
  sw2 = time.time() - sw2
  print(f"  - Nim+Oche: {sw2 * 1000:.2f}ms")
  ratio = sw1 / sw2
  print(f"  >> Winner: {'Nim' if sw2 < sw1 else 'Python'} ({ratio:.2f}x)")

print("==========================================")
print("     🏎️  OCHE GRAND PRIX (BATTLE) 🏎️      ")
print("==========================================\n")

run(
  "1. N-Body (10,000,000 iterations)",
  lambda: nbody_python(10000000),
  lambda: porche.nbodyNim(10000000) ,
)
run(
  "2. Fannkuch-Redux (N=11)",
  lambda: fannkuch_python(11),
  lambda: porche.fannkuchNim(11),
)
run(
  "3. Spectral-Norm (N=1500)",
  lambda: spectral_norm_python(1500),
  lambda: porche.spectralNormNim(1500),
)
run(
  "4. Binary-Trees (Depth=17)",
  lambda: binary_trees_python(17),
  lambda: porche.binaryTreesNim(17),
)
run(
  "5. Mandelbrot (N=1000)",
  lambda: mandelbrot_python(1000),  
  lambda: porche.mandelbrotNim(1000),
)

print("\n==========================================")
print("     🏁 THE GRAND FINALE COMPLETE! 🏁     ")
print("========================================== ")