// scripts/redis-latency.ts
import Redis from "ioredis";

async function main() {
	const url = process.env.REDIS_URL ?? "redis://127.0.0.1:6379";
	const redis = new Redis(url);

	const t0 = performance.now();
	await redis.ping();
	const t1 = performance.now();

	const t2 = performance.now();
	await redis.set("latency:test", "1", "EX", 10);
	const t3 = performance.now();

	console.log("PING ms:", (t1 - t0).toFixed(2));
	console.log("SET  ms:", (t3 - t2).toFixed(2));

	await redis.quit();
}

main().catch(console.error);
