# card-game(wip)
A modular onchain crazy-eights-style card game engine with pluggable rulesets.

![Flow Chart](asset/diagram6.svg)

## Sepolia deployments

- MinimalRNG: `0x94C89619C4b3231C97a39B5d13fCb61236EEC888`
- CardEngine: `0xCd958720AaF14d982BAfCF9798de1E450d5D883F`
- TrustedShuffleServiceV0: `0xaA196379023c804e9d244B0d3511ab0498de28e7`
- WhotRuleset: `0x9b93c90985658Eb4357443B507Fc26e86AF44d2d`
- WhotManager: `0x93D751197A987CaB6d649056b0E008772d01Cc89`
- CardEngineView: `0x86575b469bDbE0139f90773e962860a842C5b8Dc`

Whot frontend: https://github.com/0xPr0f/card-game-interface

## Getting started

Prerequisites: [Bun](https://bun.sh/) installed.

```bash
# install repo toolchain (Biome, etc.)
bun install

# lint & type-style checks
bun lint
bun check

# format source
bun format
```

Project packages live in `contracts/` (Solidity + Foundry/Hardhat) and `tee/` (TEE shuffle service).
Refer to their READMEs for service-specific commands.
