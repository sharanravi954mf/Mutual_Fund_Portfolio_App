# MoneyBowl generic outbox dispatcher

This service is the lightweight Oracle-VM scheduler/router for durable MoneyBowl integration work.

It does not own business state, claim events, retry NSE writes, or inspect event payloads. Its only job is:

1. fetch a bounded list of dispatchable event IDs and event types,
2. route each event ID to the configured worker,
3. sleep and repeat.

The worker-specific database claim/lease RPC remains the authority for ownership and idempotency. Duplicate dispatcher invocations are therefore safe: only one worker claim can win.

## Initial routes

The checked-in `routes.json` enables only:

- `integration.nse.ucc_registration_requested` -> `nse-ucc-registration-worker`
- `integration.nse.ucc_verification_requested` -> `nse-ucc-reconciliation-worker`

Future integration APIs can reuse the same dispatcher by adding a reviewed route and its worker token. No NSE business rules belong in this service.

## Security boundaries

The dispatcher never reads `event_outbox.payload`. The database RPC returns routing metadata only.

The Oracle host requires these secrets:

- `SUPABASE_SERVICE_ROLE_KEY` only for the narrow dispatch-feed RPC
- one worker bearer token per configured worker

Worker tokens are referenced by environment-variable name in `routes.json`; token values are never checked in.

The service does not follow HTTP redirects, ignores proxy environment variables, validates the Supabase origin, logs no response body or secret, runs as a non-root user, and exposes no listening port.

For Production, revisit whether the Oracle host should retain a broad Supabase service-role credential; a narrower dispatcher credential can replace it later without changing the routing model.

## Runtime defaults

- poll interval: 5 seconds
- failed-event retry delay: 30 seconds
- batch size: 10
- HTTP timeout: 45 seconds
- feed-failure backoff: 30 seconds
- exit after 12 consecutive feed failures so Docker can restart the process

The hosted Compose service caps the dispatcher at 0.10 CPU and 128 MiB RAM.

## Failure behavior

If the dispatcher is down, events remain durable in Supabase.

If a worker request never reaches the worker, the event remains eligible for a later poll.

If two dispatchers race, the worker claim RPC fences ownership.

If a worker claims an event and then crashes, the existing claim lease/recovery path decides whether the operation is safely retryable or requires reconciliation.

The dispatcher never changes an event status itself.
