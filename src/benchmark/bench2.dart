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

// --- DART SIDE: IMAGE PROCESSING (4K) ---

class PixelDart {
  int r, g, b, a;
  PixelDart(this.r, this.g, this.b, this.a);
}

void processImageDart(List<PixelDart> image) {
  for (var i = 0; i < image.length; i++) {
    final px = image[i];
    final avg = (px.r * 0.3 + px.g * 0.59 + px.b * 0.11).toInt();
    px.r = avg;
    px.g = avg;
    px.b = avg;
  }
}

// --- DART SIDE: PHYSICS COLLISIONS ---

class EntityDart {
  double x, y, radius;
  bool colliding;
  EntityDart(this.x, this.y, this.radius, this.colliding);
}

void detectCollisionsDart(List<EntityDart> ents) {
  int n = ents.length;
  for (var i = 0; i < n; i++) ents[i].colliding = false;
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final dx = ents[i].x - ents[j].x;
      final dy = ents[i].y - ents[j].y;
      final distSq = dx * dx + dy * dy;
      final limit = ents[i].radius + ents[j].radius;
      if (distSq < limit * limit) {
        ents[i].colliding = true;
        ents[j].colliding = true;
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
  print("  - Nim+Oche:  ${sw2.elapsedMilliseconds}ms");
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
    "N-Body (10M Compute Iter)",
    () => nbodyDart(10000000),
    () => oche.nbodyNim(10000000),
  );

  runBench(
    "Fannkuch-Redux (N=11)",
    () => fannkuchDart(11),
    () => oche.fannkuchNim(11),
  );

  final dartImg = List.generate(
    3840 * 2160,
    (i) => PixelDart(i % 256, (i ~/ 2) % 256, 64, 255),
    growable: false,
  );
  oche.initImage(3840, 2160);
  runBench(
    "4K Grayscale Filter (8.2M Pixels Mutated)",
    () => processImageDart(dartImg),
    () => oche.processImageGrayscale(),
  );

  final dartEnts = List.generate(
    10000,
    (i) => EntityDart((i % 1000).toDouble(), (i ~/ 100).toDouble(), 5.0, false),
    growable: false,
  );
  oche.initEntities(10000);
  runBench(
    "Physics Collision O(N²) (10K Objects = 100M Checks)",
    () => detectCollisionsDart(dartEnts),
    () => oche.detectCollisions(),
  );

  print("\n==========================================");
  print("   🏁 BATTLE COMPLETE! 🏁      ");
  print("==========================================");
}
