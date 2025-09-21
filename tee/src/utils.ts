import { randomBytes } from "crypto";

// 32-bit CSPRNG with a byte pool
export class Rng32 {
  private pool = Buffer.alloc(0);
  private off = 0;
  constructor(private readonly poolSize = 4096) {}

  private refill() {
    this.pool = randomBytes(this.poolSize); // one syscall fills many draws
    this.off = 0;
  }

  // unbiased uniform integer in [0, max)
  nextBelow(max: number): number {
    if (max < 2) return 0;
    const LIM = 0x1_0000_0000;         // 2^32
    const THR = LIM - (LIM % max);     // chop ragged tail
    for (;;) {
      if (this.off > this.pool.length - 4) this.refill();
      const x = this.pool.readUInt32LE(this.off); // 32 random bits
      this.off += 4;
      if (x < THR) return x % max;     // rejection sampling (no modulo bias)
    }
  }
}

export function fisherYatesShuffleU8(rng: Rng32, a: Uint8Array): Uint8Array {
  for (let i = a.length - 1; i > 0; i--) {
    const j = rng.nextBelow(i + 1);
    const t = a[i]; a[i] = a[j]; a[j] = t;   // swap
  }
  return a;
}

