import { serve } from "bun";
import { TappdClient } from "@phala/dstack-sdk";
import { toViemAccountSecure } from "@phala/dstack-sdk/viem";
import { toKeypairSecure } from "@phala/dstack-sdk/solana";
import { encryptMultipleDeck } from "./encrypt";

// ---------------------- small job queue ----------------------
type JobStatus = "queued" | "running" | "done" | "error";
type Job = {
  id: string;
  status: JobStatus;
  progress: number; // 0..100
  totalSize: number;
  contractAddress: string;
  importerAddress: string;
  result?: string[]; // hex strings of inputProofs for JSON-safe return
  error?: string;
};

const jobs = new Map<string, Job>();
const queue: string[] = [];
let queueRunning = false;

function enqueue(job: Job) {
  jobs.set(job.id, job);
  queue.push(job.id);
  void runQueue();
}

function u8ToHex(u8: Uint8Array): string {
  return Buffer.from(u8).toString("hex");
}

async function runQueue() {
  if (queueRunning) return;
  queueRunning = true;
  try {
    while (queue.length) {
      const id = queue.shift()!;
      const job = jobs.get(id);
      if (!job) continue;

      try {
        job.status = "running";
        job.progress = 0;

        // call encryptMultipleDeck with a progress callback
        const proofsU8 = await encryptMultipleDeck(
          job.totalSize,
          job.contractAddress,
          job.importerAddress,
          (produced, expected) => {
            // progress based on produced/expected
            job.progress = Math.floor((produced / expected) * 100);
          }
        );

        job.result = proofsU8.map(u8ToHex);
        job.status = "done";
        job.progress = 100;
      } catch (e: any) {
        job.status = "error";
        job.error = e?.stack || String(e);
        // don't throw; continue processing the rest
      }
    }
  } finally {
    queueRunning = false;
  }
}

// ---------------------- server ----------------------
const port = Number(process.env.PORT || 3000);
console.log(`Listening on port ${port}`);

serve({
  port,
  // NOTE: don't set idleTimeout > 255; default is fine for Bun.
  routes: {
    "/": async () => {
      const client = new TappdClient();
      const result = await client.info();
      return new Response(JSON.stringify(result), {
        headers: { "Content-Type": "application/json" },
      });
    },

    "/tdx_quote": async () => {
      const client = new TappdClient();
      const result = await client.tdxQuote("test");
      return new Response(JSON.stringify(result), {
        headers: { "Content-Type": "application/json" },
      });
    },

    "/tdx_quote_raw": async () => {
      const client = new TappdClient();
      const result = await client.tdxQuote("Hello DStack!", "raw");
      return new Response(JSON.stringify(result), {
        headers: { "Content-Type": "application/json" },
      });
    },

    "/derive_key": async () => {
      const client = new TappdClient();
      const result = await client.deriveKey("test");
      return new Response(JSON.stringify(result), {
        headers: { "Content-Type": "application/json" },
      });
    },

    "/ethereum": async () => {
      const client = new TappdClient();
      const result = await client.deriveKey("ethereum");
      const viemAccount = toViemAccountSecure(result);
      return new Response(
        JSON.stringify({ address: viemAccount.address }),
        { headers: { "Content-Type": "application/json" } }
      );
    },

    // Start an async shuffle+encrypt job and return a jobId immediately.
    "/shuffle": async (req) => {
      // Client can POST JSON { totalSize?, contractAddress?, importerAddress? }
      let totalSize = 24576;
      let contractAddress = process.env.CONTRACT_ADDRESS || "";
      let importerAddress = process.env.IMPORTER_ADDRESS || "";

      try {
        if (req.method === "POST") {
          const body = await req.json().catch(() => ({}));
          if (typeof body.totalSize === "number" && body.totalSize > 0) {
            totalSize = body.totalSize | 0;
          }
          if (typeof body.contractAddress === "string") {
            contractAddress = body.contractAddress;
          }
          if (typeof body.importerAddress === "string") {
            importerAddress = body.importerAddress;
          }
        }
      } catch {
        // ignore body parse errors; fall back to env/defaults
      }

      if (!contractAddress || !importerAddress) {
        return new Response(
          JSON.stringify({
            error:
              "Missing contract/importer address. Provide via env or POST body.",
          }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }

      const id = crypto.randomUUID();
      const job: Job = {
        id,
        status: "queued",
        progress: 0,
        totalSize,
        contractAddress,
        importerAddress,
      };
      enqueue(job);

      return new Response(JSON.stringify({ jobId: id, status: job.status }), {
        headers: { "Content-Type": "application/json" },
      });
    },

    // Poll job status: /shuffle/status?id=<jobId>
    "/shuffle/status": async (req) => {
      const url = new URL(req.url);
      const id = url.searchParams.get("id") || "";
      const job = id ? jobs.get(id) : undefined;

      if (!job) {
        return new Response(
          JSON.stringify({ error: "Job not found" }),
          { status: 404, headers: { "Content-Type": "application/json" } }
        );
      }

      // When done, return results (hex strings) as well
      return new Response(
        JSON.stringify({
          jobId: job.id,
          status: job.status,
          progress: job.progress,
          result: job.status === "done" ? job.result : undefined,
          error: job.status === "error" ? job.error : undefined,
        }),
        { headers: { "Content-Type": "application/json" } }
      );
    },
  },
});
