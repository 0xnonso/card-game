import { createHash } from "node:crypto";
import { TappdClient } from "@phala/dstack-sdk";
import { toViemAccountSecure } from "@phala/dstack-sdk/viem";
import type {
	FastifyInstance,
	FastifyPluginAsync,
	RouteShorthandOptions,
} from "fastify";
import Redis from "ioredis";
import {
	createPublicClient,
	createWalletClient,
	encodeAbiParameters,
	encodeFunctionData,
	http,
	isAddress,
	keccak256,
	webSocket,
} from "viem";
import { sepolia } from "viem/chains";
import { encryptMultipleDeck } from "./encrypt";

// ---------- Config / constants ----------

const QUEUE_KEY = "queue:shuffle";
const JOB_KEY_PREFIX = "job:";
const MAX_HANDLE_BITS = 512; // two 256-bit handles

const REDIS_URL = process.env.REDIS_URL ?? "redis://127.0.0.1:6379";

// Worker concurrency: default 1, override via env if positive integer
let WORKER_CONCURRENCY = 1;
const workerEnv = process.env.WORKER_CONCURRENCY;
if (workerEnv) {
	const parsed = parseInt(workerEnv, 10);
	if (!Number.isNaN(parsed) && parsed > 0) {
		WORKER_CONCURRENCY = parsed;
	}
}

// Job TTL: default 24h, override via env if positive integer
const DEFAULT_JOB_TTL_SECONDS = 60 * 60 * 24; // 24h
let JOB_TTL_SECONDS = DEFAULT_JOB_TTL_SECONDS;

const ttlEnv = process.env.JOB_TTL_SECONDS;
if (ttlEnv) {
	const parsed = parseInt(ttlEnv, 10);
	if (!Number.isNaN(parsed) && parsed > 0) {
		JOB_TTL_SECONDS = parsed;
	}
}

// rate limit: one POST /shuffle per clientId per 10 minutes
const RATE_LIMIT_WINDOW_SECONDS = 10 * 60;

// Rate limit behavior on Redis errors: fail-open (true) or fail-close (false)
// Default is fail-close for security; set RATE_LIMIT_FAIL_OPEN=true to allow requests when Redis is unavailable
const RATE_LIMIT_FAIL_OPEN = process.env.RATE_LIMIT_FAIL_OPEN === "true";

// Timeout for encryption operations in milliseconds (default: 60 seconds)
const DEFAULT_ENCRYPTION_TIMEOUT_MS = 60 * 1000;
let ENCRYPTION_TIMEOUT_MS = DEFAULT_ENCRYPTION_TIMEOUT_MS;
const encryptionTimeoutEnv = process.env.ENCRYPTION_TIMEOUT_MS;
if (encryptionTimeoutEnv) {
	const parsed = parseInt(encryptionTimeoutEnv, 10);
	if (!Number.isNaN(parsed) && parsed > 0) {
		ENCRYPTION_TIMEOUT_MS = parsed;
	}
}

// on-chain callback: env toggle + config
const CALL_TRUSTED_CONTRACT = process.env.CALL_TRUSTED_CONTRACT === "true";
const ETH_RPC_URL = process.env.SHUFFLE_RPC_URL;
const TEE_WALLET_LABEL = process.env.TEE_WALLET_LABEL ?? "ethereum";

if (CALL_TRUSTED_CONTRACT && !ETH_RPC_URL) {
	throw new Error(
		"SHUFFLE_RPC_URL env var is required when CALL_TRUSTED_CONTRACT=true",
	);
}

const STORE_INPUT_PROOFS_ABI = [
	{
		type: "function",
		name: "storeInputProofs",
		stateMutability: "nonpayable",
		inputs: [
			{ name: "proofs", type: "bytes" },
			{ name: "deckHash", type: "bytes32" },
			{ name: "numProofs", type: "uint256" },
			{ name: "proofSize", type: "uint256" },
			{ name: "doubleHandle", type: "bool" },
		],
		outputs: [],
	},
] as const;

// ---------- Redis ----------

export const redis = new Redis(REDIS_URL);
// ioredis emits an "error" event that will crash the process if unhandled.
redis.on("error", (err) => {
	// eslint-disable-next-line no-console
	console.error("[redis] error:", err);
});

// ---------- Types / Job store ----------

export type JobStatus = "queued" | "running" | "done" | "error";

