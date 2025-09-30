import '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';
import { EInputDataStruct } from '../types/contracts-exposed/base/EInputHandler.sol/$EInputHandler';
import { zeroPadValue } from 'ethers';

describe('Engine', function () {
  beforeEach(async function () {
    // Check if running in FHEVM mock environment
    if (!fhevm.isMock) {
        throw new Error(`This hardhat test suite can only run in FHEVM mock environment`);
    }
    const accounts = await ethers.getSigners();
    const [alice, bob, harry] = accounts;
    this.accounts = accounts.slice(3);
    this.alice = alice;
    this.bob = bob;
    this.harry = harry;

    const cardEngineFactory = await ethers.getContractFactory('CardEngine');
    const cardEngine = await cardEngineFactory.connect(alice).deploy();
    await cardEngine.waitForDeployment();
    this.cardEngine = cardEngine;

    const RngFactory = await ethers.getContractFactory('MockRNG');
    const rng = await RngFactory.connect(alice).deploy(12345);
    await rng.waitForDeployment();
    this.rng = rng;

    const rulesetFactory = await ethers.getContractFactory('WhotRuleset');
    const ruleset = await rulesetFactory.connect(alice).deploy(await rng.getAddress());
    await ruleset.waitForDeployment();
    this.ruleset = ruleset;
  });

  it('should work', async function () {
    const input = fhevm.createEncryptedInput(
      await this.cardEngine.target,
      this.alice.address
    );
    input.add256(
      0x6261484746454443424128272625242322210e0d0c0b0a090807060504030201n
    );
    input.add256(0xb4b4b4b4b4b4b4b48887868584838281686766656463n);

    const encryptedDeck = await input.encrypt();

    const inputData = ((): EInputDataStruct => {
      return {
        inputZero: encryptedDeck.handles[0],
        inputOneType: 2n,
        inputOne64: zeroPadValue("0x", 32),
        inputOne128: zeroPadValue("0x", 32),
        inputOne256: encryptedDeck.handles[1]
      };
    }).bind(this)();

    const transaction = await this.cardEngine.connect(this.alice).createGame(
      inputData,
      encryptedDeck.inputProof,
      [],
      await this.ruleset.getAddress(),
      8,
      54,
      4,
      2,
      0 // HookPermissions.NONE
    )
    await transaction.wait();


    
  });
});