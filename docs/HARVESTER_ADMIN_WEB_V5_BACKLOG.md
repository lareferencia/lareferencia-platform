# Harvester Admin Web v5 — Backlog

**Status:** current · **Last verified:** 2026-09-23

The v5 administration UI (React 19 + Vite + Material UI) and the `/api/v5` management API are
**implemented and merged to `main`**. This document tracks the pending work extracted from the archived
technical plan ([`archive/HARVESTER_ADMIN_WEB_V5_TECHNICAL_PLAN.md`](archive/HARVESTER_ADMIN_WEB_V5_TECHNICAL_PLAN.md),
sections 5.2, 5.3 and 9.1) and confirmed still missing as of 2026-09-23.

## P1 — Needed for production hardening

- **Concurrent-edit protection**: add `version`/ETag to networks, validators and transformers and honor
  `If-Match` to detect conflicting edits (currently absent from the v5 API).
- **Action cancellation**: cancel by `processId` where the engine supports it (Flowable) and declare the
  scope explicitly for the legacy engine.
- Decide whether `STOP_HARVESTING` per snapshot remains a functional requirement.
- **Referential integrity UX**: `usedByNetworks` / reference endpoints so 409 conflicts are explained
  before deleting validators/transformers.
- **OpenAPI completeness**: publish all error codes, examples, limits and schemas.
- Keep `typeId` stable across class renames; keep aliases for migrated plugins.
- Add integration tests for CORS, HTTP Basic, JWT (OIDC mode) and Swagger UI in a real Spring context.
- Ensure rescheduling runs **after commit**, not inside a transaction that may roll back.

## P2 — Later improvements

- **SSE** for runtime status and command progress (start with adaptive polling as the interim).
- Persistent / auditable command history.
- Audit view for security events and administrative changes.
- Dry-run preview/validation of a rule configuration without persisting it.
- Endpoint to probe OAI-PMH connectivity and run `Identify` before saving a network.

## Frontend engineering gaps (vs. plan §6.1/§9.1)

Not yet present in `lareferencia-lrharvester-admin-web`:

- E2E/component testing toolchain (Playwright) and MSW for HTTP contract mocking
- Generated API client (`src/api/generated/` in the plan) — currently a hand-written
  `src/api/client.ts` + `src/api/types.ts`
- Only 2 unit tests in the repository today

## Server-side gaps confirmed 2026-09-23

- `RecordResponse` exposes `lastError` as a string; no structured error object yet (see the dark
  plan context for the planned shape).
- Entity `attributes` are not validated against their JSON Schema server-side.