export interface Job {
	id: string;
	clientId: string;
	status: JobStatus;
	progress: number; // 0..100
	numProofs: number;
	contractAddress: string; // contract that consumes fresh ciphertexts
	importerAddress: string;
	trustedShuffleService: string; // contract that stores proofs/handles
	deck: number[];
	cardBitSize: number;
	deckHash: string; // keccak256(abi.encode(uint8[] deck))
	result?: string[]; // hex proofs
	error?: string;
	createdAt: string; // ISO timestamp
	updatedAt: string; // ISO timestamp
}

function jobKey(id: string): string {
	return `${JOB_KEY_PREFIX}${id}`;
}

const VALID_JOB_STATUSES: readonly JobStatus[] = [
	"queued",
	"running",
	"done",
	"error",
];

function isValidJob(obj: unknown): obj is Job {
	if (typeof obj !== "object" || obj === null) return false;

	const job = obj as Record<string, unknown>;

	// Required string fields
	if (typeof job.id !== "string") return false;
	if (typeof job.clientId !== "string") return false;
	if (typeof job.contractAddress !== "string") return false;
	if (typeof job.importerAddress !== "string") return false;
	if (typeof job.trustedShuffleService !== "string") return false;
	if (typeof job.deckHash !== "string") return false;
	if (typeof job.createdAt !== "string") return false;
	if (typeof job.updatedAt !== "string") return false;

	// Status must be one of the valid values
	if (
		typeof job.status !== "string" ||
		!VALID_JOB_STATUSES.includes(job.status as JobStatus)
	) {
		return false;
	}

	// Required number fields
	if (typeof job.progress !== "number" || !Number.isFinite(job.progress))
		return false;
	if (typeof job.numProofs !== "number" || !Number.isSafeInteger(job.numProofs))
		return false;
	if (
		typeof job.cardBitSize !== "number" ||
		!Number.isSafeInteger(job.cardBitSize)
	)
		return false;

	// Deck must be an array of numbers
	if (!Array.isArray(job.deck)) return false;
	for (const v of job.deck) {
		if (typeof v !== "number" || !Number.isSafeInteger(v)) return false;
	}

	// Optional fields
	if (job.result !== undefined) {
		if (!Array.isArray(job.result)) return false;
		for (const v of job.result) {
			if (typeof v !== "string") return false;
		}
	}
	if (job.error !== undefined && typeof job.error !== "string") return false;

	return true;
}

export async function saveJob(
	job: Job,
	ttlSeconds = JOB_TTL_SECONDS,
): Promise<void> {
	job.updatedAt = new Date().toISOString();
	const value = JSON.stringify(job);
	await redis.set(jobKey(job.id), value, "EX", ttlSeconds);
}

export async function getJob(id: string): Promise<Job | null> {
	const raw = await redis.get(jobKey(id));
	if (!raw) return null;
	try {
		const parsed: unknown = JSON.parse(raw);
		if (!isValidJob(parsed)) {
			// eslint-disable-next-line no-console
			console.error(
				"Job data failed validation for id",
				id,
				"- possible data corruption or schema mismatch",
			);
			return null;
		}
		return parsed;
	} catch (err) {
		// eslint-disable-next-line no-console
		console.error("Failed to parse job JSON for id", id, err);
		return null;
	}
}

export async function enqueueJob(job: Job): Promise<void> {
	const key = jobKey(job.id);
	const value = JSON.stringify(job);

	const multi = redis.multi();
	multi.set(key, value, "EX", JOB_TTL_SECONDS);
	multi.rpush(QUEUE_KEY, job.id);
	await multi.exec();
}

// ---------- Hashing: keccak256(abi.encode(uint8[] deck)) ----------

export function hashDeck(deck: number[]): string {
	for (let i = 0; i < deck.length; i++) {
		const v = deck[i];
		if (!Number.isSafeInteger(v) || v < 0 || v > 255) {
			throw new Error(
				`deck value at index ${i} = ${v} does not fit in uint8 (0..255), required for keccak256(abi.encode(uint8[]))`,
			);
		}
	}

	// Match on-chain computation: keccak256(abi.encode(uint8[] deck))
	const encoded = encodeAbiParameters([{ type: "uint8[]" }], [deck]);
	return keccak256(encoded);
}

// ---------- Rate limiting (per clientId) ----------

function rateLimitKeyForClient(clientId: string): string {
	const digest = createHash("sha256").update(clientId).digest("hex");
	return `rl:shuffle:client:${digest}`;
}

