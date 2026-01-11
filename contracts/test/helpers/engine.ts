import type { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import type { Interface, Log, TransactionReceipt } from "ethers";
import { ethers, fhevm } from "hardhat";
import type { EInputDataStruct } from "../../types/contracts-exposed/base/EInputHandler.sol/$EInputHandler";
import type { CardEngine } from "../../types/src/CardEngine";
import type { MockManager } from "../../types/src/mocks/MockManager";
import type { MockRuleset } from "../../types/src/mocks/MockRuleset";

export type EncryptedDeck = {
	input0: EInputDataStruct;
	input1: EInputDataStruct;
	inputProof: string;
	handles: string[];
};
export type EngineCtx = {
	cardEngine: CardEngine;
	ruleset: MockRuleset;
	/**
	 * Card bit-size for this test context (actual bits: 5..8).
	 * On-chain this is encoded as (8 - cardBitSize) in the DeckMap low bits.
	 */
	cardBitSize: number;
	alice: HardhatEthersSigner;
	player0: HardhatEthersSigner;
	player1: HardhatEthersSigner;
	player2: HardhatEthersSigner;
	player3: HardhatEthersSigner;
	accounts: HardhatEthersSigner[];
	encryptedDeck: EncryptedDeck;
	deckArray: number[];
};

const GAME_DATA_SLOT = 2n;
// Matches CardEngineView.PLAYER_DATA_OFFSET (players array slot inside GameData)
const PLAYERS_SLOT_OFFSET = 4n;
const ADDRESS_MASK = (1n << 160n) - 1n;
const U72_MASK = (1n << 72n) - 1n;

export type HookPermissionsConfig = {
	onStartGame?: boolean;
	onJoinGame?: boolean;
	onExecuteMove?: boolean;
	onFinishGame?: boolean;
	onPlayerExit?: boolean;
	hasSpecialMoves?: boolean;
	canBootOut?: boolean;
};

export const buildHookPermissions = (config: HookPermissionsConfig = {}): bigint => {
	const flags = {
		onStartGame: 1n << 0n,
		onJoinGame: 1n << 1n,
		onExecuteMove: 1n << 2n,
		onFinishGame: 1n << 3n,
		onPlayerExit: 1n << 4n,
		hasSpecialMoves: 1n << 5n,
		canBootOut: 1n << 6n,
	};

	let mask = 0n;
	if (config.onStartGame) mask |= flags.onStartGame;
	if (config.onJoinGame) mask |= flags.onJoinGame;
	if (config.onExecuteMove) mask |= flags.onExecuteMove;
	if (config.onFinishGame) mask |= flags.onFinishGame;
	if (config.onPlayerExit) mask |= flags.onPlayerExit;
	if (config.hasSpecialMoves) mask |= flags.hasSpecialMoves;
	if (config.canBootOut) mask |= flags.canBootOut;
	return mask;
};

export const extractMoveCommitted = (
	receipt: TransactionReceipt | null | undefined,
	iface: Interface,
): { encryptedCard: string; cardIndex: number } => {
	if (!receipt) {
		throw new Error("missing transaction receipt");
	}

	const moveCommittedEvent = iface.getEvent("MoveCommitted");
	if (!moveCommittedEvent) {
		throw new Error("MoveCommitted event not found in contract interface");
	}
	const topic0 = moveCommittedEvent.topicHash;
	for (const log of receipt.logs) {
		if (log.topics[0] !== topic0) continue;
		const parsed = iface.parseLog(log);
		if (!parsed) continue;
		const encryptedCard = parsed.args.cardToCommit as string;
		const cardIndex = Number(parsed.args.cardIndex as bigint);
		return { encryptedCard, cardIndex };
	}

	throw new Error("MoveCommitted event not found in receipt logs");
};

export const extractMarketDeckCommitted = (
	receipt: TransactionReceipt | null | undefined,
	iface: Interface,
): [string, string] => {
	if (!receipt) {
		throw new Error("missing transaction receipt");
	}

	const event = iface.getEvent("MarketDeckCommitted");
	if (!event) {
		throw new Error("MarketDeckCommitted event not found in contract interface");
	}
	const topic0 = event.topicHash;
	for (const log of receipt.logs) {
		if (log.topics[0] !== topic0) continue;
		const parsed = iface.parseLog(log);
		if (!parsed) continue;
		const deck = parsed.args.marketDeck;
		if (deck.length !== 2 || deck[0] === undefined || deck[1] === undefined) {
			throw new Error(
				`unexpected MarketDeckCommitted marketDeck length: ${deck.length}`,
			);
		}
		return [deck[0], deck[1]];
	}

	throw new Error("MarketDeckCommitted event not found in receipt logs");
};

export const deckIndexes = (deckMap: bigint): number[] => {
	const indexes: number[] = [];
	let raw = deckMap >> 2n;
	let bit = 0;
	while (raw !== 0n) {
		if ((raw & 1n) === 1n) indexes.push(bit);
		raw >>= 1n;
		bit++;
	}
	return indexes;
};

export const deckValuesFromMap = (
	deckMap: bigint,
	deckArray: readonly number[],
): number[] => deckIndexes(deckMap).map((idx) => deckArray[idx] ?? 0);

const decodePackedDeck = (
	deckMap: bigint,
	packedDeckWords: readonly bigint[],
): number[] => {
	const cardBitSize = 8 - Number(deckMap & 0x03n);
	const cardsPerWord = Math.floor(256 / cardBitSize);
	const mask = (1n << BigInt(cardBitSize)) - 1n;

	return deckIndexes(deckMap).map((idx) => {
		const wordIndex = Math.floor(idx / cardsPerWord);
		const bitOffset = BigInt((idx % cardsPerWord) * cardBitSize);
		const word = packedDeckWords[wordIndex] ?? 0n;
		return Number((word >> bitOffset) & mask);
	});
};

export const decodeDeck = async (
	deckMap: bigint,
	encryptedDeck: readonly [string, string],
): Promise<number[]> => {
	const h0 = encryptedDeck[0] as `0x${string}`;
	const h1 = encryptedDeck[1] as `0x${string}`;
	const decrypted = await fhevm.publicDecrypt([h0, h1]);
	const word0 = decrypted.clearValues[h0] as bigint;
	const word1 = decrypted.clearValues[h1] as bigint;

	return decodePackedDeck(deckMap, [word0, word1]);
};

export const decryptCard = async (
	encryptedCard: string,
): Promise<{
	clearCard: bigint;
	decryptionProof: `0x${string}`;
	abiEncodedClearValues: `0x${string}`;
}> => {
	const handle = encryptedCard as `0x${string}`;
	const decrypted = await fhevm.publicDecrypt([handle]);
	return {
		clearCard: decrypted.clearValues[handle] as bigint,
		decryptionProof: decrypted.decryptionProof,
		abiEncodedClearValues: decrypted.abiEncodedClearValues,
	};
};

export const extraDataForCard = (
	cardValue: number,
	deckArray?: number[],
): string => {
	const number = cardValue & 0x1f;
	if (number !== 20) return "0x";

	// Whot wish: pick the first non-20 card in the deck and use its shape.
	// If no such card exists (or deck is empty), default to Star (enum value 4).
	const defaultShape = 4;
	let shape = defaultShape;
	if (deckArray?.length) {
		const firstNonWish = deckArray.find((c) => (c & 0x1f) !== 20);
		if (firstNonWish !== undefined) {
			shape = (firstNonWish >> 5) & 0x07;
		}
	}
	return ethers.AbiCoder.defaultAbiCoder().encode(["uint8"], [shape]);
};

const keccak256Encode = (types: string[], values: readonly unknown[]): string =>
	ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(types, values));

