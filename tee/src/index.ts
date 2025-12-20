import dotenv from "dotenv";

dotenv.config();

import fastifyJwt from "@fastify/jwt";
import { TappdClient } from "@phala/dstack-sdk";
import { toViemAccountSecure } from "@phala/dstack-sdk/viem";
import Fastify from "fastify";
import shuffleRoutes, { redis } from "./shuffle";

// Simple PORT parsing: default 3000, override via env if valid
const DEFAULT_PORT = 3000;
let PORT = DEFAULT_PORT;

if (process.env.PORT) {
	const parsed = parseInt(process.env.PORT, 10);
	if (!Number.isNaN(parsed) && parsed > 0) {
		PORT = parsed;
	}
}

const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET) {
	throw new Error("JWT_SECRET env var is required for @fastify/jwt");
}

const fastify = Fastify({ logger: true });
const tappdClient = new TappdClient();

// Register @fastify/jwt plugin with shared secret
fastify.register(fastifyJwt, {
	secret: JWT_SECRET,
});

// Health check (includes Redis)
fastify.get("/health", async (_, reply) => {
	let redisStatus: "up" | "down" = "up";
	let redisError: string | undefined;

	try {
		await redis.ping();
	} catch (err) {
		redisStatus = "down";
		redisError = err instanceof Error ? err.message : String(err);
	}

	const status = redisStatus === "up" ? "ok" : "degraded";

	return reply.send({
		status,
		components: {
			redis: {
				status: redisStatus,
				error: redisError,
			},
		},
		timestamp: new Date().toISOString(),
	});
});

// Simple root ping
fastify.get("/", async () => ({ status: "ok" }));

// Demo endpoints (always enabled, but with error handling)
fastify.get("/tdx_quote", async (_, reply) => {
	try {
		const result = await tappdClient.tdxQuote("test");
		return reply.send(result);
	} catch (err) {
		fastify.log.error({ err }, "tdx_quote failed");
		return reply.code(500).send({ error: "tdx_quote failed" });
	}
});

fastify.get("/tdx_quote_raw", async (_, reply) => {
	try {
		const result = await tappdClient.tdxQuote("Hello DStack!", "raw");
		return reply.send(result);
	} catch (err) {
		fastify.log.error({ err }, "tdx_quote_raw failed");
		return reply.code(500).send({ error: "tdx_quote_raw failed" });
	}
});

fastify.get("/derive_key", async (_, reply) => {
	try {
		const result = await tappdClient.deriveKey("test");
		return reply.send(result);
	} catch (err) {
		fastify.log.error({ err }, "derive_key failed");
		return reply.code(500).send({ error: "derive_key failed" });
	}
});

fastify.get("/tee_wallet", async (_, reply) => {
	const WALLET_LABEL = process.env.TEE_WALLET_LABEL;
	if (!WALLET_LABEL) {
		return reply
			.code(500)
			.send({ error: "TEE_WALLET_LABEL env var is required" });
	}
	try {
		const result = await tappdClient.deriveKey(WALLET_LABEL);
		const viemAccount = toViemAccountSecure(result);
		return reply.send({ address: viemAccount.address });
	} catch (err) {
		fastify.log.error({ err }, "tee derive_key failed");
		return reply.code(500).send({ error: "tee derive_key failed" });
	}
});

// Route plugin (shuffle enqueue + status)
fastify.register(shuffleRoutes);

// Close Redis with Fastify
fastify.addHook("onClose", async () => {
	try {
		await redis.quit();
	} catch (err) {
		fastify.log.error({ err }, "failed to quit redis on close");
	}
});

let shuttingDown = false;

async function start(): Promise<void> {
	// Sanity-check Redis
	await redis.ping();

	// IMPORTANT: do NOT start workers here.
	// Workers are started in a separate process (worker.ts).

	await fastify.listen({ port: PORT, host: "0.0.0.0" });

	const shutdown = async () => {
		if (shuttingDown) return;
		shuttingDown = true;

		fastify.log.info("Shutting down API server...");
		try {
			await fastify.close();
		} catch (err) {
			fastify.log.error({ err }, "error while closing fastify");
		} finally {
			process.exit(0);
		}
	};

	process.on("SIGINT", shutdown);
	process.on("SIGTERM", shutdown);
}

start().catch((err) => {
	// eslint-disable-next-line no-console
	console.error("Failed to start server:", err);
	process.exit(1);
});