async function checkRateLimitForClient(clientId: string): Promise<boolean> {
	const key = rateLimitKeyForClient(clientId);

	try {
		const res = await redis.set(
			key,
			"1",
			"EX",
			RATE_LIMIT_WINDOW_SECONDS,
			"NX",
		);
		return res === "OK"; // OK => first call in window; null => already used
	} catch (err) {
		// eslint-disable-next-line no-console
		console.error("Rate limit check failed due to Redis error", err);
		if (RATE_LIMIT_FAIL_OPEN) {
			// eslint-disable-next-line no-console
			console.warn(
				"RATE_LIMIT_FAIL_OPEN is enabled, allowing request despite Redis error",
			);
			return true;
		}
		// Default: fail-close for security - reject request when rate limit cannot be verified
		return false;
	}
}

// ---------- Trusted shuffle contract call ----------

let cachedRpcChainId: number | undefined;

export interface TrustedShuffleResult {
	called: boolean;
	txHash?: string;
	skippedReason?: string;
	error?: string;
}

async function callTrustedShuffleService(
	job: Job,
	proofs: Uint8Array[],
	logger: FastifyInstance["log"],
): Promise<TrustedShuffleResult> {
	if (!CALL_TRUSTED_CONTRACT) {
		return { called: false, skippedReason: "CALL_TRUSTED_CONTRACT is disabled" };
	}
	if (!ETH_RPC_URL) {
		return { called: false, skippedReason: "SHUFFLE_RPC_URL not configured" };
	}

	if (!job.trustedShuffleService) {
		return {
			called: false,
			skippedReason: "trustedShuffleService address not provided in job",
		};
	}
	if (!TEE_WALLET_LABEL) {
		return { called: false, skippedReason: "TEE_WALLET_LABEL not configured" };
	}

	try {
		// Derive TEE-backed Ethereum account
		const client = new TappdClient();
		const keyResp = await client.deriveKey(TEE_WALLET_LABEL);
		const account = toViemAccountSecure(keyResp);

		const transport = ETH_RPC_URL.startsWith("ws")
			? webSocket(ETH_RPC_URL)
			: http(ETH_RPC_URL);

		const publicClient = createPublicClient({ transport });
		if (cachedRpcChainId === undefined) {
			cachedRpcChainId = await publicClient.getChainId();
		}
		const chainId = cachedRpcChainId;
		if (chainId !== sepolia.id) {
			const reason = `SHUFFLE_RPC_URL chain (${chainId}) is not Sepolia (${sepolia.id})`;
			logger.warn({ jobId: job.id, chainId }, reason);
			return { called: false, skippedReason: reason };
		}

		const wallet = createWalletClient({
			account,
			chain: sepolia,
			transport,
		});

		const proofBytes = ("0x" +
			Buffer.concat(proofs).toString("hex")) as `0x${string}`;
		const proofSize = proofs.length > 0 ? proofs[0].length : 0;
		const doubleHandle = job.deck.length * job.cardBitSize > 256;

		const data = encodeFunctionData({
			abi: STORE_INPUT_PROOFS_ABI,
			functionName: "storeInputProofs",
			args: [
				proofBytes,
				job.deckHash as `0x${string}`,
				BigInt(job.numProofs),
				BigInt(proofSize),
				doubleHandle,
			],
		});

		const txHash = await wallet.sendTransaction({
			to: job.trustedShuffleService as `0x${string}`,
			data,
		});

		logger.info(
			{ jobId: job.id, contract: job.trustedShuffleService, txHash },
			"called trustedShuffleService.storeInputProofs from TEE wallet",
		);

		return { called: true, txHash };
	} catch (err) {
		const errorMessage = err instanceof Error ? err.message : String(err);
		logger.error(
			{ jobId: job.id, err },
			"failed to call trustedShuffleService.storeInputProofs",
		);
		return { called: false, error: errorMessage };
	}
}

// ---------- Worker logic (used by worker process) ----------

let shuttingDown = false;

export function requestWorkerShutdown(): void {
	shuttingDown = true;
}

function hexlify(u8: Uint8Array): string {
	return `0x${Buffer.from(u8).toString("hex")}`;
}

async function delay(ms: number): Promise<void> {
	await new Promise((resolve) => setTimeout(resolve, ms));
}

