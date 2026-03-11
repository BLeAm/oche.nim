# orun.py — Comprehensive oche feature test runner (Python)
# Run: py3 orun.py
# Expects: libolib.so (or .dylib/.dll) in the same directory as olib.py

from olib import porche
import numpy as np
import ctypes
import sys

# ─── Test framework ────────────────────────────────────────────────────────────

_pass = 0
_fail = 0
_section = ""

def section(name: str):
    global _section
    _section = name
    print(f"\n{'─'*60}")
    print(f"  {name}")
    print(f"{'─'*60}")

def ok(label: str, cond: bool, detail: str = ""):
    global _pass, _fail
    if cond:
        _pass += 1
        print(f"  ✓  {label}")
    else:
        _fail += 1
        info = f" — {detail}" if detail else ""
        print(f"  ✗  {label}{info}", file=sys.stderr)

def eq(label: str, got, expected):
    ok(label, got == expected, f"got {got!r}, expected {expected!r}")

def approx(label: str, got: float, expected: float, tol: float = 1e-9):
    ok(label, abs(got - expected) < tol, f"got {got}, expected {expected}")

def summary():
    total = _pass + _fail
    print(f"\n{'═'*60}")
    print(f"  Results: {_pass}/{total} passed", end="")
    if _fail:
        print(f"  ({_fail} FAILED) ❌")
        sys.exit(1)
    else:
        print("  ✓ All passed ✅")

# ──────────────────────────────────────────────────────────────────────────────

section("Enums")

eq("getColor() == Green", porche.getColor(), 1)  # Green = 1

u_for_status = porche.makeUser("Alice", 30)
eq("getStatus(active user) == Active", porche.getStatus(u_for_status), 1)  # Active = 1

# ──────────────────────────────────────────────────────────────────────────────

section("Copy mode — single struct (POD)")

p = porche.makePoint(3.0, 4.0)
approx("makePoint x", p.x, 3.0)
approx("makePoint y", p.y, 4.0)

p.x = 10.0
p.y = 20.0
approx("mutate Point.x", p.x, 10.0)
approx("mutate Point.y", p.y, 20.0)

p2 = porche.makePoint(1.0, 2.0)
p3 = porche.addPoints(p, p2)   # pass User plain object
approx("addPoints x", p3.x, 11.0)
approx("addPoints y", p3.y, 22.0)

part = porche.makeParticle(1.0, 2.0, 3.0, 2)  # Blue = 2
approx("makeParticle x", part.x, 1.0)
approx("makeParticle mass", part.mass, 3.0)
eq("makeParticle color (Blue=2)", part.color, 2)

# ──────────────────────────────────────────────────────────────────────────────

section("Copy mode — single struct (non-POD, has string)")

u = porche.makeUser("Bob", 25)
eq("makeUser name", u.name, "Bob")
eq("makeUser age", u.age, 25)

u.name = "Charlie"
u.age  = 99
eq("mutate User.name", u.name, "Charlie")
eq("mutate User.age",  u.age,  99)

msg = porche.greetUser(u)
eq("greetUser", msg, "Hello, Charlie! Age: 99")

# Nested struct
t = porche.makeTagged("origin", 0.0, 0.0)
eq("makeTagged label", t.label, "origin")
approx("makeTagged point.x", t.point.x, 0.0)

# ──────────────────────────────────────────────────────────────────────────────

section("Copy mode — pass struct (User/UserView) to proc")

u_plain = porche.makeUser("Dave", 40)
msg2 = porche.greetUser(u_plain)
eq("greetUser(User plain)", msg2, "Hello, Dave! Age: 40")

# Pass via view (from share buffer)
buf_u = porche.makeUserBuffer(3)
uv = buf_u[0]  # UserView
msg3 = porche.greetUser(uv)
ok("greetUser(UserView)", msg3.startswith("Hello,"))
buf_u.free()

# ──────────────────────────────────────────────────────────────────────────────

section("Option return")

pt_some = porche.maybePoint(True)
ok("maybePoint(True) not None", pt_some is not None)
approx("maybePoint(True).x", pt_some.x, 1.5)
approx("maybePoint(True).y", pt_some.y, 2.5)

pt_none = porche.maybePoint(False)
eq("maybePoint(False) is None", pt_none, None)

