"""
gen_test_data.py -- golden model + hex file generator for the floor version.

Writes (one value per line, hex):
    templates.hex       N_TMPL x N_FEAT int8
    test_vectors.hex    N_CLIPS x N_FEAT int8
    expected_idx.hex    winning template per clip
    expected_dist.hex   winning L1 distance per clip (16-bit)

The classifier below uses the SAME integer math as the hardware:
int8 inputs cast to int32 before subtracting, L1 distance, and argmin
(which returns the first template on a tie, like the strict '<' in Verilog).

For the real design, replace T and X with your real int8 arrays
(shape (3, 64) and (N, 64)); nothing else changes.
"""
import numpy as np

T = np.array([[ 40,  30,  20,  10, -10, -20, -30, -40],
              [-40, -30, -20, -10,  10,  20,  30,  40]], dtype=np.int8)

X = np.array([[ 35,  28,  22,   8, -12, -18, -33, -38],    # A: near T0
              [-35, -28, -22,  -8,  12,  18,  33,  38],    # B: near T1
              [127, 127, 127, 127,-128,-128,-128,-128],    # C: extreme values
              [  0,   0,   0,   0,   0,   0,   0,   0]],   # D: exact tie
             dtype=np.int8)


def byte_hex(arr):
    # & 0xFF turns negative int8 into two's complement
    return [f"{int(v) & 0xFF:02x}" for v in arr.flatten()]


def classify(x, templates):
    d = [int(np.abs(x.astype(np.int32) - t.astype(np.int32)).sum()) for t in templates]
    return int(np.argmin(d)), d


def write_lines(name, lines):
    with open(name, "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    write_lines("templates.hex", byte_hex(T))
    write_lines("test_vectors.hex", byte_hex(X))

    idx_lines, dist_lines = [], []
    for n, x in enumerate(X):
        best, dists = classify(x, T)
        print(f"clip {n}: distances {dists} -> template {best}")
        idx_lines.append(f"{best:02x}")
        dist_lines.append(f"{dists[best]:04x}")

    write_lines("expected_idx.hex", idx_lines)
    write_lines("expected_dist.hex", dist_lines)
    print("wrote templates.hex, test_vectors.hex, expected_idx.hex, expected_dist.hex")
