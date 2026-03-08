import time
import math
import nlib_full

def nbodyPython(n):
    x, vx, mass, dt = 4.84, 0.606, 0.037, 0.01
    for _ in range(n):
        d2 = x*x
        mag = dt / (d2 * math.sqrt(d2))
        vx -= x * mass * mag
        x += dt * vx
    return x

def spectralNormPython(n):
    u = [1.0] * n
    v = [0.0] * n
    for _ in range(10):
        for i in range(n):
            v[i] = sum(u[j] / ((i+j)*(i+j+1)//2 + i+1) for j in range(n))
        for i in range(n):
            u[i] = sum(v[j] / ((j+i)*(j+i+1)//2 + j+1) for j in range(n))
    return math.sqrt(u[0])

if __name__ == "__main__":
    print("==========================================")
    print("    🏎️  PORCHE FULL PERFORMANCE SUITE    ")
    print("==========================================\n")

    # Bench 1 & 2
    for name, py_fn, nim_fn, arg in [
        ("N-Body (1M)", nbodyPython, nlib_full.porche.nbodyNim, 1_000_000),
        ("Spectral Norm (500)", spectralNormPython, nlib_full.porche.spectralNormNim, 500)
    ]:
        print(f"[*] {name}")
        s = time.perf_counter()
        py_fn(arg)
        t_py = time.perf_counter() - s
        s = time.perf_counter()
        nim_fn(arg)
        t_nim = time.perf_counter() - s
        print(f"  - Python: {t_py:.4f}s | Nim: {t_nim:.4f}s | Speedup: {t_py/t_nim:.2f}x")

    # Bench 3: Zero-Copy
    SIZE = 10_000_000
    print(f"\n[*] Large Data Test ({SIZE:,} items)")
    s = time.perf_counter()
    view = nlib_full.porche.generateLargeArrayView(SIZE)
    print(f"  - Creation: {time.perf_counter() - s:.6f}s")

    try:
        import numpy as np
        s = time.perf_counter()
        np_arr = view.to_numpy() 
        if np_arr is not None:
            print(f"  - NumPy Zero-Copy: {time.perf_counter() - s:.6f}s")
            print(f"  - Shape: {np_arr.shape} | Sample: {np_arr[-1]}")
        else:
            print("  - to_numpy() returned None. Check nlib_full.py for 'return' statement.")
    except Exception as e:
        print(f"  - NumPy Error: {e}")