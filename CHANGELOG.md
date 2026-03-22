# Marketplace Updates

What's new in the plugin marketplace. For the full DTF changelog, see [dream-team-flow/CHANGELOG.md](https://github.com/johwer/dream-team-flow/blob/main/CHANGELOG.md).

## 2026-03-22

### New Skills
- `anthropic-pdf`, `anthropic-docx`, `anthropic-pptx`, `anthropic-xlsx` — Official Anthropic document skills
- `anthropic-brand-guidelines`, `anthropic-skill-creator` — Official Anthropic utility skills
- `marketing-content-strategy`, `marketing-copywriting`, `marketing-email-sequence`, `marketing-seo-audit`, `marketing-ai-seo`, `marketing-social-content`, `marketing-sales-enablement`, `marketing-competitor-alternatives`, `marketing-copy-editing`, `marketing-lead-magnets`, `marketing-launch-strategy`, `marketing-marketing-ideas` — 12 marketing skills
- `claude-seo` — SEO audit with 12 sub-skills
- `context-optimization` — Token cost reduction patterns

### Updated Skills
- `code-insights` — React 19 aware (no useMemo/useCallback nudges)
- `infra-conventions` — WAF, monitoring, ECR, RDS patterns expanded

### Updated Scripts
- `config-scan.sh` — Scans skills for injection patterns, allowlist for known-safe skills, deny-rule guidance

## 2026-03-21

### New Agents (16)
- `engineering/`: api-designer, performance-analyst, migration-planner
- `data/`: data-analyst, pipeline-builder, insights-reporter
- `design/`: ui-designer, ux-researcher
- `infrastructure/`: ci-cd-engineer, security-auditor
- `marketing/`: marketing-ops, sales-enablement, content-creator, social-strategist
- `operations/`: customer-ops, support-responder
- `product/`: po-analyst, requirements-analyst, sprint-prioritizer
- `testing/`: qa-tester, uat-tester, api-tester, performance-benchmarker

### New Skills
- `frontend-performance`, `backend-performance`, `aws-performance`
- `code-insights`, `memory-hygiene`
- `po-workflows`, `testing-workflows`, `uat-workflows`, `data-analysis-workflows`, `presentation-workflows`, `content-workflows`, `infra-conventions`
- Trail of Bits security: differential-review, insecure-defaults, static-analysis, supply-chain
- Levnikolaevich auditors: codebase, security, code-quality, concurrency, api-contract, persistence-performance, query-efficiency, runtime-performance
- `code-review-skill` — React 19, TypeScript, perf, security guides

### New Commands
- `/infra-ticket` — Terraform workflow from Jira to PR

### New Scripts
- `terraform-plan-summary.sh`, `verify-infra-workflows.sh`, `memory-health.sh`

### Changed
- Agents reorganized into 8 domain subdirectories
- `dtf.sh` — role selection, custom workflow steps, `dtf configure`, `dtf steps`
- `sync-config.sh` — auto-updates DTF README stats, copies docs across repos
