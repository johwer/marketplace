---
name: stakeholder-questions
description: Write the questions a ticket needs answered by someone other than the user (the tech lead or the PO) in the format each reader answers fastest. Tech lead in English, one or two sentences each, yes/no. PO in Swedish, plain words, a concrete example and our proposal. Then record the answers back into the ticket spec, the draft PR and any running DTF session. Use when DTF work hits a decision that belongs to someone else, when ticket-refine, grill-me or an architecture report leaves questions for the PO or tech lead, when the user asks "vilka frågor har vi till PO / tech lead", "make these yes/no", "skriv frågor till …", or pastes answers back from them.
---

# Stakeholder questions: ask the person who decides, in the shape they answer

Questions that leave the session cost someone else's time. The tech lead has the context and wants
to answer "1 yes, 2 no". The PO does not read code and needs to know what a word means before
answering. One format for both readers gets slow answers from both.

## 1. Collect: only questions nobody here can answer

For every open point, decide who owns it:

| Owner | Typical questions |
|---|---|
| **Tech lead** | API shape and naming, permission/ServiceC model, shared enums and libraries, which service owns a cross-cutting bug, "is this an X change you want to avoid?" |
| **PO** | Who may see or do what, scope of the first version, wording and copy, what the user sees in an edge case |
| **The user** | Implementation choices inside the repo. Ask directly; this skill is not needed |

**Drop a question the code can answer.** Grep before asking. "Does DepartmentAdmin already have
SubscriptionRead?" is a lookup, not a question. Asking it wastes a round trip and makes the rest look
unprepared.

**Park, don't ask,** a question whose answer only matters after another decision lands. Mark it
`vilande till <X>` / `parked until <X>` and keep it in the list, so it isn't lost.

## 2. Format

### Tech lead: English

- Numbered, so the reply can be "1 yes, 2 no, 3 A".
- One or two sentences each. End with `Yes/no.` or `A or B?`.
- Name the code: path, enum, ticket key. Give no background, no pros/cons table, no "as we discussed".
- When we have a proposal, phrase the question as the proposal, so "yes" accepts it.

```
1. Path naming: should the new reads include "roleless"
   (company/{companyId}/rolelessSubscriptions/target/company|user) instead of plain subscriptions? Yes/no.
2. Shared enum: is adding RolelessSubscriptions to the shared ServiceContractType, and offering it
   on the Legacy catalog plans, fine under "no ServiceC changes"? It changes no ServiceC logic. Yes/no.
```

### PO: Swedish

- Numbered, answerable with ja/nej.
- Plain words. Write "avdelningsadmin", not `DepartmentAdmin`. No endpoints, no class names.
- When a word can be misread, add one concrete example. "Bevakning" needed one:
  *Anna bevakar Sales = Anna får aviseringar för alla i Sales.*
- Put `Förslag:` with our recommendation when we have one.
- For a first-version limitation, say what works now and what comes later, and why in one sentence.

```
1. Ta bort: får avdelningsadmin ta bort en avdelnings- eller företagsbevakning från en användare
   i sin avdelning, också en hen inte själv kan skapa? Ja/nej. Förslag: nej.
2. Personväljaren: ska väljaren bara visa personer som avdelningsadmin får lägga bevakningar på?
   I dag kan hen välja fler och får då ett fel vid sparning. Ja/nej. Förslag: ja.
```

### Translations

Only when the user asks. Translate both lists and keep code names unchanged.

## 3. Deliver

- **Show the questions in the chat for the user to paste.** Never post them to Jira, Slack or GitHub
  unless the user names the destination in this turn. A request to "lägga upp" or "make a table" is a
  request to see it.
- One message per audience. Split unrelated topics into separate messages, so answers in a thread
  don't mix (for example, path naming in one message, the service gate in another).
- If the user has already posted some of them, give only the missing ones, in the same style.

## 4. Record the answers (DTF)

When the user pastes answers back:

1. **Map each answer to its number.** If an answer could mean two things, ask the user one yes/no
   question back before writing it anywhere. For example, "bara dom som är på taggen": the recipient,
   the target, or both? An ambiguous answer written into a ticket becomes a spec.
2. **Answers that conflict with an earlier decision**, or with a tech-lead constraint (for example
   "no ServiceC changes"), go back to the user as one sentence: what clashes, and the options.
3. **Spec file** (`ticket-spec` skill): answered items go to `## Decisions` in
   `~/Downloads/<TICKET_ID>/spec.md`, written as `PO <date>: …` or `Tech lead <date>: …`. Unanswered
   ones stay in `## Open questions`, tagged `[PO]` or `[tech lead]`. Re-run
   `ticket-spec.sh hydrate <TICKET_ID> <WORKTREE>` when a worktree exists.
4. **Draft PR**: in `## Questions`, mark answered items `Decided: …`. A decision with real
   alternatives goes to `## Decisions` via `pr-decisions`.
5. **Jira descriptions** only when the user asks. Back up the ADF first, so it can be restored.
6. **A running DTF session that the answer affects** gets a SendMessage. Say what changed, which
   points are still open, and that it should report deviations rather than change scope on its own.

## Checklist

- [ ] Every question has an owner, and none is answerable by grep
- [ ] Tech lead: English, numbered, 1–2 sentences, ends in Yes/no or A/B
- [ ] PO: Swedish, numbered, ja/nej, plain words, an example where a term can be misread, `Förslag:`
- [ ] Parked questions are marked, not asked
- [ ] Shown in the chat, not posted
- [ ] Answers mapped by number. Ambiguous ones confirmed with the user before they are recorded
