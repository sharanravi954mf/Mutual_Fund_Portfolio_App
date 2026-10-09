import { resolveConfig } from "./config.ts";
import { createHandler } from "./handler.ts";

// Invalid startup configuration produces a fixed diagnostic, never environment values.
let handler: (req: Request) => Promise<Response>;
try {
  handler = createHandler(resolveConfig((name) => Deno.env.get(name)), {
    log: (entry) => console.log(JSON.stringify(entry)),
  });
} catch {
  handler = () =>
    Promise.resolve(Response.json(
      { code: "outbox_configuration_invalid" },
      { status: 503 },
    ));
}
Deno.serve(handler);
