---
name: hook-then-detail
description: Turn a long technical writeup into a short, human-sounding "hook" (1-2 sentences in Slack/chat voice) plus a polished follow-up comment with the full detail. Use when posting to Slack, Jira, GitHub PRs, or any thread where the FIRST message decides whether anyone reads the rest. Triggers on phrases like "shorten this", "make this human", "Slack version of this", "post this as a hook", "hook + comment", "shorten and humanize", "turn this into a thread".
autoTrigger:
  - when user wants to post a long technical message to Slack/Jira/PR and asks to "shorten", "humanize", "make it punchy", or "make a hook"
  - when user pastes a long writeup and asks for an attention-grabbing opener with the rest as a follow-up
  - when user says "hook and detail", "tease then detail", "Slack version", "first line then comment"
globs:
  - "**/*"
---

# Hook-Then-Detail — Lead With a Human Sentence, Park the Detail Below

## Purpose

People scroll. A long technical writeup posted cold gets ignored. The trick: lead with one or two sentences in conversational human voice that name the weird/interesting thing — then drop the full structured writeup as a follow-up message in the same thread.

This skill produces both pieces from a single input.

## Input

$ARGUMENTS

If `$ARGUMENTS` is empty, ask: "Paste the writeup you want shortened, and tell me where it's going (Slack / Jira / GitHub PR / other)."

## Output — exactly two blocks

```
=== HOOK (post first) ===
<1-2 sentences, conversational, first-person, lowercase OK, light grammar OK>

=== FOLLOW-UP (post as reply / next comment) ===
<the polished long-form writeup>
```

Nothing else. No preamble, no commentary, no "here you go".

## How to write the HOOK

Goal: the reader stops scrolling.

**Rules — follow strictly:**

1. **1-2 sentences. Hard ceiling.** If it's three, you failed.
2. **First-person, present tense.** "I have a weird scenario…" / "I'm seeing something off with…" / "I think we have a gap in…"
3. **Name the weird thing.** Not the topic, the *anomaly* — what makes a human curious or alarmed. "the role claim is missing", "the token works but is missing X", "tests pass locally but fail in CI only on Tuesday".
4. **Keep the author's voice.** If the source text is informal, keep it informal. If the user typed "doesnt" instead of "doesn't", don't fix it. Mild typos, missing commas, and lowercase are *features* — they signal a human typed this in real time, not a polished memo.
5. **Avoid corporate openers.** No "Following up on…", "I wanted to flag…", "Just sharing…". Start at the weird thing.
6. **No links, no ticket IDs, no acronyms in the hook** unless they're load-bearing for understanding the anomaly. Park context in the follow-up.
7. **No questions in the hook** unless the question IS the anomaly (rare). Statements pull harder than questions.

**Good hooks (template feel):**
- "i have a weird scenario, my access token when exchanging the partial token doesnt include the role"
- "spotted something off in the assumable token flow — legacy users come back with no role claim"
- "think we have a gap when nova hands off to signedin, the JWT is missing `role` entirely"

**Bad hooks (do not produce):**
- "I wanted to share some findings from NOVA-2830 regarding token exchange behavior." (corporate, vague, no anomaly)
- "Why does the assumable endpoint return tokens without a role claim?" (question, no setup)
- "Question for auth-service / ServiceC owner — possible gap in /Jwt/assumable/{userAccountId} token minting for legacy-product accounts." (this is the SUBJECT LINE, not a hook — too formal, too long, names the system before the symptom)

## How to write the FOLLOW-UP

The follow-up is the writeup the user already had — but cleaned up for the destination.

**Rules:**

1. **Keep the structure** if the source had clear sections (WHAT WE OBSERVED / WHY IT MATTERS / THE QUESTION / CONTEXT). Don't invent structure if the source is a wall of text — just tighten it.
2. **Reduce by ~20-40%** by removing throat-clearing, duplicated context, and any sentence the hook already covered.
3. **Promote the question / ask.** Make sure there is a clearly identifiable ASK ("Is this intentional?" / "Can we ship a fix?" / "Who owns this?") near the end.
4. **Preserve all concrete artifacts** verbatim: JWT payload dumps, error messages, file paths, PR/ticket links, TODO markers. These are evidence — never paraphrase them.
5. **Adapt formatting to destination** if the user said where it's going:
   - **Slack**: use `*bold*`, `_italic_`, triple backticks for code; no markdown headers (h2/h3 don't render). Keep paragraphs short.
   - **Jira (ACLI plain text)**: UPPERCASE headings, `----` underlines, `→` arrows, no wiki markup (it doesn't render via `acli`). Indent with spaces.
   - **GitHub PR/issue**: full GitHub-flavored markdown — `##` headings, fenced code blocks, `[text](url)` links.
   - **Unspecified**: default to GitHub-flavored markdown.

## Calibration check before output

Before you write the final blocks, ask yourself:

- Would I open Slack and read past this hook if it appeared in #general? If no — rewrite it.
- Is there a specific noun in the hook that names the anomaly? (e.g. "role claim", "JWT", "redirect loop") If no — rewrite it.
- Did I accidentally polish the user's voice into LinkedIn-speak? If yes — rewrite it.
- Is the follow-up still complete? (artifacts preserved, ask is clear) If no — restore them.

## Edge cases

- **The source is already short.** If the user pastes ≤3 sentences, the skill doesn't apply — say so and don't fabricate a hook.
- **The source has no clear anomaly** (e.g. status update, list of done items). Tell the user: "This isn't a hook scenario — there's no weird thing to lead with. Want a different framing?"
- **The user wants multiple hooks** ("give me 3 variations"). Output three numbered HOOK blocks, then ONE FOLLOW-UP.
- **Destination is unknown and the source has formatting.** Default to GitHub-flavored markdown and note the assumption in a single line above the HOOK block.

## Non-goals

- Do not generate the Jira ticket, Slack message ID, or PR comment yourself. Just produce the text — the user posts it.
- Do not add emojis unless the source had them or the user asks for them.
- Do not summarize or omit the technical detail in the follow-up. The follow-up is the source, lightly cleaned, not a TL;DR.
