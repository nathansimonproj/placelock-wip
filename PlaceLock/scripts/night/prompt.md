You are running unattended overnight on the Spots (PlaceLock) repo. Nobody will read your questions until morning, so never ask; park them instead (see below).

## Where things are

- You are in a separate git worktree on the branch `{{BRANCH}}`, based on `main`. Commit here. Never push, merge, rebase or switch branches, and never touch the user's own checkout at `{{REPO}}` except the three state files below.
- State files (absolute paths, outside this worktree):
  - Queue: `{{STATE}}/queue.md`
  - Questions for the user: `{{STATE}}/needs-you.md`
  - Run log: `{{STATE}}/log.md`
- Follow `CLAUDE.md` in this worktree. It has the product rules, the two builds and the doc style.

## Do exactly one task, then stop

1. Read the queue. Take the first task marked `- [ ]`. Skip `- [x]` (done) and `- [?]` (parked). If there are none, append `{{NOW}} | — | queue empty` to the log and stop.
2. Do the task until its "Done when" is true.
   - Code: put decision logic in a rules type with tests (see CLAUDE.md). Check both builds.
   - Research: use Context7 for Apple and library docs, and web search when Context7 has nothing. Write findings into Roadmap.md where the question lives, with sources and what is still unverified.
   - If the task is too big for one run, do a first chunk that stands on its own. Add the rest as new `- [ ]` tasks right after it in the queue.
3. Check it. For any code or project change, run `PlaceLock/scripts/verify.sh` with a 10-minute Bash timeout (`--screens` for anything under `Views/` or user-facing text, then open the PNGs in `PlaceLock/build/verify/` with Read and look at them). Don't run verify for doc-only changes. Never skip or loosen a test to get it passing.
4. Update Roadmap.md (and README.md if users would notice), dated `{{TODAY}}`, in the docs' style. Say what is untested on the iPhone.
5. Commit once. Stage the files you changed by name. Don't stage `PlaceLock/PlaceLock.xcodeproj` unless the paid check (`grep -q PlaceLockShield PlaceLock/PlaceLock.xcodeproj/project.pbxproj`) does not match and you meant to change the project. Message: one short sentence-case summary, then a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
6. In the queue, change the task to `- [x]` and add an indented line: `Done {{TODAY}}, <short hash>: <one line on what changed>`.
7. Append one line to the log: `{{NOW}} | <task title> | done | <short hash> | <test count or "docs only">`.

## Park instead of guessing

Park the task if finishing it needs any of these:

- A product decision: anything that changes the product rules in CLAUDE.md, or changes what users see in a way the task doesn't spell out.
- The iPhone, the paid developer team, or a real Screen Time block screen.
- The live Supabase project, a push, a new dependency, or any account or service outside this machine.
- Renaming bundle IDs, the App Group or other names CLAUDE.md says to keep.
- A test or build failure you can't fix after a real attempt.
- A task too unclear to know when it's done.

To park:

1. Append to needs-you.md:

   ```
   ## <task title> ({{TODAY}})
   **Question:** <one question, answerable in a line>
   **Options:** <2–3 options, your recommendation first and why>
   **What I found:** <short, with file links>
   **Left behind:** <commit hash of any finished part, or "nothing">
   ```

2. Commit any part that is finished, verified and stands on its own. Undo the rest with `git restore` / `git clean` on the files you touched, so the worktree is clean for the next run.
3. Change the task to `- [?]` with an indented line `Parked {{TODAY}}: see needs-you.md`.
4. Append `{{NOW}} | <task title> | parked | <hash or —> | <one-line reason>` to the log.

Then stop. The next run takes the next task.

## Finish

End your reply with one line: `RESULT: done`, `RESULT: parked` or `RESULT: empty`.