class TimeoutError extends Error {
	constructor(message: string) {
		super(message);
		this.name = "TimeoutError";
	}
}

async function withTimeout<T>(
	promise: Promise<T>,
	timeoutMs: number,
	operationName: string,
): Promise<T> {
	let timeoutId: ReturnType<typeof setTimeout>;

	const timeoutPromise = new Promise<never>((_, reject) => {
		timeoutId = setTimeout(() => {
			reject(
				new TimeoutError(
					`${operationName} timed out after ${timeoutMs}ms`,
				),
			);
		}, timeoutMs);
	});

	try {
		return await Promise.race([promise, timeoutPromise]);
	} finally {
		clearTimeout(timeoutId!);
	}
}

async function processJob(
	jobId: string,
	logger: FastifyInstance["log"],
): Promise<void> {
	const job = await getJob(jobId);
	if (!job) {
		logger.warn({ jobId }, "job not found in store");
		return;
	}
	if (job.status !== "queued") {
		logger.warn({ jobId, status: job.status }, "job not in queued state");
		return;
	}

	job.status = "running";
	job.progress = 0;
	await saveJob(job);

	let lastProgressSave: Promise<void> | undefined;
	try {
		const encryptionPromise = encryptMultipleDeck(
			job.numProofs,
			job.contractAddress,
			job.importerAddress,
			(produced, expected) => {
				// Track progress based on last valid shuffle.
				const safeExpected = expected > 0 ? expected : 1;
				const percent = Math.floor((produced / safeExpected) * 100);
				const bounded = Math.max(0, Math.min(99, percent));

				if (bounded > job.progress) {
					job.progress = bounded;
					lastProgressSave = (lastProgressSave ?? Promise.resolve())
						.then(() => saveJob(job))
						.catch((err) => {
							logger.warn(
								{ jobId: job.id, err },
								"failed to persist progress update",
							);
						});
				}
			},
			job.deck,
			job.cardBitSize,
			job.id,
		);

		const proofs = await withTimeout(
			encryptionPromise,
			ENCRYPTION_TIMEOUT_MS,
			"Encryption operation",
		);

		if (lastProgressSave) {
			await lastProgressSave;
		}

		job.result = proofs.map(hexlify);
		job.status = "done";
		job.progress = 100; // 100 only on successful completion
		await saveJob(job);

		// Optional on-chain callback from TEE address, to contract fallback
		const callResult = await callTrustedShuffleService(job, proofs, logger);
		if (callResult.error) {
			// Log as warning since the shuffle itself succeeded, but the on-chain callback failed
			logger.warn(
				{ jobId, error: callResult.error },
				"on-chain callback failed after successful shuffle",
			);
		} else if (callResult.skippedReason) {
			logger.debug(
				{ jobId, reason: callResult.skippedReason },
				"on-chain callback skipped",
			);
		}
	} catch (e: unknown) {
		if (lastProgressSave) {
			await lastProgressSave;
		}
		job.status = "error";
		job.error = e instanceof Error ? e.message : String(e);
		await saveJob(job);
		logger.error({ err: e, jobId }, "error while processing job");
	}
}

async function workerLoop(
	workerId: number,
	logger: FastifyInstance["log"],
): Promise<void> {
	const blockingRedis = new Redis(REDIS_URL);
	blockingRedis.on("error", (err) => {
		logger.error({ err, workerId }, "[redis] worker error");
	});

	logger.info({ workerId, concurrency: WORKER_CONCURRENCY }, "worker started");
	try {
		while (!shuttingDown) {
			try {
				const res = await blockingRedis.blpop(QUEUE_KEY, 5);
				if (!res) continue;
				const [, jobId] = res;
				if (!jobId) continue;

				logger.info({ workerId, jobId }, "worker picked up job");
				await processJob(jobId, logger);
			} catch (err) {
				if (shuttingDown) {
					logger.info({ workerId }, "worker stopping after shutdown");
					return;
				}
				logger.error({ err, workerId }, "worker error, backing off");
				await delay(1000);
			}
		}
		logger.info({ workerId }, "worker exiting");
	} finally {
		try {
			await blockingRedis.quit();
		} catch {
			blockingRedis.disconnect();
		}
	}
}

export async function startWorkers(
	logger: FastifyInstance["log"],
): Promise<void> {
	for (let i = 0; i < WORKER_CONCURRENCY; i++) {
		void workerLoop(i, logger);
	}
}

