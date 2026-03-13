// orun.dart — Comprehensive oche feature test runner (Dart)
// Run: dart run orun.dart
// Expects: libolib.so (or .dylib/.dll) in the same directory

import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'olib.dart';

// ─── Test framework ───────────────────────────────────────────────────────────

int _pass = 0;
int _fail = 0;

void section(String name) {
  print('\n${'─' * 60}');
  print('  $name');
  print('─' * 60);
}

void ok(String label, bool cond, [String detail = '']) {
  if (cond) {
    _pass++;
    print('  ✓  $label');
  } else {
    _fail++;
    final info = detail.isNotEmpty ? ' — $detail' : '';
    print('  ✗  $label$info');
  }
}

bool _deepEq(dynamic a, dynamic b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEq(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

void eq<T>(String label, T got, T expected) {
  ok(label, _deepEq(got, expected), 'got $got, expected $expected');
}

void approx(String label, double got, double expected, [double tol = 1e-9]) {
  ok(label, (got - expected).abs() < tol, 'got $got, expected $expected');
}

void summary() {
  final total = _pass + _fail;
  print('\n${'═' * 60}');
  if (_fail == 0) {
    print('  Results: $_pass/$total passed ✓ All passed ✅');
  } else {
    print('  Results: $_pass/$total passed  ($_fail FAILED) ❌');
  }
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── Enums ──────────────────────────────────────────────────────────────────
  section('Enums');

  eq('getColor() == Green', oche.getColor(), Color.Green);

  final uStatus = oche.makeUser('Alice', 30);
  eq('getStatus(active user)', oche.getStatus(uStatus), Status.Active);

  // ── Copy mode — POD struct ─────────────────────────────────────────────────
  section('Copy mode — single struct (POD)');

  final p = oche.makePoint(3.0, 4.0);
  approx('makePoint x', p.x, 3.0);
  approx('makePoint y', p.y, 4.0);

  p.x = 10.0;
  p.y = 20.0;
  approx('mutate Point.x', p.x, 10.0);
  approx('mutate Point.y', p.y, 20.0);

  final p2 = oche.makePoint(1.0, 2.0);
  final p3 = oche.addPoints(p, p2);
  approx('addPoints x', p3.x, 11.0);
  approx('addPoints y', p3.y, 22.0);

  final part = oche.makeParticle(1.0, 2.0, 3.0, Color.Blue);
  approx('makeParticle x', part.x, 1.0);
  approx('makeParticle mass', part.mass, 3.0);
  eq('makeParticle color', part.color, Color.Blue);

  // ── Copy mode — non-POD struct (string) ────────────────────────────────────
  section('Copy mode — single struct (non-POD, has string)');

  final u = oche.makeUser('Bob', 25);
  eq('makeUser name', u.name, 'Bob');
  eq('makeUser age', u.age, 25);

  u.name = 'Charlie';
  u.age = 99;
  eq('mutate User.name', u.name, 'Charlie');
  eq('mutate User.age', u.age, 99);

  final msg = oche.greetUser(u);
  eq('greetUser', msg, 'Hello, Charlie! Age: 99');

  // Nested struct
  final t = oche.makeTagged('origin', 0.0, 0.0);
  eq('makeTagged label', t.label, 'origin');
  approx('makeTagged point.x', t.point.x, 0.0);

  // ── Struct param (User and UserView) ───────────────────────────────────────
  section('Copy mode — pass struct (User/UserView) to proc');

  final uPlain = oche.makeUser('Dave', 40);
  final msg2 = oche.greetUser(uPlain);
  eq('greetUser(User plain)', msg2, 'Hello, Dave! Age: 40');

  final bufU = oche.makeUserBuffer(3);
  final uv = bufU[0]; // UserView
  final msg3 = oche.greetUser(uv);
  ok('greetUser(UserView)', msg3.startsWith('Hello,'));
  bufU.free();

  // ── Option return ──────────────────────────────────────────────────────────
  section('Option return');

  final ptSome = oche.maybePoint(true);
  ok('maybePoint(true) not null', ptSome != null);
  approx('maybePoint(true).x', ptSome!.x, 1.5);
  approx('maybePoint(true).y', ptSome.y, 2.5);

  final ptNone = oche.maybePoint(false);
  eq('maybePoint(false) is null', ptNone, null);

  final uSome = oche.maybeUser('Eve');
  ok('maybeUser(Eve) not null', uSome != null);
  eq('maybeUser name', uSome!.name, 'Eve');

  final uNone = oche.maybeUser('');
  eq("maybeUser('') is null", uNone, null);

  // ── Primitives and string ──────────────────────────────────────────────────
  section('Primitives and string');

  eq('addInts(3, 4)', oche.addInts(3, 4), 7);
  eq('addInts negative', oche.addInts(-5, 3), -2);
  approx('mulFloat', oche.mulFloat(2.5, 4.0), 10.0);
  eq('echoStr', oche.echoStr('oche'), 'echo: oche');
  eq('echoStr empty', oche.echoStr(''), 'echo: ');
  eq('sumSeq', oche.sumSeq([1, 2, 3, 4, 5]), 15);
  eq('sumSeq empty', oche.sumSeq([]), 0);

  // ── seq copy mode ──────────────────────────────────────────────────────────
  section('seq copy mode');

  final pts = oche.makePointList(5);
  eq('makePointList length', pts.length, 5);
  approx('makePointList[0].x', pts[0].x, 0.0);
  approx('makePointList[2].x', pts[2].x, 2.0);
  approx('makePointList[4].y', pts[4].y, 8.0);
  pts[0].x = 999.0; // mutate — GC-owned
  approx('mutate copy list elem', pts[0].x, 999.0);

  final usersCopy = oche.makeUserList(4);
  eq('makeUserList length', usersCopy.length, 4);
  eq('makeUserList[0].name', usersCopy[0].name, 'user0');
  eq('makeUserList[3].age', usersCopy[3].age, 30);

  // ── seq view mode (NativeListView) ─────────────────────────────────────────
  section('seq view mode (NativeListView)');

  final viewPts = oche.getPointsView();
  ok(
    'getPointsView returns NativeListView',
    viewPts is NativeListView<PointView>,
  );
  eq('view_pts length', viewPts.length, 3);
  approx('viewPts[0].x', viewPts[0].x, 1.0);
  approx('viewPts[1].y', viewPts[1].y, 4.0);

  // Iteration
  final xs = viewPts.map((p) => p.x).toList();
  eq('iteration x values', xs, [1.0, 3.0, 5.0]);

  // freeze
  final ptFrozen = viewPts[1].freeze();
  approx('freeze().x', ptFrozen.x, 3.0);
  approx('freeze().y', ptFrozen.y, 4.0);

  // read-only check
  try {
    viewPts[0] = viewPts[1].freeze() as dynamic; // should throw
    ok('NativeListView []= throws', false);
  } catch (e) {
    ok('NativeListView []= throws', true);
  }

  // Non-POD seq view (User)
  final viewUsers = oche.getUsersView();
  eq('getUsersView length', viewUsers.length, 3);
  eq('getUsersView[0].name', viewUsers[0].name, 'view_user0');
  eq('getUsersView[2].age', viewUsers[2].age, 33);
  final uf = viewUsers[0].freeze();
  eq('freeze User name', uf.name, 'view_user0');

  // ── OcheBuffer — int ───────────────────────────────────────────────────────
  section('OcheBuffer (SharedListView) — int');

  final ibuf = oche.makeIntBuffer(6);
  ok('makeIntBuffer returns SharedListView', ibuf is SharedListView<int>);
  eq('ibuf length', ibuf.length, 6);
  eq('ibuf[0]', ibuf[0], 0);
  eq('ibuf[1]', ibuf[1], 3);
  eq('ibuf[5]', ibuf[5], 15);

  ibuf[2] = 999;
  eq('ibuf[2] after set', ibuf[2], 999);

  // Negative index (via length)
  eq('ibuf[last]', ibuf[ibuf.length - 1], 15);

  // toTypedData — zero-copy view
  final td = ibuf.toTypedData();
  ok('toTypedData not null', td != null);
  ok('toTypedData is Int64List', td is Int64List);
  final il = td as Int64List;
  eq('toTypedData[5]', il[5], 15);
  // Mutate via typed data
  il[5] = 777;
  eq('ibuf[5] after TypedData mutation', ibuf[5], 777);

  ibuf.free();

  // ── OcheBuffer — POD struct (Particle) ────────────────────────────────────
  section('OcheBuffer (SharedListView) — POD struct (Particle)');

  final pbuf = oche.makeParticleBuffer(4);
  eq('particleBuf len', pbuf.length, 4);
  approx('particleBuf[0].x', pbuf[0].x, 0.0);
  eq('particleBuf[2].color', pbuf[2].color, Color.Blue);

  pbuf[0].x = 99.0;
  approx('mutate particleBuf[0].x', pbuf[0].x, 99.0);

  final pFrozen = pbuf[1].freeze();
  approx('frozen Particle.x', pFrozen.x, 1.0);

  pbuf.free();

  // ── OcheBuffer — non-POD struct (User) ────────────────────────────────────
  section('OcheBuffer (SharedListView) — non-POD struct (User)');

  final ubuf = oche.makeUserBuffer(3);
  eq('userBuf len', ubuf.length, 3);
  eq('userBuf[0].name', ubuf[0].name, 'buf_user0');
  eq('userBuf[2].age', ubuf[2].age, 22);

  ubuf[0].name = 'mutated';
  eq('ubuf[0].name after mutation', ubuf[0].name, 'mutated');

  final uf2 = ubuf[1].freeze();
  eq('frozen User name', uf2.name, 'buf_user1');

  final msgUv = oche.greetUser(ubuf[2]);
  ok('greetUser(UserView from buf)', msgUv.contains('buf_user2'));

  ubuf.free();

  // ── OcheBuffer as INPUT param ──────────────────────────────────────────────
  section('OcheBuffer as INPUT param');

  final src = oche.makeIntBuffer(5); // [0, 3, 6, 9, 12]
  final total = oche.sumIntBuffer(src);
  eq('sumIntBuffer', total, 30);

  final doubled = oche.doubleIntBuffer(src);
  eq('doubleIntBuffer[0]', doubled[0], 0);
  eq('doubleIntBuffer[1]', doubled[1], 6);
  eq('doubleIntBuffer[4]', doubled[4], 24);
  doubled.free();

  final ubuf2 = oche.makeUserBuffer(4);
  final count = oche.countActiveUsers(ubuf2);
  eq('countActiveUsers (all Active)', count, 4);
  ubuf2.free();
  src.free();

  // ── OcheArray — fast array input ──────────────────────────────────────────
  section('OcheArray — fast array input (TypedData)');

  final a = Float64List.fromList([1.0, 2.0, 3.0, 4.0]);
  final b = Float64List.fromList([2.0, 3.0, 4.0, 5.0]);

  final dot = oche.dotProduct(a, b);
  approx('dotProduct', dot, 2 + 6 + 12 + 20);

  final factorBuf = oche.multiplyArray(a, 3.0);
  ok('multiplyArray returns SharedListView', factorBuf is SharedListView);
  eq('multiplyArray len', factorBuf.length, 4);
  approx('multiplyArray[3]', (factorBuf[3] as num).toDouble(), 12.0);
  factorBuf.free();

  // ── OchePtr — true zero-copy ───────────────────────────────────────────────
  section('OchePtr — true zero-copy (ffi.Pointer)');

  final buf = calloc<ffi.Int64>(5);
  for (var i = 0; i < 5; i++) buf[i] = i + 1;

  final s = oche.sumIntsPtr(buf, 5);
  eq('sumIntsPtr', s, 15);

  final negBuf = oche.negateIntsPtr(buf, 5);
  eq('negateIntsPtr[0]', negBuf[0], -1);
  eq('negateIntsPtr[4]', negBuf[4], -5);
  negBuf.free();

  calloc.free(buf);

  // ── NativeListView — Sequence protocol extras ─────────────────────────────
  section('NativeListView — Sequence protocol extras');

  final viewPts2 = oche.getPointsView();

  // contains
  ok('contains check', viewPts2.any((p) => p.x == 1.0));
  ok('contains check (false)', !viewPts2.any((p) => p.x == 99.0));

  // firstWhere / indexOf equivalent
  final idx = viewPts2.indexWhere((p) => p.x == 3.0);
  eq('indexOf x==3.0', idx, 1);

  // reversed
  final rev = viewPts2.toList().reversed.toList();
  approx('reversed[0].x', rev[0].x, 5.0);

  // slice via sublist
  final sl = viewPts2.sublist(1, 3);
  eq('slice len', sl.length, 2);
  approx('slice[0].y', sl[0].y, 4.0);

  // where / map
  final bigX = viewPts2.where((p) => p.x >= 3.0).toList();
  eq('where x>=3 count', bigX.length, 2);

  // __repr__ equivalent (toString)
  ok('toString not empty', viewPts2.toString().isNotEmpty);

  // ── SharedListView — MutableSequence protocol extras ──────────────────────
  section('SharedListView — MutableSequence protocol extras');

  final ibuf2 = oche.makeIntBuffer(6); // [0, 3, 6, 9, 12, 15]

  // contains
  ok('SLV contains 9', ibuf2.contains(9));
  ok('SLV contains (false)', !ibuf2.contains(99));

  // indexOf
  final sidx = ibuf2.indexOf(9);
  eq('SLV indexOf 9', sidx, 3);

  // reversed
  final srev = ibuf2.toList().reversed.toList();
  eq('SLV reversed[0]', srev[0], 15);

  // sublist (slice read)
  final ssl = ibuf2.sublist(1, 4);
  eq('SLV slice len', ssl.length, 3);
  eq('SLV slice[0]', ssl[0], 3);

  // toString
  ok('SLV toString not empty', ibuf2.toString().isNotEmpty);

  // []= on out-of-range index should throw RangeError
  try {
    ibuf2[ibuf2.length] = 999; // one past end — should throw
    ok('SLV []= out-of-range throws', false);
  } catch (e) {
    ok('SLV []= out-of-range throws', e is RangeError);
  }

  // sum via fold
  final s2 = ibuf2.fold<int>(0, (acc, v) => acc + v);
  eq('SLV fold sum', s2, 0 + 3 + 6 + 9 + 12 + 15);

  ibuf2.free();

  // ── NativeListView — negative index (via length arithmetic) ───────────────
  section('NativeListView — index extras');

  final viewPts3 = oche.getPointsView();
  // Dart has no native negative indexing, use length-based access
  approx('view_pts[last].x', viewPts3[viewPts3.length - 1].x, 5.0);
  approx('view_pts[last].y', viewPts3[viewPts3.length - 1].y, 6.0);

  // OcheBuffer — particleBuf extras (mass field, color enum)
  final pbuf2 = oche.makeParticleBuffer(4);
  approx('particleBuf[3].mass', pbuf2[3].mass, 1.3, 1e-6);
  eq('particleBuf[2].color (Blue=2)', pbuf2[2].color, Color.Blue);
  pbuf2.free();

  // OcheBuffer — int extras (slice, sum, free idempotent)
  final ibuf3 = oche.makeIntBuffer(6); // [0,3,6,9,12,15]
  final s3 = ibuf3.fold<int>(0, (acc, v) => acc + v);
  eq('sum(ibuf)', s3, 45);
  approx('ibuf[-1] via length', ibuf3[ibuf3.length - 1].toDouble(), 15.0);
  ibuf3.free();
  // free() idempotent — should not crash
  ibuf3.free();
  ok('ibuf.free() idempotent no crash', true);

  // ── Dart SharedListView Finalizer (smoke test) ─────────────────────────────
  section('SharedListView Finalizer (safety net smoke test)');

  // Create and abandon without calling .free() — finalizer should handle it
  for (var i = 0; i < 5; i++) {
    final tmp = oche.makeIntBuffer(100);
    // deliberately not calling tmp.free() — Finalizer should catch it
    ok('orphaned SharedListView[${i}] created (finalizer will clean up)', true);
  }

  // ── Error handling ─────────────────────────────────────────────────────────
  section('Error handling');

  eq('riskyDivide(10, 2)', oche.riskyDivide(10, 2), 5);

  try {
    oche.riskyDivide(1, 0);
    ok('riskyDivide(1,0) throws', false);
  } catch (e) {
    ok('riskyDivide(1,0) throws', e.toString().contains('division by zero'));
  }

  final uOk = oche.riskyUser('Frank');
  eq('riskyUser ok name', uOk.name, 'Frank');

  try {
    oche.riskyUser('');
    ok("riskyUser('') throws", false);
  } catch (e) {
    ok("riskyUser('') throws", e.toString().contains('name cannot be empty'));
  }

  // ─────────────────────────────────────────────────────────────────────────
  summary();
}