u_some = porche.maybeUser("Eve")
ok("maybeUser('Eve') not None", u_some is not None)
eq("maybeUser name", u_some.name, "Eve")

u_none = porche.maybeUser("")
eq("maybeUser('') is None", u_none, None)

# ──────────────────────────────────────────────────────────────────────────────

section("Primitives and string")

eq("addInts(3, 4)", porche.addInts(3, 4), 7)
eq("addInts negative", porche.addInts(-5, 3), -2)
approx("mulFloat", porche.mulFloat(2.5, 4.0), 10.0)
eq("echoStr", porche.echoStr("oche"), "echo: oche")
eq("echoStr empty", porche.echoStr(""), "echo: ")
eq("sumSeq", porche.sumSeq([1, 2, 3, 4, 5]), 15)
eq("sumSeq empty", porche.sumSeq([]), 0)

# ──────────────────────────────────────────────────────────────────────────────

section("seq copy mode")

pts = porche.makePointList(5)
eq("makePointList length", len(pts), 5)
approx("makePointList[0].x", pts[0].x, 0.0)
approx("makePointList[2].x", pts[2].x, 2.0)
approx("makePointList[4].y", pts[4].y, 8.0)
pts[0].x = 999.0  # mutate — safe, GC owned
approx("mutate copy list elem", pts[0].x, 999.0)

users_copy = porche.makeUserList(4)
eq("makeUserList length", len(users_copy), 4)
eq("makeUserList[0].name", users_copy[0].name, "user0")
eq("makeUserList[3].age", users_copy[3].age, 30)

# ──────────────────────────────────────────────────────────────────────────────

section("seq view mode (NativeListView)")

from olib import NativeListView  # type exported from generated file

view_pts = porche.getPointsView()
ok("getPointsView returns NativeListView", isinstance(view_pts, NativeListView))
eq("view_pts length", len(view_pts), 3)
approx("view_pts[0].x", view_pts[0].x, 1.0)
approx("view_pts[1].y", view_pts[1].y, 4.0)
approx("view_pts[-1].x", view_pts[-1].x, 5.0)  # negative index

# Slice
sliced = view_pts[0:2]
eq("slice len", len(sliced), 2)
approx("slice[0].y", sliced[0].y, 2.0)

# Iteration
xs = [p.x for p in view_pts]
eq("iteration x values", xs, [1.0, 3.0, 5.0])

# Reverse
rev = list(reversed(view_pts))
approx("reversed[0].x", rev[0].x, 5.0)

# contains
ok("contains check", view_pts[0] is not None)

# freeze — copy out to GC-owned
pt_frozen = view_pts[1].freeze()
approx("freeze().x", pt_frozen.x, 3.0)
approx("freeze().y", pt_frozen.y, 4.0)

# read-only check
try:
    view_pts[0] = "bad"
    ok("NativeListView setitem raises", False)
except TypeError:
    ok("NativeListView setitem raises", True)

# View with non-POD (User)
view_users = porche.getUsersView()
eq("getUsersView length", len(view_users), 3)
eq("getUsersView[0].name", view_users[0].name, "view_user0")
eq("getUsersView[2].age", view_users[2].age, 33)
uf = view_users[0].freeze()
eq("freeze User name", uf.name, "view_user0")

# to_numpy for POD seq view — not supported for NativeListView directly on struct
# (returns copy of the struct array)
view_pts2 = porche.getPointsView()
arr_pts = view_pts2.to_numpy()
ok("to_numpy not None for POD view", arr_pts is not None)
eq("to_numpy length", len(arr_pts), 3)

# ──────────────────────────────────────────────────────────────────────────────

section("OcheBuffer (SharedListView) — int")

from olib import SharedListView

ibuf = porche.makeIntBuffer(6)
ok("makeIntBuffer returns SharedListView", isinstance(ibuf, SharedListView))
eq("intbuf len", len(ibuf), 6)
eq("intbuf[0]", ibuf[0], 0)
eq("intbuf[1]", ibuf[1], 3)
eq("intbuf[5]", ibuf[5], 15)

# Mutation via []=
ibuf[2] = 999
eq("ibuf[2] after set", ibuf[2], 999)

# Slice get
s = ibuf[1:4]
eq("slice [1:4]", s, [3, 999, 9])

