import 'nlib_suite.dart';
import 'dart:math' as math;

// --- DART SIDE IMPLEMENTATIONS ---

class Body {
  double x, y, z, vx, vy, vz, mass;
  Body({
    this.x = 0,
    this.y = 0,
    this.z = 0,
    this.vx = 0,
    this.vy = 0,
    this.vz = 0,
    required this.mass,
  });
}

const SOLAR_MASS = 4 * math.pi * math.pi;

double nbodyDart(int n) {
  final bodies = [
    Body(mass: SOLAR_MASS),
    Body(
      x: 4.84,
      y: -1.16,
      z: -0.103,
      vx: 1.66e-3 * 365.24,
      vy: 7.69e-3 * 365.24,
      vz: -6.90e-5 * 365.24,
      mass: 9.54e-4 * SOLAR_MASS,
    ),
  ];
  for (var k = 0; k < n; k++) {
    for (var i = 0; i < bodies.length; i++) {
      for (var j = i + 1; j < bodies.length; j++) {
        final dx = bodies[i].x - bodies[j].x,
            dy = bodies[i].y - bodies[j].y,
            dz = bodies[i].z - bodies[j].z;
        final d2 = dx * dx + dy * dy + dz * dz,
            mag = 0.01 / (d2 * math.sqrt(d2));
        bodies[i].vx -= dx * bodies[j].mass * mag;
        bodies[i].vy -= dy * bodies[j].mass * mag;
        bodies[i].vz -= dz * bodies[j].mass * mag;
        bodies[j].vx += dx * bodies[i].mass * mag;
        bodies[j].vy += dy * bodies[i].mass * mag;
        bodies[j].vz += dz * bodies[i].mass * mag;
      }
      bodies[i].x += 0.01 * bodies[i].vx;
      bodies[i].y += 0.01 * bodies[i].vy;
      bodies[i].z += 0.01 * bodies[i].vz;
    }
  }
  return bodies[0].x;
}

int fannkuchDart(int n) {
  final p = List.generate(n, (i) => i),
      q = List.filled(n, 0),
      s = List.generate(n, (i) => i);
  var maxFlips = 0, sign = 1;
  while (true) {
    var q0 = p[0];
    if (q0 != 0) {
      for (var i = 1; i < n; i++) q[i] = p[i];
      var flips = 1;
      while (true) {
        var qq = q[q0];
        if (qq == 0) {
          if (flips > maxFlips) maxFlips = flips;
          break;
        }
        q[q0] = q0;
        if (q0 >= 3) {
          var i = 1, j = q0 - 1;
          while (i < j) {
            final t = q[i];
            q[i] = q[j];
            q[j] = t;
            i++;
            j--;
          }
        }
        q0 = qq;
        flips++;
      }
    }
    if (sign == 1) {
      final t = p[0];
      p[0] = p[1];
      p[1] = t;
      sign = -1;
    } else {
      final t = p[1];
      p[1] = p[2];
      p[2] = t;
      sign = 1;
      for (var i = 2; i < n; i++) {
        final sx = s[i];
        if (sx != 0) {
          s[i] = sx - 1;
          break;
        }
        if (i == n - 1) return maxFlips;
        s[i] = i;
        final p0 = p[0];
        for (var j = 0; j <= i; j++) p[j] = p[j + 1];
        p[i + 1] = p0;
      }
    }
  }
}

double A(int i, int j) => 1.0 / ((i + j) * (i + j + 1) / 2 + i + 1);
double spectralNormDart(int n) {
  final u = List.filled(n, 1.0),
      v = List.filled(n, 0.0),
      tmp = List.filled(n, 0.0);
  for (var k = 0; k < 10; k++) {
    for (var i = 0; i < n; i++) {
      tmp[i] = 0.0;
      for (var j = 0; j < n; j++) tmp[i] += A(i, j) * u[j];
    }
    for (var i = 0; i < n; i++) {
      v[i] = 0.0;
      for (var j = 0; j < n; j++) v[i] += A(j, i) * tmp[j];
    }
    for (var i = 0; i < n; i++) {
      tmp[i] = 0.0;
      for (var j = 0; j < n; j++) tmp[i] += A(i, j) * v[j];
    }
    for (var i = 0; i < n; i++) {
      u[i] = 0.0;
      for (var j = 0; j < n; j++) u[i] += A(j, i) * tmp[j];
    }
  }
  var vBv = 0.0, vv = 0.0;
  for (var i = 0; i < n; i++) {
    vBv += u[i] * v[i];
    vv += v[i] * v[i];
  }
  return math.sqrt(vBv / vv);
}

class Node {
  Node? left, right;
  Node({this.left, this.right});
}

Node makeTree(int d) =>
    d <= 0 ? Node() : Node(left: makeTree(d - 1), right: makeTree(d - 1));
int checkTree(Node? n) =>
    n?.left == null ? 1 : 1 + checkTree(n!.left) + checkTree(n.right);
int binaryTreesDart(int d) => checkTree(makeTree(d));

int mandelbrotDart(int n) {
  var count = 0;
  for (var y = 0; y < n; y++) {
    final cy = -1.5 + 3.0 * y / n;
    for (var x = 0; x < n; x++) {
      final cx = -2.0 + 3.0 * x / n;
      var zx = 0.0, zy = 0.0, i = 0;
      while (zx * zx + zy * zy <= 4.0 && i < 1000) {
        final t = zx * zx - zy * zy + cx;
        zy = 2.0 * zx * zy + cy;
        zx = t;
        i++;
      }
      if (i == 1000) count++;
    }
  }
  return count;
}

// --- HARNESS ---

void run(String name, Function dartFn, Function nimFn) {
  print("\n[*] $name:");
  final sw1 = Stopwatch()..start();
  dartFn();
  sw1.stop();
  print("  - Pure Dart: ${sw1.elapsedMilliseconds}ms");
  final sw2 = Stopwatch()..start();
  nimFn();
  sw2.stop();
  print("  - Nim+Oche:   ${sw2.elapsedMilliseconds}ms");
  final ratio = (sw1.elapsedMicroseconds / sw2.elapsedMicroseconds)
      .toStringAsFixed(2);
  print(
    "  >> Winner: ${sw1.elapsedMicroseconds > sw2.elapsedMicroseconds ? 'Nim' : 'Dart'} ($ratio x)",
  );
}

void main() {
  print("==========================================");
  print("    🏎️  OCHE GRAND PRIX (BATTLE) 🏎️     ");
  print("==========================================\n");

  run(
    "1. N-Body (10,000,000 iterations)",
    () => nbodyDart(10000000),
    () => nbodyNim(10000000),
  );
  run(
    "2. Fannkuch-Redux (N=11)",
    () => fannkuchDart(11),
    () => fannkuchNim(11),
  );
  run(
    "3. Spectral-Norm (N=1500)",
    () => spectralNormDart(1500),
    () => spectralNormNim(1500),
  );
  run(
    "4. Binary-Trees (Depth=17)",
    () => binaryTreesDart(17),
    () => binaryTreesNim(17),
  );
  run(
    "5. Mandelbrot (N=1000)",
    () => mandelbrotDart(1000),
    () => mandelbrotNim(1000),
  );

  print("\n==========================================");
  print("    🏁 THE GRAND FINALE COMPLETE! 🏁     ");
  print("==========================================");
}
