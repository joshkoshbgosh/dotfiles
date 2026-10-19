import { planningRequestSchema, responseEnvelope } from "./protocol.js";
import { internalErrorResponse, solvePlanningRequest } from "./solver.js";

async function main() {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) chunks.push(Buffer.from(chunk));
  const input = Buffer.concat(chunks).toString("utf8");
  let raw: unknown;
  try {
    raw = JSON.parse(input);
  } catch (error) {
    process.stdout.write(`${JSON.stringify(responseEnvelope("unknown", {
      status: "invalid-request",
       baseline: null,
       scenario: null,
       baselinePortfolio: null,
       scenarioPortfolio: null,
      comparison: null,
      negotiationResults: [],
      errors: [{ path: "", message: `Invalid JSON: ${String(error)}` }],
    }))}\n`);
    process.exitCode = 2;
    return;
  }

  const parsed = planningRequestSchema.safeParse(raw);
  if (!parsed.success) {
    const requestId = typeof raw === "object" && raw !== null
      && "requestId" in raw && typeof raw.requestId === "string"
      ? raw.requestId
      : "unknown";
    process.stdout.write(`${JSON.stringify(responseEnvelope(requestId, {
      status: "invalid-request",
      baseline: null,
      scenario: null,
      baselinePortfolio: null,
      scenarioPortfolio: null,
      comparison: null,
      negotiationResults: [],
      errors: parsed.error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      })),
    }))}\n`);
    process.exitCode = 2;
    return;
  }

  try {
    process.stdout.write(`${JSON.stringify(await solvePlanningRequest(parsed.data))}\n`);
  } catch (error) {
    process.stdout.write(`${JSON.stringify(internalErrorResponse(parsed.data, error))}\n`);
    process.exitCode = 1;
  }
}

await main();
