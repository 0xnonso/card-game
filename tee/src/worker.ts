import dotenv from "dotenv";

dotenv.config();

import Fastify from "fastify";
import { redis, requestWorkerShutdown, startWorkers } from "./shuffle";

async function main() {
	// We use Fastify only for its logger here; no HTTP routes.
	const fastify = Fastify({ logger: true });

	fastify.log.info("Starting shuffle workers...");

	// Sanity-check Redis so we fail fast on misconfiguration.
	await redis.ping();

	// Start background worker loops (blpop + encryptMultipleDeck)
	await startWorkers(fastify.log);

	const shutdown = async () => {
		fastify.log.info("Shutting down shuffle workers...");
		requestWorkerShutdown();
		try {
			await fastify.close();
		} catch (err) {
			fastify.log.error({ err }, "error while closing worker fastify");
		} finally {
			try {
				await redis.quit();
			} catch {
				// ignore
			}
			process.exit(0);
		}
	};

	process.on("SIGINT", shutdown);
	process.on("SIGTERM", shutdown);
}

main().catch((err) => {
	// eslint-disable-next-line no-console
	console.error("Worker failed:", err);
	process.exit(1);
});