# Slice set
ibuf[0:2] = [100, 200]
eq("ibuf[0] after slice set", ibuf[0], 100)
eq("ibuf[1] after slice set", ibuf[1], 200)

# Negative index
eq("ibuf[-1]", ibuf[-1], 15)

# Iteration
total = sum(ibuf)
ok("sum(ibuf)", total > 0)

# to_numpy — zero-copy writable view
arr = ibuf.to_numpy()
ok("to_numpy not None", arr is not None)
eq("to_numpy length", len(arr), 6)
eq("to_numpy[5]", int(arr[5]), 15)

# Mutate through numpy — should affect the buffer
arr[5] = 777
eq("ibuf[5] after numpy mutation", ibuf[5], 777)

# context manager
with porche.makeIntBuffer(3) as tmp:
    eq("ctx mgr buf[2]", tmp[2], 6)
ok("ctx mgr freed (no crash)", True)

# explicit free
ibuf.free()
ok("ibuf.free() no crash", True)

# ──────────────────────────────────────────────────────────────────────────────

section("OcheBuffer (SharedListView) — POD struct (Particle)")

pbuf = porche.makeParticleBuffer(4)
eq("particleBuf len", len(pbuf), 4)
approx("particleBuf[0].x", pbuf[0].x, 0.0)
approx("particleBuf[3].mass", pbuf[3].mass, 1.3)
eq("particleBuf[2].color (Blue=2)", pbuf[2].color, 2)

# Mutation via view setter
pbuf[0].x = 99.0
approx("mutate particleBuf[0].x", pbuf[0].x, 99.0)

# to_numpy for POD struct
pnp = pbuf.to_numpy()
ok("to_numpy Particle not None", pnp is not None)
eq("to_numpy Particle len", len(pnp), 4)
ok("to_numpy has 'x' field", 'x' in pnp.dtype.names)

# freeze
pf = pbuf[1].freeze()
approx("frozen Particle.x", pf.x, 1.0)
approx("frozen Particle.mass", pf.mass, 1.1)

pbuf.free()

# ──────────────────────────────────────────────────────────────────────────────

section("OcheBuffer (SharedListView) — non-POD struct (User)")

ubuf = porche.makeUserBuffer(3)
eq("userBuf len", len(ubuf), 3)
eq("userBuf[0].name", ubuf[0].name, "buf_user0")
eq("userBuf[2].age",  ubuf[2].age,  22)

# Mutation via string setter (ocheStr lifecycle)
ubuf[0].name = "mutated"
eq("ubuf[0].name after mutation", ubuf[0].name, "mutated")

# to_numpy returns None for non-POD
unp = ubuf.to_numpy()
eq("to_numpy User returns None (non-POD)", unp, None)

# freeze
uf2 = ubuf[1].freeze()
eq("frozen User name", uf2.name, "buf_user1")

# Pass UserView to proc accepting User param
msg_uv = porche.greetUser(ubuf[2])
ok("greetUser(UserView from buf)", "buf_user2" in msg_uv)

ubuf.free()

# ──────────────────────────────────────────────────────────────────────────────

section("OcheBuffer as INPUT param")

src = porche.makeIntBuffer(5)   # [0, 3, 6, 9, 12]
total = porche.sumIntBuffer(src)
eq("sumIntBuffer", total, 30)

doubled = porche.doubleIntBuffer(src)
eq("doubleIntBuffer[0]", doubled[0], 0)
eq("doubleIntBuffer[1]", doubled[1], 6)
eq("doubleIntBuffer[4]", doubled[4], 24)
doubled.free()

ubuf2 = porche.makeUserBuffer(4)
count = porche.countActiveUsers(ubuf2)
eq("countActiveUsers (all Active)", count, 4)
ubuf2.free()
src.free()

# ──────────────────────────────────────────────────────────────────────────────

section("OcheArray — fast array input (numpy)")

a = np.array([1.0, 2.0, 3.0, 4.0], dtype=np.float64)
b = np.array([2.0, 3.0, 4.0, 5.0], dtype=np.float64)

dot = porche.dotProduct(a, b)
approx("dotProduct numpy arrays", dot, 2+6+12+20)

