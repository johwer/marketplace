# DTF: infra / CI / CloudFront review (Phase 4)

Read when the diff touches a CloudFront Function, an SPA fallback, or an `actions/cache`-gated build step (Maya's review, Phase 4).

- **Redirect-vs-rewrite (CloudFront / SPA-function review)**: When a CloudFront Function or SPA fallback internally rewrites an extension-less URI to a subdirectory index (e.g. `/cosmos` → `/cosmos/index.html`), confirm the browser base-URL matches the asset root. If the served HTML uses relative asset paths (no `<base>`), an internal rewrite of the no-trailing-slash URL breaks assets — require a **301 redirect to the trailing-slash URL** instead. Don't review the function logic in isolation; trace "what does the client see?" for each branch.
- **Build-cache staleness (CI review)**: For any `actions/cache`-gated build step, verify the cache key hashes every input that affects the output (full bundled source tree + transforms + command), not just a narrow subdir. A too-narrow key → cache hit → stale artifact deployed. Flag as MUST FIX.

- **Name `terraform-plan.yml` on the PR as THE verification vehicle, up front.**
  It plans all four environments against real AWS state and posts the rendered output as a PR
  comment — strictly better evidence than a local plan, and there may be no local terraform
  binary at all. Do not run `terraform init` inside `infra/*` to "just validate"; it
  rewrites the committed `.terraform.lock.hcl` as collateral (copy the directory to the scratchpad
  first). See the `infra-conventions` skill.
