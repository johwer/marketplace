---
name: generate-api
description: "Regenerate RTK Query API types from backend Swagger endpoints. Use when backend API endpoints have been changed, added, or removed."
user_invocable: true
---

# Generate API Types

Regenerates frontend RTK Query API types from backend Swagger specs after backend changes.

## When to Use
- After changing any backend API endpoint (new, modified, or deleted)
- After changing request/response DTOs in a backend service
- When frontend types are out of sync with the backend
- **Never manually edit `*Api.ts` files** — always regenerate

## Service Map

| Service | Docker service | Port | Swagger URL |
|---------|---------------|------|-------------|
| ServiceC | service-c-api | 5001 | http://localhost:5001/api/service-c/swagger/v1.json |
| ServiceA | service-a-api | 5002 | http://localhost:5002/api/service-a/swagger/v1.json |
| ServiceE | service-e-api | 5003 | http://localhost:5003/api/service-e/swagger/v1.json |
| ServiceB | service-b-api | 5005 | http://localhost:5005/api/service-b/swagger/v1.json |
| ServiceD | service-d-api | 5006 | http://localhost:5006/api/service-d/swagger/v1.json |

## File Structure

Each service has three file types in `apps/web/src/store/rtk-apis/{service}/`:

| File | Maintained by | Editable? |
|------|--------------|-----------|
| `{service}Api.ts` | Codegen | **NO** — auto-generated, will be overwritten |
| `{service}BaseApi.ts` | Developer | Yes — base API config, cache tags |
| `{service}ApiEnhanced.ts` | Developer | Yes — cache invalidation, manual overrides, temporary types |

## Steps

1. **Identify which service(s) changed.** Check your git diff for modified files under `services/`.

2. **Determine the working directory.** If in a worktree, use that path for Docker:
   ```bash
   # From repo root (or worktree root)
   REPO_ROOT=$(git rev-parse --show-toplevel)
   ```

3. **Rebuild and start the Docker container** for the changed service:
   ```bash
   docker compose up -d --build {service}-api
   ```
   Only rebuild the specific service — full stack rebuild is unnecessary.

4. **Wait for Swagger to be available:**
   ```bash
   for i in {1..30}; do
     curl -sf http://localhost:{port}/api/{service}/swagger/v1.json > /dev/null && echo "Ready" && break
     echo "Waiting... ($i/30)"
     sleep 2
   done
   ```

5. **Run the generation script** from either app:
   ```bash
   cd apps/web && npm run generate:api:{service}
   ```
   Works from `apps/mobile` too — same result. The script `cd`s into `scripts/api-codegen/` itself,
   which is what makes ts-node resolve the right tsconfig (see the TS5011 note below).

   Worktree ports resolve automatically: the configs call `resolvePort()`
   (`scripts/api-codegen/resolvePort.ts`), which takes an explicit env var, else the repo-root `.env`
   that `allocate-ports.sh` writes, else **throws**. An unset port is a hard error rather than a
   silent regen against the shared main stack — so start the service you changed first
   (`worktree-service.sh up {service}`).

6. **Check for Enhanced file conflicts.** If `{service}ApiEnhanced.ts` exists, verify:
   - Manually added types still match generated ones
   - Cache tag invalidation references still-existing endpoints
   - Temporary manual types can be removed if codegen now generates them
   ```bash
   # Quick check for manual types that might conflict
   grep -n "injectEndpoints" apps/web/src/store/rtk-apis/{service}/{service}ApiEnhanced.ts
   ```

7. **Run frontend type check:**
   ```bash
   cd apps/web && npm run type-check
   ```

8. **Review the generated diff** for breaking changes:
   - Removed endpoints that frontend code still imports
   - Changed type shapes that break existing components
   - New enum values that need handling

9. **Stop the container** if no longer needed:
   ```bash
   docker compose stop {service}-api
   ```

## Multiple Services

If you changed multiple services, repeat steps 3-6 for each. You can start all needed containers at once:
```bash
docker compose up -d --build service-c-api service-a-api
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Swagger returns 404 | Service hasn't started yet — wait longer or check `docker compose logs {service}-api` |
| Codegen crashes | Deps live in `scripts/api-codegen/` — run `cd scripts/api-codegen && npm install` |
| "neither esbuild-runner nor ts-node are installed" | Misleading. Usually an un-deduped nested `typescript` under `ts-node` — check `npm ls typescript`. |
| TS5011 | You ran the generator with CWD outside `scripts/api-codegen/`. Use the `npm run generate:api:{service}` form. |
| Types don't match runtime | Backend may use JSONB with snake_case serializer — check `EntityFrameworkExtensions.JsonbSerializerOptions` |
| Enhanced file has stale overrides | Compare Enhanced types with generated types, remove duplicates |

## Config Files

Generation configs live in `scripts/api-codegen/openapi-config-{service}.ts` (all 13 were consolidated there by PROJ-3438 / PR #3299). Each defines:
- `schemaFile` — Swagger JSON URL (localhost)
- `apiFile` — Path to the BaseApi file
- `outputFile` — Path to the generated Api file
- `endpointOverrides` — POST-as-query overrides for search endpoints
- `hooks: true` — Generates React hooks
- `useEnumType: true` — Generates TypeScript enums (not string unions)
