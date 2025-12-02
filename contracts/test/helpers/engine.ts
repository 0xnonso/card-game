import { ethers, fhevm } from "hardhat";
import type { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import type { EInputDataStruct } from "../../types/contracts-exposed/base/EInputHandler.sol/$EInputHandler";
import type { CardEngine } from "../../types/src/CardEngine";
import type { WhotRuleset } from "../../types/src/rules/WhotRuleset";
import type { MockManager } from "../../types/src/mocks/MockManager";

const ZERO_HANDLE = `0x${"00".repeat(32)}`;

export type EncryptedDeck = { handles: string[]; inputProof: string };
export type EngineCtx = {
  cardEngine: CardEngine;
  ruleset: WhotRuleset;
  alice: HardhatEthersSigner;
  player0: HardhatEthersSigner;
  player1: HardhatEthersSigner;
  player2: HardhatEthersSigner;
  player3: HardhatEthersSigner;
  accounts: HardhatEthersSigner[];
  encryptedDeck: EncryptedDeck;
  deckArray: number[];
};

export const buildEncryptedInputFor = async (
  cardEngine: CardEngine,
  owner: string,
  deckArray: ReadonlyArray<number>
): Promise<EncryptedDeck> => {
  const input = fhevm.createEncryptedInput(
    await cardEngine.getAddress(),
    owner,
  );
  input.add256(
    deckArray.slice(0, 32).reduce(
      (acc: bigint, v: number, i: number) => acc | (BigInt(v) << BigInt(i * 8)),
      0n,
    ),
  );
  input.add256(
    deckArray.slice(32).reduce(
      (acc: bigint, v: number, i: number) => acc | (BigInt(v) << BigInt(i * 8)),
      0n,
    ),
  );
  const raw = await input.encrypt();
  const handles = raw.handles.map((h) =>
    typeof h === "string" ? h : ethers.hexlify(h),
  );
  const inputProof =
    typeof raw.inputProof === "string"
      ? raw.inputProof
      : ethers.hexlify(raw.inputProof);
  return { handles, inputProof };
};

export const buildInputDataPair = (
  encrypted: EncryptedDeck,
): { input0: EInputDataStruct; input1: EInputDataStruct } => ({
  input0: {
    inputType: 6n, // InputType._EUINT256
    inputEuint8: ZERO_HANDLE,
    inputEuint16: ZERO_HANDLE,
    inputEuint32: ZERO_HANDLE,
    inputEuint64: ZERO_HANDLE,
    inputEuint128: ZERO_HANDLE,
    inputEuint256: encrypted.handles[0],
  },
  input1: {
    inputType: 6n, // InputType._EUINT256
    inputEuint8: ZERO_HANDLE,
    inputEuint16: ZERO_HANDLE,
    inputEuint32: ZERO_HANDLE,
    inputEuint64: ZERO_HANDLE,
    inputEuint128: ZERO_HANDLE,
    inputEuint256: encrypted.handles[1],
  },
});

const parseGameId = (logs: readonly any[] | undefined, iface: CardEngine["interface"]): bigint => {
  if (!logs?.length) return 1n;
  for (const log of logs) {
    try {
      const parsed = iface.parseLog(log);
      if (parsed?.name === "GameCreated") {
        return parsed.args?.gameId ?? parsed.args?.[0] ?? 1n;
      }
    } catch {}
  }
  return 1n;
};

export const createGameWithDefaults = async (
  ctx: EngineCtx,
  overrides: Partial<{
    gameRuleset: string;
    cardBitSize: number;
    cardDeckSize: number;
    maxPlayers: number;
    initialHandSize: number;
    proposedPlayers: string[];
    hookPermissions: bigint;
    input0: EInputDataStruct;
    input1: EInputDataStruct;
    inputProof: string;
    encryptedDeck: EncryptedDeck;
  }> = {},
) => {
  const encrypted = overrides.encryptedDeck ?? ctx.encryptedDeck;
  const inputs = buildInputDataPair(encrypted);

  const params = {
    gameRuleset: overrides.gameRuleset ?? (await ctx.ruleset.getAddress()),
    cardBitSize: overrides.cardBitSize ?? 8,
    cardDeckSize: overrides.cardDeckSize ?? 54,
    maxPlayers: overrides.maxPlayers ?? 3,
    initialHandSize: overrides.initialHandSize ?? 2,
    proposedPlayers:
      overrides.proposedPlayers ?? [ctx.player0.address, ctx.player1.address, ctx.player2.address],
    hookPermissions: overrides.hookPermissions ?? 0n,
    input0: overrides.input0 ?? inputs.input0,
    input1: overrides.input1 ?? inputs.input1,
    inputProof: overrides.inputProof ?? encrypted.inputProof,
  };

  const tx = await ctx.cardEngine.connect(ctx.alice).createGame(params);
  const receipt = await tx.wait();
  const gameId = parseGameId(receipt?.logs, ctx.cardEngine.interface);
  return { gameId, params };
};

export const createManagedGame = async (
  ctx: EngineCtx,
  manager: MockManager,
  overrides: Partial<{ hookPermissions: bigint }> = {},
) => {
  const encrypted = await buildEncryptedInputFor(ctx.cardEngine, await manager.getAddress(), ctx.deckArray);
  const inputs = buildInputDataPair(encrypted);
  const params = {
    gameRuleset: await ctx.ruleset.getAddress(),
    cardBitSize: 8,
    cardDeckSize: 54,
    maxPlayers: 3,
    initialHandSize: 2,
    proposedPlayers: [ctx.player0.address, ctx.player1.address, ctx.player2.address],
    hookPermissions: overrides.hookPermissions ?? 0xffn,
    input0: inputs.input0,
    input1: inputs.input1,
    inputProof: encrypted.inputProof,
  };
  const tx = await manager.createGame(params);
  const receipt = await tx.wait();
  const gameId = parseGameId(receipt?.logs, ctx.cardEngine.interface);
  return { gameId, params };
};

export const setupManagedGame = async (
  ctx: EngineCtx,
  options: { allowBootOut?: boolean; hookPermissions?: bigint } = {},
) => {
  const managerFactory = await ethers.getContractFactory("MockManager");
  const manager = (await managerFactory
    .connect(ctx.alice)
    .deploy(await ctx.cardEngine.getAddress())) as MockManager;
  await manager.waitForDeployment();
  if (options.allowBootOut) {
    await manager.connect(ctx.alice).setBootOutPermission(true);
  }
  const { gameId } = await createManagedGame(ctx, manager, {
    hookPermissions: options.hookPermissions ?? 0xffn,
  });
  await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);
  await ctx.cardEngine.connect(ctx.player1).joinGame(gameId);
  await ctx.cardEngine.connect(ctx.player2).joinGame(gameId);
  await ctx.cardEngine.connect(ctx.alice).startGame(gameId);
  return { gameId, manager };
};
