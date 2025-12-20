import "@fhevm/hardhat-plugin";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers, fhevm } from "hardhat";
import type { CardEngine } from "../types/src/CardEngine";
import type { MockManager } from "../types/src/mocks/MockManager";
import type { MockRuleset } from "../types/src/mocks/MockRuleset";
import type { EngineCtx } from "./helpers/engine";
import {
	buildEncryptedInputFor,
	createGameWithDefaults,
	deckIndexes,
	extractMarketDeckCommitted,
	extractMoveCommitted,
	extraDataForCard,
	readGameData,
	readPlayerData,
	setupManagedGame,
} from "./helpers/engine";

const ACTION = {
	Play: 0,
	Defend: 1,
	Draw: 2,
	Neutral: 3,
} as const;

const WHOT_DECK_TEMPLATE = [
	1, 2, 3, 4, 5, 7, 8, 10, 11, 12, 13, 14, 65, 66, 67, 68, 69, 71, 72, 74, 75,
	76, 77, 78, 33, 34, 35, 37, 39, 42, 43, 45, 46, 97, 98, 99, 101, 103, 106,
	107, 109, 110, 129, 130, 131, 132, 133, 135, 136, 180, 180, 180, 180, 180,
];

const startDefaultGame = async (ctx: EngineCtx) => {
	const { gameId } = await createGameWithDefaults(ctx);
	await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);
	await ctx.cardEngine.connect(ctx.player1).joinGame(gameId);
	await ctx.cardEngine.connect(ctx.player2).joinGame(gameId);
	await ctx.cardEngine.connect(ctx.alice).startGame(gameId);
	return gameId;
};

const currentPlayerCtx = async (ctx: EngineCtx, gameId: bigint) => {
	const gameData = await readGameData(ctx.cardEngine, gameId);
	const currentIndex = gameData.playerTurnIdx;
	const playerData = await readPlayerData(ctx.cardEngine, gameId, currentIndex);
	const playersByIndex = [
		ctx.player0,
		ctx.player1,
		ctx.player2,
		ctx.player3,
		ctx.alice,
		...(ctx.accounts ?? []),
	];
	const signer = playersByIndex[Number(currentIndex)];
	const cardIndexes = deckIndexes(playerData.deckMap);
	return { gameData, currentIndex, playerData, signer, cardIndexes };
};

async function deployEngineFixture(): Promise<EngineCtx> {
	if (!fhevm.isMock) {
		throw new Error(
			"This hardhat test suite can only run in FHEVM mock environment",
		);
	}
	const accounts = await ethers.getSigners();
	const [alice, player0, player1, player2, player3] = accounts;
	const cardEngineFactory = await ethers.getContractFactory("CardEngine");
	const cardEngine = (await cardEngineFactory
		.connect(alice)
		.deploy()) as CardEngine;
	await cardEngine.waitForDeployment();

	const rulesetFactory = await ethers.getContractFactory("MockRuleset");
	const ruleset = (await rulesetFactory
		.connect(alice)
		.deploy(await cardEngine.getAddress())) as MockRuleset;
	await ruleset.waitForDeployment();

	const deckArray = [...WHOT_DECK_TEMPLATE];
	const encryptedDeck = await buildEncryptedInputFor(
		cardEngine,
		alice.address,
		deckArray,
	);

	return {
		cardEngine,
		ruleset,
		alice,
		player0,
		player1,
		player2,
		player3,
		accounts: accounts.slice(4),
		deckArray,
		encryptedDeck,
	} as EngineCtx;
}

