---
name: pr-decisions
description: Write the "Decisions" section of a PR description — the non-obvious choices made while implementing, each with the alternatives considered and the trade-off, so a reviewer can challenge the reasoning instead of only the code. Use when a PR involved a judgement call, when the implementation diverged from what the ticket proposed, when a domain-model or architecture gate was resolved, or when asked for the pros and cons of an approach. Pairs with pr-description, which owns the purpose and outcome.
---

# PR Decisions — the choices, and what they cost

Produces a **`## Decisions`** section for a PR description. It sits below `## What changes` and above the code walkthrough.

Audience: a reviewer who can accept the code but wants to challenge the *reasoning*, and the person who reads `git blame` in a year and asks "why on earth is it like this?"

## When to include it

Include a decision when **a competent colleague could reasonably have done it differently.** That is the whole test.

Include when:
- The implementation **diverged from what the ticket proposed** — always. This is the highest-value case and the one most often left out.
- A domain-model or architecture gate was resolved. Record what was chosen and what was rejected.
- You picked one of several viable mechanisms (new action vs reuse an existing one; migration vs backfill; analyzer vs written rule).
- You deliberately did **not** do something the reader would expect (no test, no migration, no abstraction).
- You accepted a known cost — duplication, a large mechanical diff, a temporary workaround.

**Do not** include:
- Choices with one sensible answer. "Used the existing Button component" is not a decision.
- Style and naming, unless the codebase genuinely disagrees with itself.
- Restatements of a rule you followed. Following the convention is the default, not a decision.

If the section would have more than **three or four** entries, most of them are not decisions. Cut to the ones a reviewer could actually push back on.

## Shape

```markdown
## Decisions

### <The choice, stated as what was done>

**Chose:** <the option taken, one line>
**Over:** <the realistic alternative(s) — the ones actually considered, not strawmen>

**Why:** <the trade-off in one or two sentences. What this buys, and what it costs.>

**Cost accepted:** <the downside you are knowingly taking on. Omit only if there genuinely is none,
which is rare — if you cannot name a cost, you probably have not found the real trade-off.>

**Revisit if:** <the condition that would make this the wrong call. Optional, but this is what makes
the decision reversible rather than permanent by accident.>
```

## The alternatives must be real

The failure mode that makes these sections worthless is the strawman: listing an alternative nobody would pick, so the chosen option wins by default. A reviewer spots this instantly and stops reading the section.

An alternative is real if **someone could have shipped it**. If the honest answer is "there was no serious alternative", then it was not a decision — drop it.

Equally: if the alternative was genuinely close, say so. "Both were defensible; we picked X because Y" is more trustworthy than manufactured certainty, and it tells the reviewer their pushback is welcome.

## Rules

- **State the cost.** A decision with only upsides is a decision you have not finished thinking about. Naming the cost is what makes the section credible.
- **Diverging from the ticket is always a decision.** The ticket said one thing, you did another. Say so, in the PR, before a reviewer finds it. This is not an admission — it is the most useful thing in the section.
- **Facts, not persuasion.** You are recording a choice for scrutiny, not selling it. If the reasoning only works when phrased favourably, it is not reasoning.
- **Present tense, plain language.** Same readability bar as `pr-description`: short sentences, active voice, no unexpanded acronyms.
- **One decision per heading.** Two entangled choices under one heading cannot be challenged separately.
- **Link, do not relitigate.** If it was settled in a ticket comment or a domain-model gate, link there and summarise in two lines.
- **Never invent a rationale after the fact.** If the real reason was "this was simplest and it works", write that. Retrofitted architectural justification is worse than honesty.

## Worked example

From NOVA-3172, where the shipped approach differed from the ticket's proposal.

```markdown
## Decisions

### Gated the page on existing write actions instead of a new dedicated action

**Chose:** Reuse the existing Create/Update actions the page already implies —
`HcmTemplateCreate`, `ServiceATemplateConfigurationCreate`, `ProductContractsUpdate` and siblings.
**Over:** Minting a new `ProductContractsConfigure` action, which is what the ticket specified.

**Why:** A new action needs an enum member, wiring in two permission-mapping files, and a grant
decision for every affected role. Reusing write actions gets the same outcome — administration
surfaces are revealed by the ability to administer them — with no new surface to maintain.

**Cost accepted:** The page is now gated by five actions rather than one, so "who can see this
page" is a slightly longer answer. We judged that cheaper than a new action nobody else uses.

**Revisit if:** a role needs to administer products *without* any other write access on the page.
That case cannot be expressed today and would need the dedicated action after all.
```

Note what makes it work: the alternative was the ticket's own proposal, the cost is stated plainly,
and `Revisit if` names the exact scenario that would invalidate the choice. A reviewer can disagree
with the trade-off without having to reverse-engineer it from the diff.

## Placement in the PR

```
## Why                 <- pr-description
## What changes        <- pr-description
## Decisions           <- this skill, only when there were real decisions
## How to see it       <- pr-description
## Not in this PR      <- pr-description
## Walkthrough         <- code-walkthrough
```

Omit the section entirely when there were no real decisions. An empty or padded `## Decisions`
teaches readers to skip it, which costs you the one time it matters.

## Related

- `pr-description` — purpose and outcome. Owns the surrounding sections and the readability bar.
- `grill-me` / `grill-with-docs` — where decisions get *made*. This skill only records them.
- `mermaid-diagram` — when a domain-model decision needs options drawn rather than described.
- `code-walkthrough` — the file-by-file section, below this.
