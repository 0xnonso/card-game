#!/usr/bin/env ts-node

import "dotenv/config";
import fastifyJwt from "@fastify/jwt";
import Fastify from "fastify";

async function main() {
	const secret = process.env.JWT_SECRET;
	if (!secret) {
		console.error("JWT_SECRET env var is required");
		process.exit(1);
	}

	const [, , clientIdArg, expiresInArg] = process.argv;
	if (!clientIdArg) {
		console.error("Usage: issue-jwt <clientId> [expiresIn]");
		process.exit(1);
	}

	const clientId = clientIdArg;
	const expiresIn = expiresInArg || "1h";

	const fastify = Fastify();
	await fastify.register(fastifyJwt, { secret });

	const token = fastify.jwt.sign({ sub: clientId }, { expiresIn });

	console.log(`Authorization: Bearer ${token}`);

	await fastify.close();
}

main().catch((err) => {
	console.error(err);
	process.exit(1);
});
