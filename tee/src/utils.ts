import { HMACDRBG } from "@stablelib/hmac-drbg";
import type { RandomSource } from "@stablelib/random";
import { SHA256 } from "@stablelib/sha256";

/**
 * Minimum seed length in bytes for cryptographic security.
 * 32 bytes = 256 bits, matching the security level of SHA-256.
 */
export const MIN_SEED_LENGTH = 32;

export interface Rng32Options {
	/**
	 * Size of the internal random byte pool, in bytes.
	 * Must be >= 4.
	 * If omitted, defaults to 4096.
	 */
	poolSize?: number;

	/**
	 * Deterministic seed (entropy input for the DRBG).
	 * Must be at least MIN_SEED_LENGTH (32) bytes for cryptographic security.
	 */
	seed: Uint8Array | Buffer;

	/**
	 * Optional nonce/personalization to diversify the DRBG stream.
	 * Use this to domain-separate different streams from the same seed.
	 */
	nonce?: Uint8Array | Buffer;
}

/**
 * Simple deterministic RandomSource that feeds the seed bytes
 * into HMACDRBG. It is NOT itself a RNG; it just satisfies
 * the stablelib RandomSource interface.
 */
class SeedRandomSource implements RandomSource {
	isAvailable = true;

	private readonly seed: Uint8Array;
	private offset = 0;

	constructor(seed: Uint8Array) {
		if (seed.length < MIN_SEED_LENGTH) {
			throw new RangeError(
				`seed must be at least ${MIN_SEED_LENGTH} bytes for cryptographic security, got ${seed.length}`,
			);
		}
		this.seed = seed;
	}

	randomBytes(length: number): Uint8Array {
		const out = new Uint8Array(length);
		for (let i = 0; i < length; i++) {
			out[i] = this.seed[this.offset % this.seed.length];
			this.offset++;
		}
		return out;
	}
}

/**
 * 32-bit CSPRNG backed exclusively by an HMAC-DRBG (SHA-256)
 * from `@stablelib/hmac-drbg`, with a pooled byte buffer to
 * amortize DRBG expansions.
 *
 * This generator is **fully deterministic**:
 *  - Same (seed, nonce, poolSize) => identical output sequence.
 *  - No fallback to system randomness.
 */
export class Rng32 {
	private static readonly UINT32_RANGE = 0x1_0000_0000; // 2^32

	private pool: Uint8Array = new Uint8Array(0);
	private offset = 0;

	private readonly poolSize: number;
	private readonly drbg: HMACDRBG;

	constructor(options: Rng32Options) {
		const poolSize = options.poolSize ?? 4096;
		if (poolSize < 4) {
			throw new RangeError("poolSize must be at least 4");
		}

		const seedBytes = new Uint8Array(Buffer.from(options.seed));
		if (seedBytes.length < MIN_SEED_LENGTH) {
			throw new RangeError(
				`seed must be at least ${MIN_SEED_LENGTH} bytes for cryptographic security, got ${seedBytes.length}`,
			);
		}

		const nonceBytes = options.nonce
			? new Uint8Array(Buffer.from(options.nonce))
			: undefined;

		this.poolSize = poolSize;

		const entropySource = new SeedRandomSource(seedBytes);
		// HMACDRBG(entropySource: RandomSource, hash?: Hash, personalization?: Uint8Array)
		this.drbg = new HMACDRBG(entropySource, SHA256, nonceBytes);
	}

	/**
	 * Refill the internal byte pool with fresh DRBG bytes.
	 */
	private refill(): void {
		const bytes = this.drbg.randomBytes(this.poolSize);
		if (bytes.length !== this.poolSize) {
			throw new Error(
				`Rng32: DRBG returned ${bytes.length} bytes, expected ${this.poolSize}`,
			);
		}
		this.pool = bytes;
		this.offset = 0;
	}

	/**
	 * Get a uniformly random unsigned 32-bit integer in [0, 2^32).
	 */
	nextUint32(): number {
		// Need 4 bytes; refill if not enough left in the pool.
		if (this.offset >= this.pool.length - 3) {
			this.refill();
		}

		const view = new DataView(
			this.pool.buffer,
			this.pool.byteOffset + this.offset,
			4,
		);
		const value = view.getUint32(0, true); // little-endian
		this.offset += 4;
		return value;
	}

	/**
	 * Get a uniformly random integer in the range [0, max).
	 *
	 * Uses rejection sampling to avoid modulo bias.
	 *
	 * @param max Positive number in (0, 2^32].
	 */
	nextBelow(max: number): number {
		const n = Math.trunc(max);
		if (n <= 0) {
			throw new RangeError("max must be a positive integer");
		}

		// We only generate 32 bits of randomness; beyond this you need a wider RNG.
		if (n > Rng32.UINT32_RANGE) {
			throw new RangeError("max must be <= 2^32 for Rng32");
		}

		if (n === 1) {
			return 0;
		}

		const limit = Rng32.UINT32_RANGE;
		const threshold = limit - (limit % n); // chop off ragged tail

		// Rejection sampling: keep drawing until we fall in the "good" range.
		// This guarantees uniform distribution over [0, max).
		for (;;) {
			const x = this.nextUint32(); // in [0, 2^32)
			if (x < threshold) {
				return x % n;
			}
		}
	}

	/**
	 * Get a random double in [0, 1), using 32 bits of randomness.
	 * If you need full 53-bit precision, you’ll want a wider generator.
	 */
	nextFloat(): number {
		return this.nextUint32() / Rng32.UINT32_RANGE;
	}

	/**
	 * Fill a buffer with random bytes using the DRBG-backed pool.
	 * Returns a Uint8Array; wrap with Buffer.from(...) if you need a Buffer.
	 */
	nextBytes(size: number): Uint8Array {
		const len = Math.trunc(size);
		if (len < 0) {
			throw new RangeError("size must be a non-negative integer");
		}
		if (len === 0) {
			return new Uint8Array(0);
		}

		const out = new Uint8Array(len);
		let written = 0;

		while (written < len) {
			if (this.offset >= this.pool.length) {
				this.refill();
			}
			const available = this.pool.length - this.offset;
			const toCopy = Math.min(available, len - written);
			out.set(this.pool.subarray(this.offset, this.offset + toCopy), written);
			this.offset += toCopy;
			written += toCopy;
		}

		return out;
	}
}