const toAddress = (value: bigint): string =>
	ethers.getAddress(`0x${value.toString(16).padStart(40, "0")}`);

const loadBits = (value: bigint, offset: bigint, mask: bigint): bigint =>
	(value >> offset) & mask;

export const readGameData = async (cardEngine: CardEngine, gameId: bigint) => {
	// mirror CardEngineView.getGameDataSlot: keccak256(abi.encode(gameId, GAME_DATA_SLOT))
	const slot = keccak256Encode(
		["uint256", "uint256"],
		[gameId, GAME_DATA_SLOT],
	);
	const [raw0, raw1] = await cardEngine["extsload(uint256,uint256)"](slot, 2);
	const v0 = BigInt(raw0);
	const v1 = BigInt(raw1);

	return {
		gameCreator: toAddress(loadBits(v0, 0n, ADDRESS_MASK)),
		playerTurnIdx: loadBits(v0, 168n, 0xffn),
		status: loadBits(v0, 176n, 0xffn),
		// bit layout (slot 1): address ruleset (160) | DeckMap (72) | initialHandSize (8) | playersLeftToJoin (8) | recycle (8)
		playersLeftToJoin: loadBits(v1, 240n, 0xffn),
		hookPermissions: loadBits(v0, 232n, 0xffn),
		playerStoreMap: loadBits(v0, 240n, 0xffffn),
		marketDeckMap: loadBits(v1, 160n, U72_MASK),
		initialHandSize: loadBits(v1, 232n, 0xffn),
		ruleset: toAddress(loadBits(v1, 0n, ADDRESS_MASK)),
	};
};