factor_buf = porche.multiplyArray(a, 3.0)
ok("multiplyArray returns SharedListView", isinstance(factor_buf, SharedListView))
eq("multiplyArray len", len(factor_buf), 4)
approx("multiplyArray[0]", factor_buf[0], 3.0)
approx("multiplyArray[3]", factor_buf[3], 12.0)
factor_buf.free()

# array.array as OcheArray input
import array as pyarray
arr_aa = pyarray.array('d', [5.0, 6.0, 7.0])
b2 = np.array([1.0, 1.0, 1.0], dtype=np.float64)
dot2 = porche.dotProduct(arr_aa, b2)
approx("dotProduct array.array", dot2, 18.0)

# ──────────────────────────────────────────────────────────────────────────────

section("OchePtr — true zero-copy (numpy/ctypes pointer)")

narr = np.array([1, 2, 3, 4, 5], dtype=np.int64)
s = porche.sumIntsPtr(narr)
eq("sumIntsPtr numpy", s, 15)

neg = porche.negateIntsPtr(narr)
eq("negateIntsPtr[0]", neg[0], -1)
eq("negateIntsPtr[4]", neg[4], -5)
neg.free()

# Raw ctypes pointer path
carr = (ctypes.c_int64 * 4)(10, 20, 30, 40)
s2 = porche.sumIntsPtr(carr)
eq("sumIntsPtr ctypes pointer", s2, 100)

# ──────────────────────────────────────────────────────────────────────────────

section("Error handling")

r = porche.riskyDivide(10, 2)
eq("riskyDivide ok", r, 5)

try:
    porche.riskyDivide(1, 0)
    ok("riskyDivide(1,0) raises", False)
except RuntimeError as e:
    ok("riskyDivide(1,0) raises RuntimeError", "division by zero" in str(e))

u_ok = porche.riskyUser("Frank")
eq("riskyUser ok name", u_ok.name, "Frank")

try:
    porche.riskyUser("")
    ok("riskyUser('') raises", False)
except RuntimeError as e:
    ok("riskyUser('') raises RuntimeError", "name cannot be empty" in str(e))

# ──────────────────────────────────────────────────────────────────────────────

section("NativeListView — Sequence protocol extras")

vp = porche.getPointsView()
eq("index()", vp.index(vp[0]), 0)
eq("count()", vp.count(vp[0]), 1)
eq("len(list(reversed()))", len(list(reversed(vp))), 3)
ok("__repr__", "NativeListView" in repr(vp))

# ──────────────────────────────────────────────────────────────────────────────

section("SharedListView — MutableSequence protocol extras")

ibuf3 = porche.makeIntBuffer(5)
eq("SLV index()", ibuf3.index(ibuf3[1]), 1)
eq("SLV count()", ibuf3.count(0), 1)   # only buf[0] == 0
ok("SLV __repr__", "SharedListView" in repr(ibuf3))

# slice length mismatch raises
try:
    ibuf3[0:2] = [1, 2, 3]
    ok("slice length mismatch raises", False)
except ValueError:
    ok("slice length mismatch raises", True)

ibuf3.free()

# ──────────────────────────────────────────────────────────────────────────────

section("numpy integration — benchmark context")

import time

N = 1_000_000
narr_big = np.arange(N, dtype=np.int64)
a_big = np.ones(N, dtype=np.float64)
b_big = np.arange(N, dtype=np.float64)

t0 = time.perf_counter()
dot_big = porche.dotProduct(a_big, b_big)
t1 = time.perf_counter()
approx(f"dotProduct 1M elements correct ({(t1-t0)*1000:.1f}ms)", dot_big, float(N*(N-1)//2))

t0 = time.perf_counter()
neg_big = porche.negateIntsPtr(narr_big)
t1 = time.perf_counter()
eq(f"negateIntsPtr 1M elements [0]={neg_big[0]} ({(t1-t0)*1000:.1f}ms)", neg_big[0], 0)
eq("negateIntsPtr 1M elements [-1]", neg_big[-1], -(N-1))
neg_big.free()

# to_numpy zero-copy mutation round-trip
pbuf_np = porche.makeIntBuffer(5)
np_view = pbuf_np.to_numpy()
np_view[:] = 42
eq("numpy zero-copy write buf[0]", pbuf_np[0], 42)
eq("numpy zero-copy write buf[4]", pbuf_np[4], 42)
pbuf_np.free()

# ──────────────────────────────────────────────────────────────────────────────

summary()
