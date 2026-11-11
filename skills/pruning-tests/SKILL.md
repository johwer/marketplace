---
name: pruning-tests
description: Applies the writing-tests value bar backwards: audits an existing test project or folder, proves which tests guard nothing (green when the code under test is broken, or redundant with a test in the same gate), deletes them in small per-area PRs, and removes what only those tests kept alive. Use for test tech-debt work, when a suite is noisy to refactor against, when agents keep copying mock choreography from old tests, or when asked to "rensa tester", "prune tests", "delete low-signal tests".
---

# Pruning tests

Runs inside the Repo monorepo. `/writing-tests` (`.claude/skills/writing-tests/` in the repo) stops low-value tests at the door. This skill removes the ones that got in before it existed. The bar is the same; the difference is that a deletion needs proof, because a test that looks trivial is sometimes the only thing guarding a line.

One area per run: one test project (`ServiceE.API.Test`) or one frontend folder (`apps/web/src/utils`). One area per PR.

The payoff is mostly maintenance, not CI minutes: a test with no Act or a matcher that accepts anything gets copied by the next agent that opens the file. Most of our suites run in seconds once built.

## 1. Inventory

- List every test in the area with what it calls and what it asserts, grouped by the unit under test.
- Find which other suites exercise the same production code **and run in the same gate**. Read the `paths:` filters in `.github/workflows/`: a test project that references the code but whose workflow doesn't trigger on its folder is not cover.
- `gh pr list` for open PRs touching the area. Skip files under someone's feature branch.

| Gate | Counts as cover? |
|---|---|
| PR checks whose `paths:` include the area | yes |
| PR checks that don't trigger on the area | no |
| Playwright web / mobile e2e, manual or scheduled | **no**, see below |

## 2. Triage by shape

Scan for these first; they are cheap to spot and almost always tautologies:

- **No Act.** The test never calls the unit it is named after, or calls the mock directly.
- **Logic copied into the test.** The rule under test is re-implemented in the test and asserted against itself.
- **A matcher that accepts anything on the asserted argument.** `It.IsAny<T>()`, `expect.anything()` where the argument is the point of the test.
- **`Verify` choreography** between our own services and repositories, with no outcome asserted.

Then classify the rest. Each test gets exactly one verdict:

- **DELETE: tautology.** Stays green when the line under test is broken.
- **DELETE: redundant.** Another test in the same gate goes red for every mutation this one catches.
- **MERGE.** A near-duplicate of a sibling over the *same* production code. Fold it into an `[InlineData]` / `[MemberData]` / `it.each` row.
- **KEEP.** It is the only test that fails on a mutation. This wins over any shape rule: a "mapper copies a field" test that is the only one to catch a dropped assignment stays.
- **KEEP, E2E CANDIDATE.** Guards a user flow a Playwright test would guard better. Keep it and list it.

## 3. Prove each DELETE and MERGE

Reading the test is not proof.

1. Mutate the production line the test's **name** claims to guard (flip the condition, return the default, drop the call). For a redundancy claim, use at least two mutations, one of them aimed at that claim.
2. The mutation must compile. If the build fails, adjust it (a `!` under nullable-as-errors) or drop it; a build error proves nothing.
3. Run the **whole** area project plus the same-gate suites from step 1, not a `--filter`. One mutation can break tests in several classes, and the cost is the build, not the run. Script it: mutate, build once, run, record red tests, revert.
4. Revert. Before committing, `git diff --stat` must show no production files.
5. Before reading "stayed green" as a tautology, prove the mutation took effect (a throw or log in the mutated branch). An inert mutation looks exactly like a test that guards nothing; jsdom's `Storage`, for one, does not enumerate via `Object.keys`. And the verdict is about **this** test going red, not something going red.

| Result | Verdict |
|---|---|
| Only this test went red | KEEP |
| This test stayed green | DELETE: tautology |
| This test and another went red, on every mutation | DELETE: redundant, naming the other |
| Nothing went red | **Untested code**, not dead code: log it as a coverage gap |
| The mutation cannot fail by construction (a guard on an empty collection that is never empty in the test) | Unproven: leave the test |

**Which of a redundant pair to delete:** keep the one whose name says what it guards and that hits the line directly. Delete the one that covers it by accident (through a shared catch block or a broad setup).

**Near-identical tests over copied production code are not redundant.** Two endpoints with copied filter logic need a test each. The copy is the finding: log it as a refactor follow-up, don't merge the tests.

## 4. Remove what the tests kept alive

After the deletions, delete in the same PR what only they used: `internal` members and `InternalsVisibleTo` that existed for the tests, exports with no remaining importer, `resetXForTests` hooks, setup builders, fixtures and mocks with no caller. Grep the whole repo for each first; a helper in `Repo.Shared.IntegrationTesting` may be used by another service.

## E2E is not cover until it gates

Web and mobile e2e is going to grow, probably on a self-hosted Mac mini rather than in the PR checks. A test it runs counts as cover only once it blocks merging to `main`, which deploys. Until then:

- Never delete a unit or integration test because "e2e covers it".
- List KEEP, E2E CANDIDATE tests in the PR body, so the list is ready the day e2e gates.

## Out of scope

- Rewriting weak but load-bearing tests, writing tests for coverage gaps, deduplicating copied production code. Each becomes a follow-up subtask listed in the PR body, not part of the pruning PR.
- Production refactors beyond step 4.

## In the PR

- Title `PROJ-<n>: Prune low-signal tests in <area>`.
- Counts: tests before, deleted, merged, kept; lines removed; suite duration before and after, with the command.
- The verdict table: test, verdict, mutations tried, which tests went red (or "none").
- Coverage gaps and copied-code findings, each as a follow-up.
- The KEEP, E2E CANDIDATE list.
- Run `/reviewing-changes` before marking it ready. The reviewer's job is to challenge a DELETE, so give them the mutation table, not a summary.
