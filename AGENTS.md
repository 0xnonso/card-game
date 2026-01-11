# AGENTS.md

This document provides guidelines for AI agents working in this repository.

## Project Structure

- `contracts/` - Solidity smart contracts with Hardhat framework
- `tee/` - Trusted Execution Environment (TEE) shuffle service (Bun + TypeScript)
- Root level - Shared tooling and configuration

## Commands

### Root Level
```bash
bun install          # Install dependencies
bun lint             # Run Biome linter
bun check            # Run Biome check (lint + format)
bun format           # Auto-format code with Biome
bun format:check     # Check formatting without modifying files
```

### Contracts (cd contracts/)
```bash
bun compile          # Compile Solidity contracts
bun test            # Run all Hardhat tests
bun test <path>     # Run specific test file
bun test -t <pattern>  # Run tests matching name pattern (e.g., "should emit game id")
```

### TEE Service (cd tee/)
```bash
bun run dev          # Start Fastify API server
bun run dev:worker   # Start background shuffle worker (separate process)
bun run issue:jwt    # Issue JWT tokens for API authentication
```

## Code Style Guidelines

### TypeScript (Tee Service)

**Imports:**
```typescript
// 1. Node.js built-ins (with node: prefix)
import { createHash } from "node:crypto";

// 2. Third-party packages
import { TappdClient } from "@phala/dstack-sdk";
import Fastify from "fastify";

// 3. Type-only imports
import type { FastifyInstance } from "fastify";
```

**Naming Conventions:**
- Variables/functions: `camelCase`
- Classes/types/interfaces: `PascalCase`
- Constants: `UPPER_SNAKE_CASE`
- Private properties: `_privateProperty` (optional)

**Error Handling:**
```typescript
// Always check and handle errors explicitly
try {
  await someOperation();
} catch (err) {
  const errorMessage = err instanceof Error ? err.message : String(err);
  logger.error({ err }, "Operation failed");
  throw new Error(`Failed to complete operation: ${errorMessage}`);
}
```

**Type Safety:**
- Strict mode enabled in tsconfig.json
- Use `type` imports for type-only imports
- Prefer explicit types over `any`
- Use type guards for runtime validation: `obj is MyType`

**Validation:**
```typescript
// Validate inputs at API boundaries
function isValidJob(obj: unknown): obj is Job {
  if (typeof obj !== "object" || obj === null) return false;
  // ...additional checks
  return true;
}
```

### Solidity

**Compiler Settings:**
- Version: 0.8.29
- Optimizer enabled (200 runs)
- EVM version: Cancun

**Naming Conventions:**
- Contracts: `PascalCase`
- Functions: `camelCase`
- Events: `PascalCase`
- Errors: `PascalCase`
- State variables: `camelCase` (private), `publicVariable` (public)
- Constants: `UPPER_SNAKE_CASE`

**Testing (Hardhat):**
```typescript
import { expect } from "chai";
import { ethers } from "hardhat";

// Use describe blocks for test organization
describe("FeatureName", () => {
  beforeEach(async () => {
    // Setup
  });

  it("should do something", async () => {
    await expect(contract.method())
      .to.emit(contract, "EventName")
      .withArgs(arg1, arg2);
  });
});
```

## Formatting

- **Tool:** Biome (config in `biome.json`)
- **Rule:** Run `bun format` before committing
- **Line Length:** Not explicitly enforced, use reasonable length
- **Semicolons:** Required
- **Quotes:** Double quotes for strings
- **Indentation:** 2 spaces

## Validation

Always run these before submitting changes:
```bash
bun lint        # Check for lint errors
bun format      # Fix formatting issues
cd contracts && bun test  # Run contract tests
```

## Testing Strategy

- **Contracts:** Hardhat with Mocha/Chai
- **TEE Service:** Bun test runner (if tests exist)
- **Test Files:** Located in `contracts/test/` and `tee/test/` (if present)
- **Test Pattern:** Use descriptive names: `should emit game id`, `prevents unauthorized access`

## Important Notes

- TEE service requires Redis running (set REDIS_URL in .env)
- Hardhat tests require FHEVM mock environment
- Contracts use TypeChain for type generation (output: `contracts/types/`)
- Biome excludes: `contracts/lib/`, `contracts/artifacts/`, `contracts/cache/`, `contracts/out/`
