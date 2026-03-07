#!/usr/bin/env python3
"""
Test Porche (Python bindings) for parity with Oche.
Run from project root: python3 tests/test_porche.py
With numpy disabled (test fallback): NO_NUMPY=1 python3 tests/test_porche.py
"""
import os
import sys

# Allow running from project root; nlib and libmain.so live there
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.chdir(ROOT)

# Optional: simulate no numpy for fallback path testing
if os.environ.get("NO_NUMPY") == "1":
    class BlockNumpy:
        def find_module(self, name, path=None):
            if name == "numpy": return self
            return None
        def load_module(self, name):
            raise ImportError("numpy disabled for test")
    sys.meta_path.insert(0, BlockNumpy())

import nlib

def test_add_numbers():
    assert nlib.porche.addNumbersPy(1, 2) == 3
    assert nlib.porche.addNumbersPy(10, 20) == 30
    print("  addNumbersPy: OK")

def test_greet():
    s = nlib.porche.greetPy("Python")
    assert s == "Hello, Python"
    print("  greetPy: OK")

def test_create_user():
    user = nlib.porche.createUserPy("Alice", 7)
    assert isinstance(user, dict)
    assert "username" in user and "status" in user and "primaryTag" in user
    assert user["status"] == 0  # Active
    print("  createUserPy (struct return): OK")

def test_get_points_copy():
    pts = nlib.porche.getPointsCopyPy(3)
    assert len(pts) == 3
    for i, p in enumerate(pts):
        assert isinstance(p, dict)
        assert p["x"] == float(i)
        assert p["y"] == float(i)
    print("  getPointsCopyPy (seq[Point] return): OK")

def test_maybe_point():
    none_pt = nlib.porche.maybePoint(0)
    assert none_pt is None
    some_pt = nlib.porche.maybePoint(1)
    assert some_pt is not None
    assert isinstance(some_pt, dict)
    assert some_pt["x"] == 1.0
    assert some_pt["y"] == 2.0
    print("  maybePoint (Option[Point] return): OK")

def main():
    has_numpy = os.environ.get("NO_NUMPY") != "1"
    print("Porche tests (numpy available:", has_numpy, ")")
    test_add_numbers()
    test_greet()
    test_create_user()
    test_get_points_copy()
    test_maybe_point()
    print("All Porche tests passed.")

if __name__ == "__main__":
    main()
