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

## Writing Posts, Prose, and Replies

These rules apply to every post, article, document, and reply in this project.

- **Use Simplified Technical English.** Write in ASD-STE100 Simplified Technical English (or in the style of Simple English Wikipedia when STE100 has no suitable word). Use clear, direct prose in the active voice. Keep sentences short and replies tight. Cut filler words.
- **Explain all relevant context.** Give the reader the background they need. Do not assume they know the project, its history, or its abbreviations.
- **Use a cold-read critic first.** Before you send any reply, or publish any post or document, give the draft to a reader who has no prior context (for example, a fresh subagent), and fix every point that the critic cannot understand.
