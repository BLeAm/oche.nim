import time
import math
import nlib_all_bench

# --- Pure Python Implementations (Real Logic) ---

def nbodyPython(n):
    # เลียนแบบโครงสร้างเดียวกับ Nim
    x, y, z = 4.84, -1.16, -0.103
    vx, vy, vz = 0.606, 2.812, -0.025
    mass = 0.037
    dt = 0.01
    for _ in range(n):
        # Simplified 1-body interaction for loop test
        d2 = x*x + y*y + z*z
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

def run_bench(name, py_func, porche_func):
    print(f"\n[*] {name}")
    
    # Measure Python
    start = time.perf_counter()
    py_func()
    t_py = time.perf_counter() - start
    print(f"  - Pure Python: {t_py:.4f}s")
    
    # Measure Porche (Nim)
    start = time.perf_counter()
    porche_func()
    t_nim = time.perf_counter() - start
    print(f"  - Porche (Nim): {t_nim:.4f}s")
    
    print(f"  >> Speedup: {t_py/t_nim:.2f}x")

if __name__ == "__main__":
    print("==========================================")
    print("    🏎️  PORCHE FULL PERFORMANCE SUITE    ")
    print("==========================================\n")

    # 1. N-Body (1M Iters) - วัด Computational Power
    run_bench("N-Body Simulation (1M Iters)", 
              lambda: nbodyPython(1_000_000), 
              lambda: nlib_all_bench.porche.nbodyNim(1_000_000))

    # 2. Spectral Norm (N=500) - วัด Floating Point Performance
    run_bench("Spectral Norm (N=500)", 
              lambda: spectralNormPython(500), 
              lambda: nlib_all_bench.porche.spectralNormNim(500))

    # 3. The Zero-Copy "Porche" Test
    SIZE = 10_000_000
    print(f"\n[*] Large Data Test (Size: {SIZE:,} Vec3)")
    
    # วัดเวลาสร้าง + ส่ง Pointer
    start = time.perf_counter()
    view = nlib_all_bench.porche.generateLargeArrayView(SIZE)
    t_view = time.perf_counter() - start
    print(f"  - PorcheView Creation (Nim -> Py): {t_view:.6f}s")

    # วัดความแรงของ NumPy Integration
    try:
        start = time.perf_counter()
        # ใช้ dtype ให้ตรงกับ Vec3 (3 x float64)
        np_arr = view.to_numpy(dtype=[('x', 'f8'), ('y', 'f8'), ('z', 'f8')])
        t_np = time.perf_counter() - start
        print(f"  - NumPy Zero-Copy Mapping:      {t_np:.6f}s (Total {SIZE*24/1024/1024:.1f} MB shared)")
    except Exception as e:
        print(f"  - NumPy Test Skipped: {e}")