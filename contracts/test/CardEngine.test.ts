import "@fhevm/hardhat-plugin";
import { expect } from "chai";
import { ethers, fhevm } from "hardhat";
import type { CardEngine } from "../types/src/CardEngine";
import type { WhotRuleset } from "../types/src/rules/WhotRuleset";
import type { MockRNG } from "../types/src/mocks/MockRng.sol/MockRNG";
import type { MockManager } from "../types/src/mocks/MockManager";
import type { EngineCtx } from "./helpers/engine";
import {
  buildEncryptedInputFor,
  createGameWithDefaults,
  setupManagedGame,
} from "./helpers/engine";

const ACTION = {
  Play: 0,
  Defend: 1,
  Draw: 2,
  Neutral: 4,
} as const;

const WHOT_DECK_TEMPLATE: ReadonlyArray<number> = [
  1, 2, 3, 4, 5, 7, 8, 10, 11, 12, 13, 14, 65, 66, 67, 68, 69, 71, 72, 74, 75,
  76, 77, 78, 33, 34, 35, 37, 39, 42, 43, 45, 46, 97, 98, 99, 101, 103, 106,
  107, 109, 110, 129, 130, 131, 132, 133, 135, 136, 180, 180, 180, 180, 180,
];

const deckIndexes = (deckMap: bigint | { toString(): string }): number[] => {
  const indexes: number[] = [];
  let raw = BigInt(deckMap.toString()) >> 2n;
  let bit = 0;
  while (raw !== 0n) {
    if ((raw & 1n) === 1n) indexes.push(bit);
    raw >>= 1n;
    bit++;
  }
  return indexes;
};

const extraDataForCard = (cardValue: number): string => {
  const number = cardValue & 0x1f;
  return number === 20 ? ethers.AbiCoder.defaultAbiCoder().encode(["uint8"], [0]) : "0x";
};

const signerFor = (ctx: EngineCtx, address: string) => {
  const candidates = [ctx.alice, ctx.player0, ctx.player1, ctx.player2, ctx.player3, ...(ctx.accounts ?? [])];
  const signer = candidates.find((candidate) => candidate.address === address);
  if (!signer) throw new Error(`Unknown signer for address ${address}`);
  return signer;
};

const startDefaultGame = async (ctx: EngineCtx) => {
  const { gameId } = await createGameWithDefaults(ctx);
  await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);
  await ctx.cardEngine.connect(ctx.player1).joinGame(gameId);
  await ctx.cardEngine.connect(ctx.player2).joinGame(gameId);
  await ctx.cardEngine.connect(ctx.alice).startGame(gameId);
  return gameId;
};

const currentPlayerCtx = async (ctx: EngineCtx, gameId: bigint) => {
  const gameData = await ctx.cardEngine.getGameData(gameId);
  const currentIndex = Number(gameData.playerTurnIdx);
  const playerData = await ctx.cardEngine.getPlayerData(gameId, currentIndex);
  const signer = signerFor(ctx, playerData.playerAddr);
  const cardIndexes = deckIndexes(playerData.deckMap);
  return { gameData, currentIndex, playerData, signer, cardIndexes };
};

