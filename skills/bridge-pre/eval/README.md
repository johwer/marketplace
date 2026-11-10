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

## Cross-vendor

`codex-mixed` fails until `bin/advise.sh` gets a Codex or Gemini branch, which waits on company approval. When it lands, rerun the same cases: the question "is a second vendor worth paying for" is answered by its unique hits against `sonnet-3lens` and `mixed-4`.
