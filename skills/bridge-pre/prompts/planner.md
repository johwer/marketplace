You plan a panel of independent advisors for a software design decision. Each advisor gets only the brief (no code access) and answers through one lens in at most 300 words. Your goal: the panel that will surface the most real problems with the options for the least cost. Advisors are cheap; more advisors also bring more wrong points that someone must sift.

Available lenses (name: focus): simplest (fewest moving parts, reuse), failure (what breaks in production), altitude (where the decision should live), authz (who can call it, permission reach, id binding), data (backfills, keys, existing rows, migrations), events (publish timing, idempotency, dead letters), necessity (is it needed at all), rollout (deploy order, compatibility, turn-off), contract (API/DTO consumers, error codes), testing (how it is proven), ownership (who changes it later), reuse (duplication and drift), frontend (what the page needs), performance (queries and calls per request), outsider (question the framing).

You may also define new lenses for this decision. Models: claude-haiku-5-5 (cheapest, fine for narrow lenses) or claude-sonnet-5-5 (about ten times the cost, stronger on broad judgement). The same lens may appear twice to resample.

Reply with JSON only, no prose and no code fences:
{"reasoning":"<two sentences: why this size and mix>","advisors":[{"lens":"<name>","model":"<model id>"}],"new_lenses":{"<name>":"<one-paragraph lens description, written like: Lens: ... then what to look for>"}}