export const readMarketDeckHandles = async (
	cardEngine: CardEngine,
	gameId: bigint,
): Promise<[string, string]> => {
	const gameSlot = BigInt(
		keccak256Encode(["uint256", "uint256"], [gameId, GAME_DATA_SLOT]),
	);
	const [h0, h1] = await cardEngine["extsload(uint256,uint256)"](
		gameSlot + 2n,
		2,
	);
	const toBytes32Hex = (value: unknown): string =>
		typeof value === "bigint" ? ethers.toBeHex(value, 32) : (value as string);
	return [toBytes32Hex(h0), toBytes32Hex(h1)];
};

export const readPlayerData = async (
	cardEngine: CardEngine,
	gameId: bigint,
	playerIndex: bigint,
) => {
	// mirror CardEngineView.getPlayerDataSlot:
	// slot = keccak256(abi.encode(gameId, GAME_DATA_SLOT)) + PLAYER_DATA_OFFSET;
	// slot = keccak256(abi.encode(slot)) + playerIndex * 3 (player struct uses 3 slots).
	const gameSlot = BigInt(
		keccak256Encode(["uint256", "uint256"], [gameId, GAME_DATA_SLOT]),
	);
	const baseSlot = gameSlot + PLAYERS_SLOT_OFFSET;
	const slot0 =
		BigInt(keccak256Encode(["uint256"], [baseSlot])) + playerIndex * 3n;
	const [raw0, raw1, raw2] = await cardEngine["extsload(uint256,uint256)"](
		slot0,
		3,
	);
	const v0 = BigInt(raw0 ?? 0);
	const v1 = BigInt(raw1 ?? 0);
	const v2 = BigInt(raw2 ?? 0);

	return {
		playerAddr: toAddress(loadBits(v0, 0n, ADDRESS_MASK)),
		deckMap: loadBits(v0, 160n, U72_MASK),
		pendingAction: loadBits(v0, 240n, 0xffn),
		forfeited: loadBits(v0, 248n, 0xffn) !== 0n,
		hand0: v1,
		hand1: v2,
	};
};

export const buildEncryptedInputFor = async (
	cardEngine: CardEngine,
	owner: string,
	deckArray: Array<number>,
	cardBitSize = 8,
): Promise<EncryptedDeck> => {
	if (!Number.isInteger(cardBitSize) || cardBitSize < 5 || cardBitSize > 8) {
		throw new Error(
			`cardBitSize must be an integer between 5 and 8 (got ${cardBitSize})`,
		);
	}

	const cardsPerWord = Math.floor(256 / cardBitSize);
	const maxValue = (1n << BigInt(cardBitSize)) - 1n;

	for (const v of deckArray) {
		if (!Number.isInteger(v) || v < 0) {
			throw new Error(`deck values must be non-negative integers (got ${v})`);
		}
		if (BigInt(v) > maxValue) {
			throw new Error(
				`deck value ${v} does not fit in cardBitSize=${cardBitSize}`,
			);
		}
	}

	const input = fhevm.createEncryptedInput(
		await cardEngine.getAddress(),
		owner,
	);

	const pack = (chunk: number[]): bigint =>
		chunk.reduce(
			(acc: bigint, v: number, i: number) =>
				acc | (BigInt(v) << BigInt(i * cardBitSize)),
			0n,
		);

	input.add256(pack(deckArray.slice(0, cardsPerWord)));
	if (deckArray.length > cardsPerWord) {
		input.add256(pack(deckArray.slice(cardsPerWord, cardsPerWord * 2)));
	}
	const raw = await input.encrypt();
	const handles = raw.handles.map((h) =>
		typeof h === "string" ? h : ethers.hexlify(h),
	);
	const inputProof =
		typeof raw.inputProof === "string"
			? raw.inputProof
			: ethers.hexlify(raw.inputProof);

	const input0: EInputDataStruct = {
		inputType: 6n, // InputType._EUINT256
		externalInput: handles[0],
	};

	const input1: EInputDataStruct = handles[1]
		? {
				inputType: 6n, // InputType._EUINT256
				externalInput: handles[1],
			}
		: {
				inputType: 0n, // InputType._EMPTY
				externalInput: "0x",
			};

	return { input0, input1, inputProof, handles };
};