describe("Engine", () => {
	describe("Create Game", () => {
		it("Should emit game id", async () => {
			const ctx = await deployEngineFixture();
			const { gameId } = await createGameWithDefaults(ctx);
			expect(gameId).to.equal(1n);
		});

		it("initializes marketDeckMap with expected deck size and card bit size", async () => {
			const ctx = await deployEngineFixture();
			const deckSize = 54;
			const bitSize = 8;
			const { gameId } = await createGameWithDefaults(ctx, {
				cardDeckSize: deckSize,
				cardBitSize: bitSize,
			});
			const { marketDeckMap } = await readGameData(ctx.cardEngine, gameId);
			const idxs = deckIndexes(marketDeckMap);
			expect(idxs.length).to.equal(deckSize);
			const encodedBitSize = 8n - (marketDeckMap & 0x03n);
			expect(encodedBitSize).to.equal(bitSize);
		});

		it("reverts when initial hand size exceeds available cards", async () => {
			const ctx = await deployEngineFixture();
			await expect(
				createGameWithDefaults(ctx, {
					proposedPlayers: [],
					maxPlayers: 4,
					initialHandSize: 20,
				}),
			).to.be.revertedWithCustomError(ctx.cardEngine, "CardDeckSizeTooSmall");
		});

		it("tracks playersLeftToJoin from proposed players length", async () => {
			const ctx = await deployEngineFixture();
			const proposed = [
				ctx.player0.address,
				ctx.player1.address,
				ctx.player2.address,
			];
			const { gameId } = await createGameWithDefaults(ctx, {
				proposedPlayers: proposed,
			});
			const { playersLeftToJoin } = await readGameData(ctx.cardEngine, gameId);
			expect(playersLeftToJoin).to.equal(proposed.length);
		});
	});

	describe("Join Game", () => {
		it("allows proposed players to join and decrements players left to join", async () => {
			const ctx = await deployEngineFixture();
			const { gameId } = await createGameWithDefaults(ctx);

			await expect(ctx.cardEngine.connect(ctx.player0).joinGame(gameId))
				.to.emit(ctx.cardEngine, "PlayerJoined")
				.withArgs(gameId, ctx.player0.address);

			const { playersLeftToJoin } = await readGameData(ctx.cardEngine, gameId);
			const playerData = await readPlayerData(ctx.cardEngine, gameId, 0n);

			expect(playersLeftToJoin).to.equal(2n);
			expect(playerData.playerAddr).to.equal(ctx.player0.address);
		});

		it("allows the game creator to join the game they created", async () => {
			const ctx = await deployEngineFixture();
			const { gameId } = await createGameWithDefaults(ctx, {
				proposedPlayers: [],
				maxPlayers: 2,
			});

			await expect(ctx.cardEngine.connect(ctx.alice).joinGame(gameId))
				.to.emit(ctx.cardEngine, "PlayerJoined")
				.withArgs(gameId, ctx.alice.address);

			const { playersLeftToJoin } = await readGameData(ctx.cardEngine, gameId);
			const playerData = await readPlayerData(ctx.cardEngine, gameId, 0n);

			expect(playerData.playerAddr).to.equal(ctx.alice.address);
			expect(playersLeftToJoin).to.equal(1n);
		});

		it("rejects addresses that are not proposed players", async () => {
			const ctx = await deployEngineFixture();
			const { gameId } = await createGameWithDefaults(ctx);

			const stranger = ctx.accounts[0];
			await expect(ctx.cardEngine.connect(stranger).joinGame(gameId))
				.to.be.revertedWithCustomError(ctx.cardEngine, "NotProposedPlayer")
				.withArgs(stranger.address);
		});

		it("allows every proposed player to join and tracks their indices", async () => {
			const ctx = await deployEngineFixture();
			const { gameId } = await createGameWithDefaults(ctx);

			await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);
			await ctx.cardEngine.connect(ctx.player1).joinGame(gameId);
			await ctx.cardEngine.connect(ctx.player2).joinGame(gameId);

			const { playersLeftToJoin } = await readGameData(ctx.cardEngine, gameId);
			expect(playersLeftToJoin).to.equal(0n);
		});

		it("allows non-proposed players to join open games until capacity is reached", async () => {
			const ctx = await deployEngineFixture();
			const { gameId } = await createGameWithDefaults(ctx, {
				proposedPlayers: [],
				maxPlayers: 3,
			});

			await expect(ctx.cardEngine.connect(ctx.player0).joinGame(gameId))
				.to.emit(ctx.cardEngine, "PlayerJoined")
				.withArgs(gameId, ctx.player0.address);

			await expect(ctx.cardEngine.connect(ctx.player1).joinGame(gameId))
				.to.emit(ctx.cardEngine, "PlayerJoined")
				.withArgs(gameId, ctx.player1.address);

			await expect(ctx.cardEngine.connect(ctx.player2).joinGame(gameId))
				.to.emit(ctx.cardEngine, "PlayerJoined")
				.withArgs(gameId, ctx.player2.address);

			const { playersLeftToJoin } = await readGameData(ctx.cardEngine, gameId);
			expect(playersLeftToJoin).to.equal(0n);
		});

		it("rejects join attempts once the game has started", async () => {
			const ctx = await deployEngineFixture();
			const { gameId } = await createGameWithDefaults(ctx);

			await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);
			await ctx.cardEngine.connect(ctx.player1).joinGame(gameId);
			await ctx.cardEngine.connect(ctx.player2).joinGame(gameId);

			await ctx.cardEngine.connect(ctx.alice).startGame(gameId);

			const spectator = ctx.accounts[0];
			await expect(
				ctx.cardEngine.connect(spectator).joinGame(gameId),
			).to.be.revertedWithCustomError(ctx.cardEngine, "GameAlreadyStarted");
		});

		it("caps open games at maxPlayers when proposedPlayers is empty", async () => {
			const ctx = await deployEngineFixture();
			const { gameId } = await createGameWithDefaults(ctx, {
				proposedPlayers: [],
				maxPlayers: 2,
			});

			await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);
			await ctx.cardEngine.connect(ctx.player1).joinGame(gameId);

			const { playersLeftToJoin } = await readGameData(ctx.cardEngine, gameId);
			expect(playersLeftToJoin).to.equal(0n);

			await expect(ctx.cardEngine.connect(ctx.player2).joinGame(gameId))
				.to.be.revertedWithCustomError(ctx.cardEngine, "NotProposedPlayer")
				.withArgs(ctx.player2.address);
		});
	});

	describe("Start Game", () => {
		it("allows the game creator to start once all proposed players join", async () => {
			const ctx = await deployEngineFixture();
			const { gameId } = await createGameWithDefaults(ctx);
			await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);
			await ctx.cardEngine.connect(ctx.player1).joinGame(gameId);
			await ctx.cardEngine.connect(ctx.player2).joinGame(gameId);

			await expect(ctx.cardEngine.connect(ctx.alice).startGame(gameId))
				.to.emit(ctx.cardEngine, "GameStarted")
				.withArgs(gameId);

			const { status, playersLeftToJoin, playerTurnIdx } = await readGameData(
				ctx.cardEngine,
				gameId,
			);

			expect(status).to.equal(1n);
			expect(playersLeftToJoin).to.equal(0n);
			expect(playerTurnIdx).to.be.lessThan(3n);
		});

		it("prevents non-creators from starting before all players join", async () => {
			const ctx = await deployEngineFixture();
			const { gameId } = await createGameWithDefaults(ctx);
			await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);
			await ctx.cardEngine.connect(ctx.player1).joinGame(gameId);

			await expect(
				ctx.cardEngine.connect(ctx.player0).startGame(gameId),
			).to.be.revertedWithCustomError(ctx.cardEngine, "CannotStartGame");
		});

		it("requires at least two players to start even for the creator", async () => {
			const ctx = await deployEngineFixture();
			const { gameId } = await createGameWithDefaults(ctx, {
				proposedPlayers: [],
				maxPlayers: 3,
			});
			await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);

			await expect(
				ctx.cardEngine.connect(ctx.alice).startGame(gameId),
			).to.be.revertedWithCustomError(ctx.cardEngine, "CannotStartGame");

			await ctx.cardEngine.connect(ctx.player1).joinGame(gameId);
			await expect(ctx.cardEngine.connect(ctx.alice).startGame(gameId))
				.to.emit(ctx.cardEngine, "GameStarted")
				.withArgs(gameId);
		});

		it("allows non-creators to start once every seat is filled", async () => {
			const ctx = await deployEngineFixture();
			const { gameId } = await createGameWithDefaults(ctx);
			await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);
			await ctx.cardEngine.connect(ctx.player1).joinGame(gameId);
			await ctx.cardEngine.connect(ctx.player2).joinGame(gameId);

			await expect(ctx.cardEngine.connect(ctx.player0).startGame(gameId))
				.to.emit(ctx.cardEngine, "GameStarted")
				.withArgs(gameId);

			const { status, playersLeftToJoin } = await readGameData(
				ctx.cardEngine,
				gameId,
			);

			expect(status).to.equal(1n);
			expect(playersLeftToJoin).to.equal(0n);
		});
	});
	describe("Execute Move", () => {
		it("reverts when executing a Play action without a committed move", async () => {
			const ctx = await deployEngineFixture();
			const gameId = await startDefaultGame(ctx);
			const { currentIndex, signer, cardIndexes } = await currentPlayerCtx(
				ctx,
				gameId,
			);

			const targetCardIdx = cardIndexes[0];
			const targetCardValue = ctx.deckArray[targetCardIdx];

			// Commit + decrypt to get a valid proof, then clear commitment.
			const commitTx = await ctx.cardEngine
				.connect(signer)
				.commitMove(gameId, targetCardIdx);
			const commitReceipt = await commitTx.wait();
			const { encryptedCard } = extractMoveCommitted(
				commitReceipt,
				ctx.cardEngine.interface,
			);

			const decrypted = await fhevm.publicDecrypt([encryptedCard]);
			const clearCard = decrypted.clearValues[encryptedCard as `0x${string}`];
			expect(clearCard).to.equal(targetCardValue);
			const decryptionProof: `0x${string}` = decrypted.decryptionProof;
			const abiEncodedClearValues: `0x${string}` =
				decrypted.abiEncodedClearValues;
			const proofData = ethers.AbiCoder.defaultAbiCoder().encode(
				["bytes", "bytes32", "bytes", "uint8"],
				[decryptionProof, encryptedCard, abiEncodedClearValues, targetCardIdx],
			);

			await ctx.cardEngine.connect(signer).breakCommitment(gameId);

			await expect(
				ctx.cardEngine
					.connect(signer)
					.executeMove(
						gameId,
						ACTION.Play,
						proofData,
						extraDataForCard(targetCardValue, ctx.deckArray),
					),
			).to.be.revertedWithCustomError(
				ctx.cardEngine,
				"AsyncHandler_InvalidCommitmentHash",
			);

			const { playerTurnIdx: postTurn } = await readGameData(
				ctx.cardEngine,
				gameId,
			);
			expect(postTurn).to.equal(currentIndex);
		});

		it("reverts when proof does not match the commitment", async () => {
			const ctx = await deployEngineFixture();
			const gameId = await startDefaultGame(ctx);
			const { currentIndex, signer, cardIndexes } = await currentPlayerCtx(
				ctx,
				gameId,
			);

			const targetCardIdx = cardIndexes[0];
			const targetCardValue = ctx.deckArray[targetCardIdx];
			const commitTx = await ctx.cardEngine
				.connect(signer)
				.commitMove(gameId, targetCardIdx);
			const commitReceipt = await commitTx.wait();
			const { encryptedCard } = extractMoveCommitted(
				commitReceipt,
				ctx.cardEngine.interface,
			);

			const { playerTurnIdx: postTurn } = await readGameData(
				ctx.cardEngine,
				gameId,
			);
			expect(postTurn).to.equal(currentIndex);

			const decrypted = await fhevm.publicDecrypt([encryptedCard]);
			const clearCard = decrypted.clearValues[encryptedCard as `0x${string}`];

			expect(clearCard).to.equal(targetCardValue);

			const decryptionProof: `0x${string}` = decrypted.decryptionProof;
			const abiEncodedClearValues: `0x${string}` =
				decrypted.abiEncodedClearValues;
			const wrongCardIdx = cardIndexes[1];
			const wrongProofData = ethers.AbiCoder.defaultAbiCoder().encode(
				["bytes", "bytes32", "bytes", "uint8"],
				[decryptionProof, encryptedCard, abiEncodedClearValues, wrongCardIdx],
			);

			await expect(
				ctx.cardEngine
					.connect(signer)
					.executeMove(
						gameId,
						ACTION.Play,
						wrongProofData,
						extraDataForCard(targetCardValue, ctx.deckArray),
					),
			).to.be.revertedWithCustomError(
				ctx.cardEngine,
				"AsyncHandler_InvalidCommitmentHash",
			);
		});

		it("prevents non-current players from executing Play actions", async () => {
			const ctx = await deployEngineFixture();
			const gameId = await startDefaultGame(ctx);
			const { currentIndex, signer, cardIndexes } = await currentPlayerCtx(
				ctx,
				gameId,
			);

			const targetCardIdx = cardIndexes[0];
			const targetCardValue = ctx.deckArray[targetCardIdx];
			const commitTx = await ctx.cardEngine
				.connect(signer)
				.commitMove(gameId, targetCardIdx);
			const commitReceipt = await commitTx.wait();
			const { encryptedCard } = extractMoveCommitted(
				commitReceipt,
				ctx.cardEngine.interface,
			);

			const decrypted = await fhevm.publicDecrypt([encryptedCard]);
			const clearCard = decrypted.clearValues[encryptedCard as `0x${string}`];
			expect(clearCard).to.equal(BigInt(targetCardValue));
			const decryptionProof: `0x${string}` = decrypted.decryptionProof;
			const abiEncodedClearValues: `0x${string}` =
				decrypted.abiEncodedClearValues;
			const proofData = ethers.AbiCoder.defaultAbiCoder().encode(
				["bytes", "bytes32", "bytes", "uint8"],
				[decryptionProof, encryptedCard, abiEncodedClearValues, targetCardIdx],
			);

			const allPlayers = [ctx.player0, ctx.player1, ctx.player2];
			const nextPlayer =
				allPlayers[Number(currentIndex + 1n) % allPlayers.length];

			await expect(
				ctx.cardEngine
					.connect(nextPlayer)
					.executeMove(
						gameId,
						ACTION.Play,
						proofData,
						extraDataForCard(targetCardValue, ctx.deckArray),
					),
			)
				.to.be.revertedWithCustomError(ctx.cardEngine, "InvalidPlayerAddress")
				.withArgs(nextPlayer.address);

			const { playerTurnIdx: postTurn } = await readGameData(
				ctx.cardEngine,
				gameId,
			);
			expect(postTurn).to.equal(currentIndex);
		});

		it("executes a committed Play action end-to-end", async () => {
			const ctx = await deployEngineFixture();
			const gameId = await startDefaultGame(ctx);
			const { currentIndex, signer, cardIndexes } = await currentPlayerCtx(
				ctx,
				gameId,
			);

			const targetCardIdx = cardIndexes[0];
			const targetCardValue = ctx.deckArray[targetCardIdx];

			const playerBefore = await readPlayerData(
				ctx.cardEngine,
				gameId,
				currentIndex,
			);
			const cardsBefore = deckIndexes(playerBefore.deckMap).length;

			const commitTx = await ctx.cardEngine
				.connect(signer)
				.commitMove(gameId, targetCardIdx);
			const commitReceipt = await commitTx.wait();
			const { encryptedCard } = extractMoveCommitted(
				commitReceipt,
				ctx.cardEngine.interface,
			);
			const decrypted = await fhevm.publicDecrypt([encryptedCard]);
			const clearCard = decrypted.clearValues[encryptedCard as `0x${string}`];
			expect(clearCard).to.equal(targetCardValue);
			const decryptionProof: `0x${string}` = decrypted.decryptionProof;
			const decryptionResult: `0x${string}` = decrypted.abiEncodedClearValues;
			const proofData = ethers.AbiCoder.defaultAbiCoder().encode(
				["bytes", "bytes32", "bytes", "uint8"],
				[decryptionProof, encryptedCard, decryptionResult, targetCardIdx],
			);

			await expect(
				ctx.cardEngine
					.connect(signer)
					.executeMove(
						gameId,
						ACTION.Play,
						proofData,
						extraDataForCard(targetCardValue, ctx.deckArray),
					),
			)
				.to.emit(ctx.cardEngine, "MoveExecuted")
				.withArgs(gameId, currentIndex, ACTION.Play);

			const playerAfter = await readPlayerData(
				ctx.cardEngine,
				gameId,
				currentIndex,
			);
			const cardsAfter = deckIndexes(playerAfter.deckMap).length;
			expect(cardsAfter).to.equal(cardsBefore - 1);
		});
	});

	describe("Boot Out / Forfeit", () => {
		it("allows the current player to forfeit after the game has started", async () => {
			const ctx = await deployEngineFixture();
			const gameId = await startDefaultGame(ctx);

			await expect(ctx.cardEngine.connect(ctx.player0).forfeit(gameId))
				.to.emit(ctx.cardEngine, "PlayerForfeited")
				.withArgs(gameId, 0);
		});

		it("prevents forfeiting before the game has started", async () => {
			const ctx = await deployEngineFixture();
			const { gameId } = await createGameWithDefaults(ctx);
			await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);
			await ctx.cardEngine.connect(ctx.player1).joinGame(gameId);

			await expect(
				ctx.cardEngine.connect(ctx.player0).forfeit(gameId),
			).to.be.revertedWithCustomError(ctx.cardEngine, "GameNotStarted");
		});

		it("prevents booting out an idle player when the manager denies", async () => {
			const ctx = await deployEngineFixture();
			const { gameId } = await setupManagedGame(ctx, { allowBootOut: false });

			await time.increase(300);

			await expect(ctx.cardEngine.connect(ctx.alice).bootOut(gameId, 0))
				.to.be.revertedWithCustomError(ctx.cardEngine, "CannotBootOutPlayer")
				.withArgs(ctx.player0.address);
		});

		it("prevents a booted player from executing moves", async () => {
			const ctx = await deployEngineFixture();
			const { gameId } = await setupManagedGame(ctx, { allowBootOut: true });

			const { signer, cardIndexes } = await currentPlayerCtx(ctx, gameId);
			const targetCardIdx = cardIndexes[0];
			const targetCardValue = ctx.deckArray[targetCardIdx];

			// Generate a real proof payload (then clear commitment so bootOut can proceed).
			const commitTx = await ctx.cardEngine
				.connect(signer)
				.commitMove(gameId, targetCardIdx);
			const commitReceipt = await commitTx.wait();
			const { encryptedCard } = extractMoveCommitted(
				commitReceipt,
				ctx.cardEngine.interface,
			);

			const decrypted = await fhevm.publicDecrypt([encryptedCard]);
			const clearCard = decrypted.clearValues[encryptedCard as `0x${string}`];
			expect(clearCard).to.equal(targetCardValue);
			const decryptionProof: `0x${string}` = decrypted.decryptionProof;
			const abiEncodedClearValues: `0x${string}` =
				decrypted.abiEncodedClearValues;
			const proofData = ethers.AbiCoder.defaultAbiCoder().encode(
				["bytes", "bytes32", "bytes", "uint8"],
				[decryptionProof, encryptedCard, abiEncodedClearValues, targetCardIdx],
			);

			await ctx.cardEngine.connect(signer).breakCommitment(gameId);

			await time.increase(300);

			await ctx.cardEngine.connect(ctx.alice).bootOut(gameId, 0);

			await expect(
				ctx.cardEngine
					.connect(ctx.player0)
					.executeMove(
						gameId,
						ACTION.Play,
						proofData,
						extraDataForCard(targetCardValue, ctx.deckArray),
					),
			)
				.to.be.revertedWithCustomError(ctx.cardEngine, "InvalidPlayerAddress")
				.withArgs(ctx.player0.address);
		});

		it("prevents booting out players with an unfulfilled commitment", async () => {
			const ctx = await deployEngineFixture();
			const { gameId, manager } = await setupManagedGame(ctx, {
				allowBootOut: true,
			});
			const { signer, cardIndexes } = await currentPlayerCtx(ctx, gameId);

			const targetCardIdx = cardIndexes[0];
			const commitTx = await ctx.cardEngine
				.connect(signer)
				.commitMove(gameId, targetCardIdx);
			await commitTx.wait();
			await (manager as MockManager)
				.connect(ctx.alice)
				.setBootOutPermission(true);

			// Reduce players to 2 without clearing the commitment (forfeit a non-current player).
			await ctx.cardEngine.connect(ctx.player2).forfeit(gameId);

			// Booting out a player here would end the game (only one left), which is forbidden
			// while there's an outstanding commitment.
			await expect(
				ctx.cardEngine.connect(ctx.alice).bootOut(gameId, 1),
			).to.be.revertedWithCustomError(
				ctx.cardEngine,
				"PlayerAlreadyCommittedAction",
			);
		});
	});

	describe("End Game (self-relayed decryption)", () => {
		it("accepts a valid market deck decryption proof after game ends", async () => {
			const ctx = await deployEngineFixture();
			const gameId = await startDefaultGame(ctx);

			await ctx.cardEngine.connect(ctx.player0).forfeit(gameId);

			const endTx = await ctx.cardEngine.connect(ctx.player1).forfeit(gameId);
			const endReceipt = await endTx.wait();

			const deckHandles = extractMarketDeckCommitted(
				endReceipt,
				ctx.cardEngine.interface,
			);

			const decrypted = await fhevm.publicDecrypt(deckHandles);
			const decryptionProof: `0x${string}` = decrypted.decryptionProof;
			const decryptedResult: `0x${string}` = decrypted.abiEncodedClearValues;
			const proofData = ethers.AbiCoder.defaultAbiCoder().encode(
				["bytes", "bytes32[2]", "bytes"],
				[decryptionProof, [deckHandles[0], deckHandles[1]], decryptedResult],
			);

			await expect(ctx.cardEngine.connect(ctx.alice).endGame(gameId, proofData))
				.to.not.be.reverted;
		});

		it("reverts when the market deck decryption proof was computed with a different handle order", async () => {
			const ctx = await deployEngineFixture();
			const gameId = await startDefaultGame(ctx);

			await ctx.cardEngine.connect(ctx.player0).forfeit(gameId);

			const endTx = await ctx.cardEngine.connect(ctx.player1).forfeit(gameId);
			const endReceipt = await endTx.wait();

			const deckHandles = extractMarketDeckCommitted(
				endReceipt,
				ctx.cardEngine.interface,
			);

			// Compute a proof for the reversed order [h1, h0]…
			const reversed = await fhevm.publicDecrypt([
				deckHandles[1],
				deckHandles[0],
			]);

			// …but submit it on-chain for the original order [h0, h1]. This must fail signature verification.
			const wrongProofData = ethers.AbiCoder.defaultAbiCoder().encode(
				["bytes", "bytes32[2]", "bytes"],
				[
					reversed.decryptionProof,
					[deckHandles[0], deckHandles[1]],
					reversed.abiEncodedClearValues,
				],
			);

			await expect(
				ctx.cardEngine.connect(ctx.alice).endGame(gameId, wrongProofData),
			).to.be.reverted;
		});
	});
});
