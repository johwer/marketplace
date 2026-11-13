# Bridge eval

Answers one question with numbers instead of opinions: which advisor setup surfaces the most of what later mattered, per dollar?

## Cases

Cases live outside the skill, in `~/.claude/bridge-eval/cases/<id>/` (or `$BRIDGE_EVAL_DIR`), so ticket detail never reaches the synced or public skill repo.

Each case is two files:

- `brief.md`: the brief as it would have looked **before** implementation (`prompts/brief-template.md`). Rebuild it from the ticket and the code at the parent commit. Leave out anything learned later, or the case leaks its answer.
- `expected.md`: one line per issue that tech-lead review, PR comments or production later raised, written as the concern, not the fix. `- Permission check only in the frontend; the API is callable directly.`

Good sources: PRs where `ghost-review`/`owl-review` standing decisions were born, PRs with long review threads, tickets reopened after release. Ten cases is enough to start; noise between runs is real, so compare variants on the same run and rerun a close call.

No PII, secrets or customer data in either file.

**Don't leak the answer.** When a case comes from a standing decision in `ghost-review`/`owl-review`, the brief must not quote that decision. The `altitude` lens is partly distilled from the same decisions, so a leaked decision flatters it. Quote only decisions that predate the case.

## Live cases

Every ticket that ran bridge leaves `~/.claude/bridge-eval/live/<TICKET>/` at cleanup: the brief, each advisor's answer and the log. These beat replayed cases, because the brief was provably written before implementation and cannot leak the answer. A `PENDING` file marks one with no `expected.md` yet. After merge, write `expected.md` from the PR's review threads and any ghost/owl finding (the concern, not the fix), delete `PENDING`, and move the folder into `cases/`. `ls ~/.claude/bridge-eval/live/*/PENDING` lists what is waiting.

## Run

```bash
bash ~/.claude/skills/bridge-pre/eval/run.sh sonnet-3lens opus-3lens mixed-4 fable-1
```

Each variant runs `BRIDGE_REPEATS` times (default 2). Prints, per variant: mean hits, advisor cost, hits per dollar, noise, the difference from `BRIDGE_BASELINE` (default `sonnet-3lens`), the spread between repeats, and which advisors found things nobody else did. A lens or model with no unique hits across the set is not earning its tokens. A difference smaller than the spread is run-to-run variation, not a result.

**Read every miss before blaming the model.** A miss can be a bad case: an expected finding nobody could see from the brief, a brief missing the excerpt that showed it, or a grader that matched the wrong text. Classify each miss as model, case or grader, fix the case or grader ones, and rerun only the affected case.

Variant lines are `<lens> <model> [effort]`; effort defaults to medium. Effort is a lever worth measuring: Anthropic reports Fable 5.2 at high effort roughly matching Opus 5.5 at max for about half the cost per task. Each advisor stops at `BRIDGE_MAX_USD_PER_ADVISOR` (default 0.50).

Results stay in `~/.claude/bridge-eval/results/<timestamp>/`. Write the winner into `SKILL.md` Step 2 as the default variant, with the run date.

## Results behind the SKILL.md defaults

Bigger or smarter swarms did not pay either (same eval): `haiku-14` 29.0 with noise 99.5, `haiku-14dup` 28.5 with noise 108, and `fable-planner` (Fable picks 5–8 advisors per decision, about two on Sonnet, sometimes inventing a lens) 28.5 for $1.63. Adding the team's convention docs as they stood at the time to the brief gave 27.0 (no gain).

**Triage with a critic (Step 4, $0.17 per decision).** `eval/critic-run.sh` runs a critic with no code access (default Sonnet. On pre: Sonnet 73 % of findings / 54 % of noise on the shortlist for $0.08 per decision, Opus 70 % / 53 % for $0.17, Fable 77 % / 38 % for $0.38. On post (`post-haiku-7`): Sonnet 83 % / 24 % for $0.16, Opus 79 % / 30 % for $0.36. Pass `claude-fable-5-2` as the critic model for M+ when less noise is worth $0.30) that merges duplicates and splits the points into a shortlist of at most 8 and a "weak" list. On `haiku-7lens` its shortlist held 39 of 56 findings (70 %) and 62 of 117 noise points (53 %). Show the shortlist first and the weak list collapsed, never dropped: 30 % of the real findings land under weak.

Stronger models did not pay: `sonnet-7lens` 27.5, `opus-3lens` 25.5, `fable-1-high` 17. More lenses mean more noise (Haiku 58 vs Sonnet 43 wrong or irrelevant points over 24 runs), so Step 4's check against the repo matters. An automated Opus verifier with repo access was tried (`bin/verify.sh`, `eval/verify-run.sh`): at $2 per decision it dropped true findings (19 → 16 of 22) and hit its budget on 3 of 12 cases, so it is not part of the flow. A stated team lean barely moved Sonnet advisors; keep the brief blind anyway. Rerun the eval before changing these. This follows Anthropic's routing (Opus by default, Fable for the hardest, Sonnet or Haiku for the simpler): advisors answer a narrow lens question from a short brief, which is Haiku or Sonnet work; the critic and the synthesis run on the stronger model. Variant lines may add an effort level; each advisor is capped at `BRIDGE_MAX_USD_PER_ADVISOR` (default 0.50). It prints each advisor's cost and the total. Answers land in `.dream-team/bridge/advisors/<lens>@<model>@<effort>.md` (scratchpad outside a worktree).

## Cross-vendor

`codex-mixed` fails until `bin/advise.sh` gets a Codex or Gemini branch, which waits on company approval. When it lands, rerun the same cases: the question "is a second vendor worth paying for" is answered by its unique hits against `sonnet-3lens` and `mixed-4`.