// ---------- Route plugin: /shuffle (API process only) ----------

export interface ShuffleRequestBody {
	trustedShuffleService: string;
	contractAddress: string;
	importerAddress: string;
	numProofs?: number;
	cardBitSize?: number;
	deck: number[];
}

export interface ShuffleEnqueueResponse {
	jobId: string;
	status: JobStatus;
	progress: number;
	cardBitSize: number;
	deckHash: string;
}

// Shared schema fragments
const cardBitSizeSchema = {
	type: "integer",
	minimum: 5,
	maximum: 8,
} as const;

const deckSchema = {
	type: "array",
	items: { type: "integer", minimum: 0 },
	minItems: 1,
	maxItems: 512,
} as const;

const jobSummaryProperties = {
	jobId: { type: "string", format: "uuid" },
	status: {
		type: "string",
		enum: ["queued", "running", "done", "error"],
	},
	progress: { type: "integer", minimum: 0, maximum: 100 },
	cardBitSize: cardBitSizeSchema,
	deckHash: { type: "string" },
	contractAddress: { type: "string" },
	importerAddress: { type: "string" },
	trustedShuffleService: { type: "string" },
} as const;

const jobSummaryBaseSchema = {
	type: "object",
	properties: jobSummaryProperties,
} as const;

const shuffleBodySchema = {
	type: "object",
	required: [
		"trustedShuffleService",
		"contractAddress",
		"importerAddress",
		"deck",
	],
	properties: {
		trustedShuffleService: { type: "string", minLength: 1 },
		contractAddress: { type: "string", minLength: 1 },
		importerAddress: { type: "string", minLength: 1 },
		numProofs: { type: "integer", minimum: 1 },
		cardBitSize: cardBitSizeSchema,
		deck: deckSchema,
	},
	additionalProperties: false,
} as const;

const errorResponseSchema = {
	type: "object",
	required: ["error"],
	properties: {
		error: { type: "string" },
	},
} as const;

const shuffleEnqueueResponseSchema = {
	...jobSummaryBaseSchema,
	required: ["jobId", "status", "progress", "cardBitSize", "deckHash"],
} as const;

const shuffleStatusResponseSchema = {
	...jobSummaryBaseSchema,
	required: [
		"jobId",
		"status",
		"progress",
		"cardBitSize",
		"deckHash",
		"deckSize",
		"createdAt",
		"updatedAt",
	],
	properties: {
		...jobSummaryProperties,
		deckSize: { type: "integer", minimum: 0 },
		result: { type: "array", items: { type: "string" } },
		error: { type: "string" },
		createdAt: { type: "string", format: "date-time" },
		updatedAt: { type: "string", format: "date-time" },
	},
} as const;

function normalizeAndValidateShuffleBody(
	body: ShuffleRequestBody,
): Required<ShuffleRequestBody> {
	const trustedShuffleService = body.trustedShuffleService;
	const contractAddress = body.contractAddress;
	const importerAddress = body.importerAddress;

	const numProofs =
		body.numProofs === undefined ? 1 : Math.trunc(body.numProofs);
	const cardBitSize =
		body.cardBitSize === undefined ? 8 : Math.trunc(body.cardBitSize);
	const deck = body.deck;

	if (!isAddress(trustedShuffleService)) {
		throw new Error("trustedShuffleService must be a valid EVM address");
	}
	if (!isAddress(contractAddress)) {
		throw new Error("contractAddress must be a valid EVM address");
	}
	if (!isAddress(importerAddress)) {
		throw new Error("importerAddress must be a valid EVM address");
	}

	if (!Number.isSafeInteger(numProofs) || numProofs <= 0) {
		throw new Error("numProofs must be a positive integer");
	}
	if (
		!Number.isSafeInteger(cardBitSize) ||
		cardBitSize < 5 ||
		cardBitSize > 8
	) {
		throw new Error("cardBitSize must be an integer between 5 and 8");
	}
	if (!Array.isArray(deck) || deck.length === 0) {
		throw new Error(
			"deck is required and must be a non-empty array of integers",
		);
	}

	const maxValue = (BigInt(1) << BigInt(cardBitSize)) - BigInt(1);

	for (const v of deck) {
		if (!Number.isSafeInteger(v) || v < 0) {
			throw new Error("deck values must be non-negative safe integers");
		}
		if (BigInt(v) > maxValue) {
			throw new Error(`deck values must fit within cardBitSize=${cardBitSize}`);
		}
		// Required by the on-chain deck hash format: uint8[].
		if (v > 255) {
			throw new Error("deck values must fit within uint8 (0..255)");
		}
	}

	if (deck.length * cardBitSize > MAX_HANDLE_BITS) {
		throw new Error(
			"deck too large: requires more than two handles (increase handle capacity or shrink deck/bit size)",
		);
	}

	return {
		trustedShuffleService,
		contractAddress,
		importerAddress,
		numProofs,
		cardBitSize,
		deck,
	};
}