async function deployEngineFixture(): Promise<EngineCtx> {
  if (!fhevm.isMock) {
    throw new Error("This hardhat test suite can only run in FHEVM mock environment");
  }
  const accounts = await ethers.getSigners();
  const [alice, player0, player1, player2, player3] = accounts;
  const cardEngineFactory = await ethers.getContractFactory("CardEngine");
  const cardEngine = (await cardEngineFactory.connect(alice).deploy()) as CardEngine;
  await cardEngine.waitForDeployment();

  const rngFactory = await ethers.getContractFactory("MockRNG");
  const rng = (await rngFactory.connect(alice).deploy(12345)) as MockRNG;
  await rng.waitForDeployment();

  const rulesetFactory = await ethers.getContractFactory("WhotRuleset");
  const ruleset = (await rulesetFactory
    .connect(alice)
    .deploy(await rng.getAddress(), await cardEngine.getAddress())) as WhotRuleset;
  await ruleset.waitForDeployment();

  const deckArray = [...WHOT_DECK_TEMPLATE];
  const encryptedDeck = await buildEncryptedInputFor(cardEngine, alice.address, deckArray);

  return {
    cardEngine,
    ruleset,
    rng,
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

    it("Should persist game data retrievable via getGameData", async () => {
      const ctx = await deployEngineFixture();
      const { params } = await createGameWithDefaults(ctx);
      const gameId = 1;

      const {
        gameCreator,
        callCard,
        playerTurnIdx,
        status,
        lastMoveTimestamp,
        playersLeftToJoin,
        hookPermissions,
        playerStoreMap,
        ruleset,
        marketDeckMap,
        initialHandSize,
      } = await ctx.cardEngine.getGameData(gameId);

      const expectedMarketDeckMap =
        (((1n << BigInt(params.cardDeckSize)) - 1n) << 2n) |
        (BigInt(params.cardBitSize) & 0x03n);

      expect(gameCreator).to.equal(ctx.alice.address);
      expect(callCard).to.equal(0n);
      expect(playerTurnIdx).to.equal(0n);
      expect(status).to.equal(0n);
      expect(lastMoveTimestamp).to.equal(0n);
      expect(playersLeftToJoin).to.equal(BigInt(params.maxPlayers));
      expect(hookPermissions).to.equal(params.hookPermissions);
      expect(playerStoreMap).to.equal(0n);
      expect(ruleset).to.equal(params.gameRuleset);
      expect(marketDeckMap).to.equal(expectedMarketDeckMap);
      expect(initialHandSize).to.equal(BigInt(params.initialHandSize));
    });
  });

  describe("Join Game", () => {
    it("allows proposed players to join and decrements players left to join", async () => {
      const ctx = await deployEngineFixture();
      const { gameId } = await createGameWithDefaults(ctx);

      await expect(ctx.cardEngine.connect(ctx.player0).joinGame(gameId))
        .to.emit(ctx.cardEngine, "PlayerJoined")
        .withArgs(gameId, ctx.player0.address);

      const { playersLeftToJoin } = await ctx.cardEngine.getGameData(gameId);
      const playerData = await ctx.cardEngine.getPlayerData(gameId, 0);

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

      const { playersLeftToJoin } = await ctx.cardEngine.getGameData(gameId);
      const playerData = await ctx.cardEngine.getPlayerData(gameId, 0);

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

      const [player0Data, player1Data, player2Data] = await Promise.all([
        ctx.cardEngine.getPlayerData(gameId, 0),
        ctx.cardEngine.getPlayerData(gameId, 1),
        ctx.cardEngine.getPlayerData(gameId, 2),
      ]);
      const { playersLeftToJoin } = await ctx.cardEngine.getGameData(gameId);

      expect(player0Data.playerAddr).to.equal(ctx.player0.address);
      expect(player1Data.playerAddr).to.equal(ctx.player1.address);
      expect(player2Data.playerAddr).to.equal(ctx.player2.address);
      expect(playersLeftToJoin).to.equal(0n);
    });

    it("allows non-proposed players to join open games until capacity is reached", async () => {
      const ctx = await deployEngineFixture();
      const { gameId } = await createGameWithDefaults(ctx, {
        proposedPlayers: [],
        maxPlayers: 3,
      });

      await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);
      await ctx.cardEngine.connect(ctx.player1).joinGame(gameId);

      await expect(ctx.cardEngine.connect(ctx.player2).joinGame(gameId))
        .to.emit(ctx.cardEngine, "PlayerJoined")
        .withArgs(gameId, ctx.player2.address);

      const { playersLeftToJoin } = await ctx.cardEngine.getGameData(gameId);
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
      await expect(ctx.cardEngine.connect(spectator).joinGame(gameId))
        .to.be.revertedWithCustomError(ctx.cardEngine, "GameAlreadyStarted");
    });

    it("caps open games at maxPlayers when proposedPlayers is empty", async () => {
      const ctx = await deployEngineFixture();
      const { gameId } = await createGameWithDefaults(ctx, {
        proposedPlayers: [],
        maxPlayers: 2,
      });

      await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);
      await ctx.cardEngine.connect(ctx.player1).joinGame(gameId);

      const { playersLeftToJoin } = await ctx.cardEngine.getGameData(gameId);
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

      const { status, playersLeftToJoin, playerTurnIdx } = await ctx.cardEngine.getGameData(gameId);

      expect(status).to.equal(1n);
      expect(playersLeftToJoin).to.equal(0n);
      expect(Number(playerTurnIdx)).to.be.lessThan(3);
    });

    it("prevents non-creators from starting before all players join", async () => {
      const ctx = await deployEngineFixture();
      const { gameId } = await createGameWithDefaults(ctx);
      await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);
      await ctx.cardEngine.connect(ctx.player1).joinGame(gameId);

      await expect(ctx.cardEngine.connect(ctx.player0).startGame(gameId))
        .to.be.revertedWithCustomError(ctx.cardEngine, "CannotStartGame");
    });

    it("allows the creator to start with at least two players even if spots remain", async () => {
      const ctx = await deployEngineFixture();
      const { gameId } = await createGameWithDefaults(ctx, {
        proposedPlayers: [],
        maxPlayers: 4,
      });
      await ctx.cardEngine.connect(ctx.alice).joinGame(gameId);
      await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);

      await expect(ctx.cardEngine.connect(ctx.alice).startGame(gameId))
        .to.emit(ctx.cardEngine, "GameStarted")
        .withArgs(gameId);

      const { status, playersLeftToJoin, playerTurnIdx } = await ctx.cardEngine.getGameData(gameId);

      expect(status).to.equal(1n);
      expect(playersLeftToJoin).to.equal(2n);
      expect(Number(playerTurnIdx)).to.be.lessThan(2);
    });

    it("requires at least two players to start even for the creator", async () => {
      const ctx = await deployEngineFixture();
      const { gameId } = await createGameWithDefaults(ctx, {
        proposedPlayers: [],
        maxPlayers: 3,
      });
      await ctx.cardEngine.connect(ctx.alice).joinGame(gameId);

      await expect(ctx.cardEngine.connect(ctx.alice).startGame(gameId))
        .to.be.revertedWithCustomError(ctx.cardEngine, "CannotStartGame");
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

      const { status, playersLeftToJoin } = await ctx.cardEngine.getGameData(gameId);

      expect(status).to.equal(1n);
      expect(playersLeftToJoin).to.equal(0n);
    });

    describe("Execute Move", () => {
      it("reverts when executing a Play action without a committed move", async () => {
        const ctx = await deployEngineFixture();
        const gameId = await startDefaultGame(ctx);
        const { currentIndex, signer } = await currentPlayerCtx(ctx, gameId);

        await expect(
          ctx.cardEngine.connect(signer).executeMove(Number(gameId), ACTION.Play, "0x"),
        ).to.be.revertedWith("AsyncHandler: no committed move for game");

        const postGame = await ctx.cardEngine.getGameData(gameId);
        expect(Number(postGame.playerTurnIdx)).to.equal(currentIndex);
      });

      it("requires the relayer to resolve a committed move before execution", async () => {
        const ctx = await deployEngineFixture();
        const gameId = await startDefaultGame(ctx);
        const { currentIndex, signer, cardIndexes } = await currentPlayerCtx(ctx, gameId);
        const targetCardIdx = cardIndexes[0];
        const commitTx = await ctx.cardEngine
          .connect(signer)
          .commitMove(Number(gameId), ACTION.Play, targetCardIdx);
        await commitTx.wait();

        await expect(
          ctx.cardEngine.connect(signer).executeMove(Number(gameId), ACTION.Play, "0x"),
        ).to.be.revertedWith("AsyncHandler: latest committed move not fulfilled");

        const postGame = await ctx.cardEngine.getGameData(gameId);
        expect(Number(postGame.playerTurnIdx)).to.equal(currentIndex);
      });

      it("prevents non-current players from executing Play actions", async () => {
        const ctx = await deployEngineFixture();
        const gameId = await startDefaultGame(ctx);
        const { currentIndex, signer, cardIndexes } = await currentPlayerCtx(ctx, gameId);
        const targetCardIdx = cardIndexes[0];

        const commitTx = await ctx.cardEngine
          .connect(signer)
          .commitMove(Number(gameId), ACTION.Play, targetCardIdx);
        await commitTx.wait();
        await fhevm.awaitDecryptionOracle();

        const allPlayers = [ctx.player0, ctx.player1, ctx.player2];
        const nextPlayer = allPlayers.find((p) => p.address !== signer.address) ?? ctx.player0;

        await expect(
          ctx.cardEngine.connect(nextPlayer).executeMove(Number(gameId), ACTION.Play, "0x"),
        )
          .to.be.revertedWithCustomError(ctx.cardEngine, "InvalidPlayerAddress")
          .withArgs(nextPlayer.address);

        const postGame = await ctx.cardEngine.getGameData(gameId);
        expect(Number(postGame.playerTurnIdx)).to.equal(currentIndex);
      });

      it("executes a committed Play action end-to-end", async () => {
        const ctx = await deployEngineFixture();
        const gameId = await startDefaultGame(ctx);
        const { currentIndex, signer, cardIndexes } = await currentPlayerCtx(ctx, gameId);
        const targetCardIdx = cardIndexes[0];
        const targetCardValue = ctx.deckArray[targetCardIdx] ?? 0;

        const playerBefore = await ctx.cardEngine.getPlayerData(gameId, currentIndex);
        const cardsBefore = deckIndexes(playerBefore.deckMap).length;

        const commitTx = await ctx.cardEngine
          .connect(signer)
          .commitMove(Number(gameId), ACTION.Play, targetCardIdx);
        await commitTx.wait();
        await fhevm.awaitDecryptionOracle();

        await expect(
          ctx.cardEngine
            .connect(signer)
            .executeMove(Number(gameId), ACTION.Play, extraDataForCard(targetCardValue)),
        )
          .to.emit(ctx.cardEngine, "MoveExecuted")
          .withArgs(gameId, currentIndex, ACTION.Play);

        const playerAfter = await ctx.cardEngine.getPlayerData(gameId, currentIndex);
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

        const playerData = await ctx.cardEngine.getPlayerData(gameId, 0);
        expect(playerData.forfeited).to.equal(true);
      });

      it("prevents forfeiting before the game has started", async () => {
        const ctx = await deployEngineFixture();
        const { gameId } = await createGameWithDefaults(ctx);
        await ctx.cardEngine.connect(ctx.player0).joinGame(gameId);
        await ctx.cardEngine.connect(ctx.player1).joinGame(gameId);

        await expect(ctx.cardEngine.connect(ctx.player0).forfeit(gameId))
          .to.be.revertedWithCustomError(ctx.cardEngine, "GameNotStarted");
      });

      it("prevents booting out an idle player when the manager denies", async () => {
        const ctx = await deployEngineFixture();
        const { gameId } = await setupManagedGame(ctx, { allowBootOut: false });

        await ethers.provider.send("evm_increaseTime", [300]);
        await ethers.provider.send("evm_mine", []);

        await expect(ctx.cardEngine.connect(ctx.alice).bootOut(gameId, 0))
          .to.be.revertedWithCustomError(ctx.cardEngine, "CannotBootOutPlayer")
          .withArgs(ctx.player0.address);
      });

      it("prevents a booted player from executing moves", async () => {
        const ctx = await deployEngineFixture();
        const { gameId } = await setupManagedGame(ctx, { allowBootOut: true });

        await ethers.provider.send("evm_increaseTime", [300]);
        await ethers.provider.send("evm_mine", []);

        await ctx.cardEngine.connect(ctx.alice).bootOut(gameId, 0);

        const bootedData = await ctx.cardEngine.getPlayerData(gameId, 0);
        expect(bootedData.forfeited).to.equal(true);

        await expect(ctx.cardEngine.connect(ctx.player0).executeMove(Number(gameId), ACTION.Play, "0x"))
          .to.be.revertedWithCustomError(ctx.cardEngine, "InvalidPlayerAddress")
          .withArgs(ctx.player0.address);
      });

      it("prevents booting out players with an unfulfilled commitment", async () => {
        const ctx = await deployEngineFixture();
        const { gameId, manager } = await setupManagedGame(ctx, { allowBootOut: true });

        const { signer, cardIndexes } = await currentPlayerCtx(ctx, gameId);
        const targetCardIdx = cardIndexes[0];
        const commitTx = await ctx.cardEngine
          .connect(signer)
          .commitMove(Number(gameId), ACTION.Play, targetCardIdx);
        await commitTx.wait();
        await (manager as MockManager).connect(ctx.alice).setBootOutPermission(true);

        await expect(ctx.cardEngine.connect(ctx.alice).bootOut(gameId, 0))
          .to.be.revertedWithCustomError(ctx.cardEngine, "PlayerAlreadyCommittedAction");
      });
    });
  });
});
