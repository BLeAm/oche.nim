import 'nlib_bench2.dart';
import 'dart:math' as math;

// --- DART SIDE: N-BODY ---

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
const DAYS_PER_YEAR = 365.24;

double nbodyDart(int iterations) {
  final bodies = [
    Body(mass: SOLAR_MASS),
    Body(
      x: 4.84143144246472090e+00,
      y: -1.16032004402742839e+00,
      z: -1.03622044486121090e-01,
      vx: 1.66007664274403694e-03 * DAYS_PER_YEAR,
      vy: 7.69901118419740425e-03 * DAYS_PER_YEAR,
      vz: -6.90460016972063023e-05 * DAYS_PER_YEAR,
      mass: 9.54791938424326609e-04 * SOLAR_MASS,
    ),
  ];

  // Offset Momentum
  var px = 0.0, py = 0.0, pz = 0.0;
  for (final b in bodies) {
    px += b.vx * b.mass;
    py += b.vy * b.mass;
    pz += b.vz * b.mass;
  }
  bodies[0].vx = -px / SOLAR_MASS;
  bodies[0].vy = -py / SOLAR_MASS;
  bodies[0].vz = -pz / SOLAR_MASS;

  for (var k = 0; k < iterations; k++) {
    for (var i = 0; i < bodies.length; i++) {
      final bi = bodies[i];
      for (var j = i + 1; j < bodies.length; j++) {
        final bj = bodies[j];
        final dx = bi.x - bj.x;
        final dy = bi.y - bj.y;
        final dz = bi.z - bj.z;
        final dSq = dx * dx + dy * dy + dz * dz;
        final dist = math.sqrt(dSq);
        final mag = 0.01 / (dSq * dist);
        bi.vx -= dx * bj.mass * mag;
        bi.vy -= dy * bj.mass * mag;
        bi.vz -= dz * bj.mass * mag;
        bj.vx += dx * bi.mass * mag;
        bj.vy += dy * bi.mass * mag;
        bj.vz += dz * bi.mass * mag;
      }
      bi.x += 0.01 * bi.vx;
      bi.y += 0.01 * bi.vy;
      bi.z += 0.01 * bi.vz;
    }
  }

  var e = 0.0;
  for (var i = 0; i < bodies.length; i++) {
    final bi = bodies[i];
    e += 0.5 * bi.mass * (bi.vx * bi.vx + bi.vy * bi.vy + bi.vz * bi.vz);
    for (var j = i + 1; j < bodies.length; j++) {
      final bj = bodies[j];
      final dx = bi.x - bj.x;
      final dy = bi.y - bj.y;
      final dz = bi.z - bj.z;
      e -= (bi.mass * bj.mass) / math.sqrt(dx * dx + dy * dy + dz * dz);
    }
  }
  return e;
}

// --- DART SIDE: FANNKUCH ---

int fannkuchDart(int n) {
  final p = List.generate(n, (i) => i);
  final q = List.filled(n, 0);
  final s = List.generate(n, (i) => i);
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

// --- HARNESS ---

void runBench(String name, Function pure, Function oche) {
  print("\n[*] BENCHMARK: $name");
  final sw1 = Stopwatch()..start();
  pure();
  sw1.stop();
  print("  - Pure Dart: ${sw1.elapsedMilliseconds}ms");
  final sw2 = Stopwatch()..start();
  oche();
  sw2.stop();
  print("  - Nim+Oche:   ${sw2.elapsedMilliseconds}ms");
  final ratio = (sw1.elapsedMicroseconds / sw2.elapsedMicroseconds)
      .toStringAsFixed(2);
  print(
    "  >> Winner: ${sw1.elapsedMicroseconds > sw2.elapsedMicroseconds ? "Nim" : "Dart"} (Ratio: $ratio x)",
  );
}

void main() {
  print("==========================================");
  print("    🏅 THE COMPUTER LANGUAGE BATTLE 🏅   ");
  print("==========================================\n");

  runBench(
    "N-Body (10,000,000 iterations)",
    () => nbodyDart(10000000),
    () => nbodyNim(10000000),
  );

  runBench(
    "Fannkuch-Redux (N=11)",
    () => fannkuchDart(11),
    () => fannkuchNim(11),
  );

  print("\n==========================================");
  print("   🏁 BATTLE COMPLETE! 🏁      ");
  print("==========================================");
}
