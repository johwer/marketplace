# Evolve — Review and Promote Learned Patterns

You are reviewing patterns detected from tool usage analysis. Your goal is to identify valuable patterns and promote them to the right destination.

## Steps

1. **Find the instinct file** for the current project:
   ```bash
   # Get project hash
   REMOTE=$(git remote get-url origin 2>/dev/null || echo "local")
   HASH=$(echo "$REMOTE" | shasum -a 256 | cut -c1-8)
   cat ~/.claude/instincts/$HASH/INSTINCTS.md 2>/dev/null || cat ~/.claude/instincts/global/INSTINCTS.md 2>/dev/null || echo "No instincts found. Run: bash ~/.claude/scripts/analyze-patterns.sh"
   ```

2. **If no instincts exist**, run the analysis first:
   ```bash
   bash ~/.claude/scripts/analyze-patterns.sh
   ```

3. **Review each pattern** and categorize:
   - **Promote to skill** — Pattern is reusable, create/update a skill file
   - **Promote to convention** — Pattern reflects a project rule, add to CLAUDE.md or conventions doc
   - **Promote to script** — Repeated bash command, wrap in a utility script
   - **Promote to memory** — Context gap that should be remembered, save as memory
   - **Dismiss** — Noise or one-off pattern, skip it

4. **Present findings to user** in this format:
   ```
   ## Pattern Review

   ### Promote
   - [pattern] → [destination] — [why]

   ### Dismiss
   - [pattern] — [why it's noise]
   ```

5. **After user confirms**, implement the promotions (edit files, create scripts, save memories).

6. **Clean up** — Archive the processed instinct file:
   ```bash
   mv INSTINCTS.md INSTINCTS.$(date +%Y%m%d).md
   ```

$ARGUMENTS
