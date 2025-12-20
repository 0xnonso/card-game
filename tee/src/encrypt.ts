import { createHash } from "node:crypto";
import { TappdClient } from "@phala/dstack-sdk";
import type { RelayerEncryptedInput } from "@zama-fhe/relayer-sdk/node";
import { createInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/node";
import { Rng32 } from "./utils";

type PackedChunkBits = 8 | 16 | 32 | 64 | 128 | 256;
type PackedChunk = { bits: PackedChunkBits; value: bigint };

const RNG_LABEL = process.env.SHUFFLE_RNG_LABEL ?? "shuffle-rng";

let relayerInstancePromise:
	| Promise<Awaited<ReturnType<typeof createInstance>>>
	| undefined;

async function getRelayerInstance(): Promise<
	Awaited<ReturnType<typeof createInstance>>
> {
	if (!relayerInstancePromise) {
		relayerInstancePromise = createInstance(SepoliaConfig).catch((err) => {
			// Allow retry if the relayer is temporarily unavailable.
			relayerInstancePromise = undefined;
			throw err;
		});
	}
	return relayerInstancePromise;
}

async function createTeeRng(seedContext: string): Promise<Rng32> {
	if (!seedContext) {
		throw new Error("seedContext is required for TEE-backed RNG");
	}
	const label = `${RNG_LABEL}:${seedContext}`;
	const seedResp = await new TappdClient().deriveKey(label);
	const seed = createHash("sha256").update(seedResp.asUint8Array()).digest();
	return new Rng32({ seed, nonce: Buffer.from(seedContext) });
}

function selectChunkBits(bitLength: number): PackedChunkBits {
	if (bitLength <= 8) return 8;
	if (bitLength <= 16) return 16;
	if (bitLength <= 32) return 32;
	if (bitLength <= 64) return 64;
	if (bitLength <= 128) return 128;
	return 256;
}

function shuffleDeck(rng: Rng32, src: ReadonlyArray<number>): number[] {
	const deck = Array.from(src);
	for (let i = deck.length - 1; i > 0; i--) {
		const j = rng.nextBelow(i + 1);
		const t = deck[i];
		deck[i] = deck[j];
		deck[j] = t; // swap
	}
	return deck;
}

function packDeckToChunks(
	deck: ReadonlyArray<number>,
	bitsPerCard: number,
): PackedChunk[] {
	if (!Number.isInteger(bitsPerCard) || bitsPerCard < 1 || bitsPerCard > 256) {
		throw new Error("cardBitSize must be an integer between 1 and 256");
	}
	if (deck.length === 0) {
		throw new Error("deck must contain at least one card");
	}

	const totalBits = deck.length * bitsPerCard;
	if (totalBits > 512) {
		throw new Error("deck too large: requires more than two handles");
	}

	const maxValue = (1n << BigInt(bitsPerCard)) - 1n;
	let stream = 0n;
	for (const card of deck) {
		if (!Number.isSafeInteger(card) || card < 0) {
			throw new Error("deck values must be non-negative safe integers");
		}
		const cardBig = BigInt(card);
		if (cardBig > maxValue) {
			throw new Error(`card value ${card} exceeds cardBitSize=${bitsPerCard}`);
		}
		stream = (stream << BigInt(bitsPerCard)) | cardBig;
	}

	const chunks: PackedChunk[] = [];
	let remaining = totalBits;
	while (remaining > 0) {
		const take = Math.min(256, remaining);
		const shift = remaining - take;
		const mask = (1n << BigInt(take)) - 1n;
		const value = (stream >> BigInt(shift)) & mask;
		const bits = selectChunkBits(take);
		const shifted = bits === take ? value : value << BigInt(bits - take);
		chunks.push({ bits, value: shifted });
		remaining -= take;
	}
	return chunks;
}

function addPackedChunk(buf: RelayerEncryptedInput, chunk: PackedChunk) {
	switch (chunk.bits) {
		case 8:
			buf.add8(chunk.value);
			break;
		case 16:
			buf.add16(chunk.value);
			break;
		case 32:
			buf.add32(chunk.value);
			break;
		case 64:
			buf.add64(chunk.value);
			break;
		case 128:
			buf.add128(chunk.value);
			break;
		default:
			buf.add256(chunk.value);
			break;
	}
}

export async function encryptMultipleDeck(
	numProofs: number,
	contractAddress: string,
	importerAddress: string,
	onProgress?: (produced: number, expected: number) => void,
	deck: ReadonlyArray<number> = [],
	cardBitSize = 8,
	seedContext?: string,
): Promise<Uint8Array[]> {
	if (!contractAddress) throw new Error("contractAddress is required");
	if (!importerAddress) throw new Error("importerAddress is required");
	if (!deck.length) throw new Error("deck is required");
	if (!seedContext)
		throw new Error("seedContext is required for TEE-backed RNG");
	if (!Number.isSafeInteger(numProofs) || numProofs <= 0) {
		throw new Error("numProofs must be a positive integer");
	}

	const relayer = await getRelayerInstance();
	const rng = await createTeeRng(seedContext);
	const baseDeck = Array.from(deck);
	const expected = numProofs;
	const proofs: Uint8Array[] = [];

	const totalBits = baseDeck.length * cardBitSize;
	const handlesPerDeck = totalBits <= 256 ? 1 : 2;
	const decksPerProof = handlesPerDeck === 1 ? 8 : 4;

	for (let produced = 0; produced < expected; produced++) {
		const buf = relayer.createEncryptedInput(contractAddress, importerAddress);
		for (let deckIdx = 0; deckIdx < decksPerProof; deckIdx++) {
			const shuffled = shuffleDeck(rng, baseDeck);
			for (const chunk of packDeckToChunks(shuffled, cardBitSize)) {
				addPackedChunk(buf, chunk);
			}
		}
		const { inputProof } = await buf.encrypt();
		proofs.push(inputProof);

		if (onProgress) onProgress(produced + 1, expected);
	}

	return proofs;
}

export default encryptMultipleDeck;
