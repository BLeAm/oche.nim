#!/usr/bin/env python3
"""
🦅 THE PORCHE CHALLENGE SUITE 🦅
Comparing Pure Python vs Nim+Porche+Python performance
"""

import time
import random
import nlib_bench

# --- PYTHON PURE IMPLEMENTATIONS ---

def monteCarloPiPython(iterations):
    """Pure Python Monte Carlo Pi calculation"""
    count = 0
    for _ in range(iterations):
        x = random.random()
        y = random.random()
        if x*x + y*y <= 1.0:
            count += 1
    return 4.0 * (count / iterations)

def mandelbrotPython(width, height, max_iter):
    """Pure Python Mandelbrot set calculation"""
    result = [0] * (width * height)
    for y in range(height):
        cy = -1.5 + 3.0 * y / height
        for x in range(width):
            cx = -2.0 + 3.0 * x / width
            zx = 0.0
            zy = 0.0
            count = 0
            while zx*zx + zy*zy <= 4.0 and count < max_iter:
                temp = zx*zx - zy*zy + cx
                zy = 2.0 * zx * zy + cy
                zx = temp
                count += 1
            result[y * width + x] = count
    return result

# --- BENCHMARK HARNESS ---

def runBench(name, pure_func, porche_func):
    print(f"\n[*] BENCHMARK: {name}")

    # Pure Python
    start = time.perf_counter()
    res1 = pure_func()
    t1 = time.perf_counter() - start
    print(f"Pure Python: {t1:.2f}s")

    # Nim+Porche+Python
    start = time.perf_counter()
    res2 = porche_func()
    t2 = time.perf_counter() - start
    print(f"Porche: {t2:.2f}s")

    ratio = t1 / t2 if t2 > 0 else float('inf')
    winner = "Nim" if t1 > t2 else "Python"
    print(f"Speedup: {ratio:.2f}x ({winner} wins)")

def main():
    print("==========================================")
    print("     🦅 THE PORCHE CHALLENGE SUITE 🦅    ")
    print("==========================================\n")

    # CASE A: Pure Loop Logic (10 Million Iterations)
    iters = 10000000
    runBench(
        f"Monte Carlo Pi ({iters:,} iterations)",
        lambda: monteCarloPiPython(iters),
        lambda: nlib_bench.porche.monteCarloPiNim(iters),
    )

    # CASE B: Complex Graphics Math (1000x1000)
    runBench(
        "Mandelbrot Fractal (1000x1000 pixels)",
        lambda: mandelbrotPython(1000, 1000, 1000),
        lambda: nlib_bench.porche.mandelbrotNim(1000, 1000, 1000),
    )

    print("\n==========================================")
    print("   🏁 CHALLENGE COMPLETE! 🏁      ")
    print("==========================================")

if __name__ == "__main__":
    main()