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
const PLAYER_DATA_OFFSET = 4n;
const ADDRESS_MASK = (1n << 160n) - 1n;
const U64_MASK = (1n << 64n) - 1n;

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
		playersLeftToJoin: loadBits(v1, 232n, 0xffn),
		hookPermissions: loadBits(v0, 232n, 0xffn),
		playerStoreMap: loadBits(v0, 240n, 0xffn),
		marketDeckMap: loadBits(v1, 160n, U64_MASK),
		initialHandSize: loadBits(v1, 224n, 0xffn),
		ruleset: toAddress(loadBits(v1, 0n, ADDRESS_MASK)),
	};
};

export const readPlayerData = async (
	cardEngine: CardEngine,
	gameId: bigint,
	playerIndex: bigint,
) => {
	// mirror CardEngineView.getPlayerDataSlot:
	// slot = keccak256(abi.encode(gameId, GAME_DATA_SLOT)) + PLAYER_DATA_OFFSET;
	// slot = keccak256(abi.encode(slot)) + playerIndex;
	const gameSlot = BigInt(
		keccak256Encode(["uint256", "uint256"], [gameId, GAME_DATA_SLOT]),
	);
	const baseSlot = gameSlot + PLAYER_DATA_OFFSET;
	const slot =
		BigInt(keccak256Encode(["uint256"], [baseSlot])) + playerIndex * 3n;
	const [raw0, raw1, raw2] = await cardEngine["extsload(uint256,uint256)"](
		slot,
		3,
	);
	const v0 = BigInt(raw0 ?? 0);
	const v1 = BigInt(raw1 ?? 0);
	const v2 = BigInt(raw2 ?? 0);

	return {
		playerAddr: toAddress(loadBits(v0, 0n, ADDRESS_MASK)),
		deckMap: loadBits(v0, 160n, U64_MASK),
		pendingAction: loadBits(v0, 224n, 0xffn),
		score: loadBits(v0, 232n, 0xffffn),
		forfeited: loadBits(v0, 248n, 0xffn) !== 0n,
		hand0: v1,
		hand1: v2,
	};
};

export const buildEncryptedInputFor = async (
	cardEngine: CardEngine,
	owner: string,
	deckArray: Array<number>,
): Promise<EncryptedDeck> => {
	const input = fhevm.createEncryptedInput(
		await cardEngine.getAddress(),
		owner,
	);
	input.add256(
		deckArray
			.slice(0, 32)
			.reduce(
				(acc: bigint, v: number, i: number) =>
					acc | (BigInt(v) << BigInt(i * 8)),
				0n,
			),
	);
	input.add256(
		deckArray
			.slice(32)
			.reduce(
				(acc: bigint, v: number, i: number) =>
					acc | (BigInt(v) << BigInt(i * 8)),
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
	}> = {},
) => {
	const encrypted = overrides.encryptedDeck ?? ctx.encryptedDeck;

	const params = {
		gameRuleset: overrides.gameRuleset ?? (await ctx.ruleset.getAddress()),
		cardBitSize: overrides.cardBitSize ?? 0,
		cardDeckSize: overrides.cardDeckSize ?? 54,
		maxPlayers: overrides.maxPlayers ?? 3,
		initialHandSize: overrides.initialHandSize ?? 2,
		proposedPlayers: overrides.proposedPlayers ?? [
			ctx.player0.address,
			ctx.player1.address,
			ctx.player2.address,
		],
		hookPermissions: overrides.hookPermissions ?? 0n,
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
	overrides: Partial<{ hookPermissions: bigint }> = {},
) => {
	const encrypted = await buildEncryptedInputFor(
		ctx.cardEngine,
		await manager.getAddress(),
		ctx.deckArray,
	);
	const params = {
		gameRuleset: await ctx.ruleset.getAddress(),
		cardBitSize: 0,
		cardDeckSize: 54,
		maxPlayers: 3,
		initialHandSize: 2,
		proposedPlayers: [
			ctx.player0.address,
			ctx.player1.address,
			ctx.player2.address,
		],
		hookPermissions: overrides.hookPermissions ?? 0n,
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
	options: { manager: MockManager; hookPermissions?: bigint },
) => {
	const manager = options.manager;
	const { gameId } = await createManagedGame(ctx, manager, {
		hookPermissions: options.hookPermissions ?? 0n,
	});
	await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);
	await ctx.cardEngine.connect(ctx.player1).joinGame(gameId);
	await ctx.cardEngine.connect(ctx.player2).joinGame(gameId);
	await ctx.cardEngine.connect(ctx.alice).startGame(gameId);
	return { gameId };
};
