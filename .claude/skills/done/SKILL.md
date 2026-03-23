---
name: done
description: Wrap up a coding session — run tests, smoke test, update CLAUDE.md, then commit. Use when the user says "done", "wrap up", or "finish".
argument-hint: "[optional commit message]"
---

Wrap up the current coding session.

## Timing & Stats

At the start of EACH phase, run `date +%s` to capture a timestamp. At the end of each phase, capture another timestamp and compute the elapsed time.

After all phases complete, output a summary table like this:

```
/done summary
───────────────────────────────────────
Phase                   Time     Count
───────────────────────────────────────
Build                   3s       0 errors, 0 warnings
Unit tests              2s       51 passed, 0 failed
Smoke test              5s       7 passed, 0 failed
Architecture docs       4s       1 updated, 1 created
Update CLAUDE.md        2s       1 section updated
Commit                  2s       1 commit, 5 files staged
Report                  1s       session complete
───────────────────────────────────────
Total                   17s
```

Adjust the "Count" column to reflect what actually happened in each phase. Be specific with numbers.

## Determining Session Files

Multiple Claude Code sessions may run concurrently on the same branch, so git history (e.g., `HEAD~3`) is NOT a reliable way to determine which files this session changed.

**Use your own memory of the conversation.** You know every file you read, edited, created, or wrote during this session. Compile that list directly — it's the only reliable source.

## Productivity Summary

After the phase summary, generate a session productivity report.

Use your session file list to get modification timestamps:
```
stat -f "%m %N" <file1> <file2> ... 2>/dev/null | sort -n
```

Output:

```
Session productivity
───────────────────────────────────────
Session duration:     1h 23m (first change 2:15pm → last change 3:38pm)
User prompts:         8
Files modified:       14
Files created:        3
Lines changed:        +187 / -42
Areas touched:        SpaceBridge, HotkeyListener
───────────────────────────────────────
```

## Steps

### Phase 1: Build

1. Run `swift build` — ensure the project compiles with zero errors.
   - If the build fails, fix the errors before proceeding.

### Phase 2: Unit Tests

2. Run `swift test` — ensure all unit tests pass.
   - If tests fail, investigate and fix the failures before proceeding.
   - Do NOT skip or delete failing tests to make them pass.
   - Report total passed/failed count.

### Phase 3: Smoke Test

3. Run `swift Scripts/smoke_test_switching.swift` — verify actual space switching works.
   - This requires Accessibility permission and switches spaces briefly.
   - If it fails, the space switching code is broken — investigate before committing.
   - Report passed/failed count.

### Phase 4: Update Architecture Docs

4. **Identify affected areas** — based on files changed this session, determine which feature areas were modified.

5. **Check existing docs** — run `ls docs/architecture/` to see what exists:
   - If a doc exists for the affected area, read it and update it to reflect the current state
   - If no doc exists and the session touched non-trivial logic in that area, create one

6. **Write/update docs** — each architecture doc in `docs/architecture/` should include:
   - **Overview**: What this feature/area does
   - **Key files**: File paths and their roles
   - **Data flow**: How data moves through the system
   - **Important patterns**: Conventions, gotchas, or design decisions
   - Focus on the CURRENT state, not history of changes
   - Skip this phase if only trivial changes were made (typos, formatting)

### Phase 5: Update CLAUDE.md

7. **Check if CLAUDE.md needs updating** — based on the session's changes:
   - If architecture changed (new files, new patterns, new APIs), update the relevant sections
   - If build commands changed, update the build section
   - If key decisions changed, update those
   - If nothing material changed, skip this phase

### Phase 6: Commit

8. Stage all relevant changed files and commit.
   - If $ARGUMENTS is provided, use it as the first line of the commit message
   - Otherwise, draft a summary of the session's changes as the first line
   - Append the session productivity summary to the commit body
   - Use a HEREDOC for the commit message, formatted like:
     ```
     feat: summary of changes

     Session summary:
     - Duration: 1h 23m
     - User prompts: 8
     - Files modified: 5, created: 2
     - Lines: +187 / -42
     - Tests: 51 unit passed, 7 smoke passed
     - Areas: SpaceBridge, HotkeyListener

     Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
     ```

9. Run `git status` to confirm everything is clean.

### Phase 7: Report

10. Output the `/done summary` table and `Session productivity` block (see above).

11. **Goodbye message** — end with a short celebratory message about what was accomplished.

## Rules

- Focus on documenting the CURRENT state, not the history of changes
- Only commit files changed in this session
- NEVER use `--no-verify`, `--amend`, or force push
- NEVER commit `.env`, secrets, or credential files
- Do NOT push unless the user explicitly asks