const encodeCardBitSize = (cardBitSize: number): number => {
	if (!Number.isInteger(cardBitSize) || cardBitSize < 5 || cardBitSize > 8) {
		throw new Error(
			`cardBitSize must be an integer between 5 and 8 (got ${cardBitSize})`,
		);
	}
	return 8 - cardBitSize;
};

const parseGameId = (
	logs: readonly Log[] | undefined,
	iface: CardEngine["interface"],
): bigint => {
	if (!logs?.length) return 1n;
	const event = iface.getEvent("GameCreated");
	const topic0 = event?.topicHash;
	if (!topic0) return 1n;

	for (const log of logs) {
		if (log.topics[0] !== topic0) continue;
		try {
			const parsed = iface.parseLog(log);
			if (parsed?.args?.gameId !== undefined) {
				return parsed.args.gameId as bigint;
			}
		} catch {
			// ignore parse errors and continue
		}
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
		encryptedDeck: EncryptedDeck;
		recycleMarketDeck: boolean;
	}> = {},
) => {
	const encrypted = overrides.encryptedDeck ?? ctx.encryptedDeck;
	const cardBitSize = overrides.cardBitSize ?? ctx.cardBitSize;
	const cardDeckSize = overrides.cardDeckSize ?? ctx.deckArray.length;

	const params = {
		gameRuleset: overrides.gameRuleset ?? (await ctx.ruleset.getAddress()),
		cardBitSize: encodeCardBitSize(cardBitSize),
		cardDeckSize,
		maxPlayers: overrides.maxPlayers ?? 3,
		initialHandSize: overrides.initialHandSize ?? 2,
		proposedPlayers: overrides.proposedPlayers ?? [
			ctx.player0.address,
			ctx.player1.address,
			ctx.player2.address,
		],
		hookPermissions: overrides.hookPermissions ?? 0n,
		recycleMarketDeck: overrides.recycleMarketDeck ?? false,
		input0: encrypted.input0,
		input1: encrypted.input1,
		inputProof: encrypted.inputProof,
	};

	const tx = await ctx.cardEngine.connect(ctx.alice).createGame(params);
	const receipt = await tx.wait();
	const gameId = parseGameId(receipt?.logs, ctx.cardEngine.interface);
	return { gameId, params };
};

export const createManagedGame = async (
	ctx: EngineCtx,
	manager: MockManager,
	overrides: Partial<{ hookPermissions: bigint; recycleMarketDeck: boolean }> = {},
) => {
	const encrypted = await buildEncryptedInputFor(
		ctx.cardEngine,
		await manager.getAddress(),
		ctx.deckArray,
		ctx.cardBitSize,
	);
	const params = {
		gameRuleset: await ctx.ruleset.getAddress(),
		cardBitSize: encodeCardBitSize(ctx.cardBitSize),
		cardDeckSize: ctx.deckArray.length,
		maxPlayers: 3,
		initialHandSize: 2,
		proposedPlayers: [
			ctx.player0.address,
			ctx.player1.address,
			ctx.player2.address,
		],
		hookPermissions: overrides.hookPermissions ?? 0n,
		recycleMarketDeck: overrides.recycleMarketDeck ?? false,
		input0: encrypted.input0,
		input1: encrypted.input1,
		inputProof: encrypted.inputProof,
	};
	const tx = await manager.createGame(params);
	const receipt = await tx.wait();
	const gameId = parseGameId(receipt?.logs, ctx.cardEngine.interface);
	return { gameId, params };
};

export const deployMockManager = async (ctx: EngineCtx): Promise<MockManager> => {
	const managerFactory = await ethers.getContractFactory("MockManager");
	const manager = (await managerFactory
		.connect(ctx.alice)
		.deploy(await ctx.cardEngine.getAddress())) as MockManager;
	await manager.waitForDeployment();
	return manager;
};

export const setupManagedGame = async (
	ctx: EngineCtx,
	options: {
		manager: MockManager;
		hookPermissions?: bigint;
		recycleMarketDeck?: boolean;
	},
) => {
	const manager = options.manager;
	const { gameId } = await createManagedGame(ctx, manager, {
		hookPermissions: options.hookPermissions ?? 0n,
		recycleMarketDeck: options.recycleMarketDeck ?? false,
	});
	await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);
	await ctx.cardEngine.connect(ctx.player1).joinGame(gameId);
	await ctx.cardEngine.connect(ctx.player2).joinGame(gameId);
	await ctx.cardEngine.connect(ctx.alice).startGame(gameId);
	return { gameId };
};
