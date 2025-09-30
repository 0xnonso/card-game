import { createInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/node";
import { fisherYatesShuffleU8, Rng32 } from "./utils";
import { WHOT_DECK } from "./whot-cards";

const instanceP = (async () => {
  return createInstance({
    ...SepoliaConfig,
    ...(process.env.RELAYER_URL ? { relayerUrl: process.env.RELAYER_URL } : {}),
    ...(process.env.RPC_URL ? { network: process.env.RPC_URL } : {}),
  });
})();


function splitIntoTwoUint256BE(src: Uint8Array): [Uint8Array, Uint8Array] {
  const limb0 = new Uint8Array(32);
  const limb1 = new Uint8Array(32);

  // copy first 32 bytes -> limb0[0..len0-1]
  const len0 = Math.min(32, src.length);
  limb0.set(src.subarray(0, len0), 0);

  // copy remaining bytes -> limb1[0..len1-1]
  const rem = src.subarray(len0);
  const len1 = Math.min(32, rem.length);
  limb1.set(rem.subarray(0, len1), 0);

  return [limb0, limb1];
}

/** Convert 32-byte big-endian bytes -> BigInt (0..2^256-1) */
function be32ToBigInt(b32: Uint8Array): bigint {
  // Using hex is simple & clear; EVM uses big-endian for uint256 by convention.
  const hex = Buffer.from(b32).toString("hex");
  return BigInt("0x" + hex);
}

export async function encryptMultipleDeck(
  totalSize: number,
  contractAddress: string,
  importerAddress: string,
  onProgress?: (produced: number, expected: number) => void
): Promise<Uint8Array[]> {
  const inst = await instanceP;
  const rng = new Rng32();
  const cardDeck = new Uint8Array(WHOT_DECK.length);

  const buf0: any = inst.createEncryptedInput(contractAddress, importerAddress);
  for (let k = 0; k < 4; k++) {
    cardDeck.set(WHOT_DECK);
    const shuffled = fisherYatesShuffleU8(rng, cardDeck);
    const [limb0, limb1] = splitIntoTwoUint256BE(shuffled);
    buf0.add256(be32ToBigInt(limb0));
    buf0.add256(be32ToBigInt(limb1));
  }
  const first = await buf0.encrypt();               // { inputProof, handles }
  const firstProof = first.inputProof;
  const proofSize = firstProof.length;
  const expected = Math.max(1, Math.ceil(totalSize / proofSize));

  const proofs: Uint8Array[] = [firstProof];
  let produced = 1;

  // report initial progress
  if (onProgress) onProgress(produced, expected);

  while (produced < expected) {
    const buf: any = inst.createEncryptedInput(contractAddress, importerAddress);
    for (let j = 0; j < 4; j++) {
      cardDeck.set(WHOT_DECK);
      const shuffled = fisherYatesShuffleU8(rng, cardDeck);
      const [limb0, limb1] = splitIntoTwoUint256BE(shuffled);
      buf.add256(be32ToBigInt(limb0));
      buf.add256(be32ToBigInt(limb1));
    }
    const { inputProof } = await buf.encrypt();
    proofs.push(inputProof);
    produced++;

    // progress callback on every proof
    if (onProgress) onProgress(produced, expected);
  }

  return proofs;
}


export default encryptMultipleDeck;