const shuffleRoutes: FastifyPluginAsync = async (fastify) => {
	const shuffleRouteOpts: RouteShorthandOptions = {
		schema: {
			body: shuffleBodySchema,
			response: {
				200: shuffleEnqueueResponseSchema,
				400: errorResponseSchema,
				401: errorResponseSchema,
				429: errorResponseSchema,
			},
		},
	};

	fastify.post<{
		Body: ShuffleRequestBody;
		Reply: ShuffleEnqueueResponse | { error: string };
	}>("/shuffle", shuffleRouteOpts, async (req, reply) => {
		let payload: { sub?: string; clientId?: string };
		try {
			const reqWithJwt = req as unknown as {
				jwtVerify: () => Promise<{ sub?: string; clientId?: string }>;
			};
			payload = await reqWithJwt.jwtVerify();
		} catch {
			return reply.code(401).send({ error: "unauthorized" });
		}
		const clientId = payload.sub ?? payload.clientId;
		if (!clientId) {
			return reply.code(401).send({ error: "unauthorized" });
		}

		const allowed = await checkRateLimitForClient(clientId);
		if (!allowed) {
			fastify.log.info({ clientId }, "rate limit hit for /shuffle");
			return reply.code(429).send({
				error: "rate limit: one POST /shuffle per 10 minutes for this clientId",
			});
		}

		let normalized: Required<ShuffleRequestBody>;
		try {
			normalized = normalizeAndValidateShuffleBody(req.body);
		} catch (e: unknown) {
			return reply
				.code(400)
				.send({ error: e instanceof Error ? e.message : String(e) });
		}

		let deckHash: string;
		try {
			deckHash = hashDeck(normalized.deck);
		} catch (e: unknown) {
			return reply
				.code(400)
				.send({ error: e instanceof Error ? e.message : String(e) });
		}

		const id = crypto.randomUUID();
		const now = new Date().toISOString();

		const job: Job = {
			id,
			clientId,
			status: "queued",
			progress: 0,
			numProofs: normalized.numProofs,
			contractAddress: normalized.contractAddress,
			importerAddress: normalized.importerAddress,
			trustedShuffleService: normalized.trustedShuffleService,
			deck: normalized.deck,
			cardBitSize: normalized.cardBitSize,
			deckHash,
			createdAt: now,
			updatedAt: now,
		};

		await enqueueJob(job);

		fastify.log.info({ clientId, jobId: id }, "enqueued shuffle job");

		return {
			jobId: job.id,
			status: job.status,
			progress: job.progress,
			cardBitSize: job.cardBitSize,
			deckHash: job.deckHash,
		};
	});

	const shuffleStatusRouteOpts: RouteShorthandOptions = {
		schema: {
			params: {
				type: "object",
				required: ["id"],
				properties: {
					id: { type: "string", minLength: 1 },
				},
				additionalProperties: false,
			},
			response: {
				200: shuffleStatusResponseSchema,
				400: errorResponseSchema,
				404: errorResponseSchema,
			},
		},
	};

	fastify.get<{
		Params: { id: string };
	}>("/shuffle/:id", shuffleStatusRouteOpts, async (req, reply) => {
		const { id } = req.params;
		if (!id) {
			return reply.code(400).send({ error: "job id is required" });
		}

		const job = await getJob(id);
		if (!job) {
			return reply.code(404).send({ error: "job not found" });
		}

		return {
			jobId: job.id,
			status: job.status,
			progress: job.progress,
			cardBitSize: job.cardBitSize,
			deckSize: job.deck.length,
			deckHash: job.deckHash,
			result: job.status === "done" ? job.result : undefined,
			error: job.status === "error" ? job.error : undefined,
			createdAt: job.createdAt,
			updatedAt: job.updatedAt,
		};
	});
};

export default shuffleRoutes;
