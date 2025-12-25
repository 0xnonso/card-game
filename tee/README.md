# TEE Shuffle/Proof Worker (Bun + TypeScript)

Trusted shuffle/encryption service that:
- Accepts shuffle jobs via Fastify HTTP API (JWT bearer auth).
- Queues jobs in Redis.
- Worker shuffles/encrypts decks using TEE-backed randomness and produces proofs.
- Can call `TrustedShuffleService.storeInputProofs` on-chain with the generated proof bytes.

## Setup

```bash
cd tee
bun install
cp .env.example .env  # fill in all required URLs/keys
```

### Local dev
- Start HTTP API: `bun run dev`
- Start worker (separate process): `bun run dev:worker`
- Lint: `bun run lint`

### Redis
The service requires Redis. Provide the URL via `REDIS_URL` in `.env`.

### Shuffle API (Fastify)
- `POST /shuffle` (auth required): enqueue a shuffle job.
- `GET /shuffle/:id`: fetch job status/result.

### Scripts
- `scripts/issue-jwt.ts`: issue bearer/JWT tokens for API access.
- `scripts/redis-latency.ts`: simple Redis latency checker.

### Running the TEE stack locally (sequential)

1. **Start Redis** (required for queueing).
2. **Run the Tappd simulator** (for attestation/key-derivation demos):

```bash
# Mac
wget https://github.com/Leechael/tappd-simulator/releases/download/v0.1.4/tappd-simulator-0.1.4-aarch64-apple-darwin.tgz
tar -xvf tappd-simulator-0.1.4-aarch64-apple-darwin.tgz
cd tappd-simulator-0.1.4-aarch64-apple-darwin
./tappd-simulator -l unix:/tmp/tappd.sock

# Linux
wget https://github.com/Leechael/tappd-simulator/releases/download/v0.1.4/tappd-simulator-0.1.4-x86_64-linux-musl.tgz
tar -xvf tappd-simulator-0.1.4-x86_64-linux-musl.tgz
cd tappd-simulator-0.1.4-x86_64-linux-musl
./tappd-simulator -l unix:/tmp/tappd.sock
```

3. **Start the API**: `bun run dev`
4. **Start the worker** (separate terminal): `bun run dev:worker`

5. **Call endpoints**:
   - `/tdx_quote` and `/tdx_quote_raw` for attestation quotes
   - `/derive_key`, `/ethereum` for TEE-held keys
   - `/shuffle` to exercise the shuffle pipeline

### Notes
- Uses `@zama-fhe/relayer-sdk` + `@phala/dstack-sdk` for TEE/relayer integration.
- Expects network/RPC URLs and relayer addresses in `.env`.
