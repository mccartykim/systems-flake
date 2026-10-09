# Agent Instructions

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `jj git push` succeeds.

**MANDATORY WORKFLOW:**

1. **Note remaining work** - anything unfinished goes in the commit message or the hand-off below
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **PUSH TO REMOTE** - This is MANDATORY:
   This repo uses Jujutsu (jj), not plain git — plain `git push` will not push the working-copy commit.
   ```bash
   jj describe -m "message"
   jj bookmark set main -r @
   jj git push
   ```
4. **Clean up** - Clear stashes, prune remote branches
5. **Verify** - All changes committed AND pushed
6. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `jj git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
