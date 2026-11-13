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
- **Before calling a "backend added fields" ticket blocked:** regenerate and read the diff first; the generated file is often just stale. Check every DTO in the feature area (the field may sit on a sibling response type) and `git log -S <field> origin/main` for a merged sibling ticket. Escalate only if the field is absent from live swagger, origin/main and open PRs.

## Service Map

The services that can be generated are the `generate:api:*` scripts in `apps/web/package.json`; the docker service is in `docker-compose.yml`. Each `scripts/api-codegen/openapi-config-{service}.ts` holds the Swagger URL and reads its port with `resolvePort("<SERVICE>_API_PORT")` (env var, else the repo-root `.env`), so read the port there, not a fixed number, before polling Swagger in step 4.

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
   PORT=<the <SERVICE>_API_PORT value from the env or repo-root .env>
   for i in {1..30}; do
     curl -sf http://localhost:${PORT}/api/{service}/swagger/v1.json > /dev/null && echo "Ready" && break
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
   - A diff much larger than your change is usually drift: main's committed client can lag main's
     backend. Compare exported member sets, not lines, and confirm your new symbols appear. Commit
     the codegen unedited and say so in the PR.

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

Generation configs live in `scripts/api-codegen/openapi-config-{service}.ts`. Each defines:
- `schemaFile` — Swagger JSON URL (localhost)
- `apiFile` — Path to the BaseApi file
- `outputFile` — Path to the generated Api file
- `endpointOverrides` — POST-as-query overrides for search endpoints
- `hooks: true` — Generates React hooks
- `useEnumType: true` — Generates TypeScript enums (not string unions)
