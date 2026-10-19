# Working on My AI Planet

A Godot 4.7 project in `src/`, tested headless. See [README.md](README.md) for the game and the tools.

## Testing: pick the smallest run that answers the question

| When | Run | Time on a quiet machine |
|---|---|---|
| While changing code | `scripts/test.sh <filter>` (matches `file::method`, e.g. `animals` or `test_save_and_load`) | seconds |
| Before each commit | `scripts/test.sh --quick` (skips the tests each file lists in `SLOW`) | about 30 s |
| Once, before merging or opening a PR | `scripts/test.sh` | about 2 min |

- `scripts/test.sh` runs one Godot process per test file, in parallel, and prints only failures, script errors and a summary line. Add `-v` to see every test with its time.
- The full run takes longer than the Bash tool's default 2-minute timeout. Pass `timeout: 600000`, or use `run_in_background` and wait for the notification. Never poll with `sleep`.
- Don't rerun the full suite after a fix that one filtered run already proves. CI runs everything on every PR anyway.
- A new test that takes over 15 seconds goes in its file's `const SLOW := [...]`. Better still, simulate fewer years.
- A test that writes to `user://` uses `scratch_path("name.json")`. The path is unique to the process, so runs in other checkouts can't overwrite it.

## Sharing the machine with other agents

- Don't take a global lock (`/tmp/myaiplanet-godot.lock`) around tests or reports. Each worktree has its own `src/.godot` import cache, and tests don't share files. Only take the lock for GUI work that needs the foreground window (cua-driver clicks).
- The Mac has 8 cores, shared with every other agent. Run at most 4 Godot simulations at once (`jobs=4` for `society_report.sh`, `JOBS=4 scripts/test.sh` when other agents are busy). Twelve parallel 100-year runs slow down everyone, you included.
- Give subagents that run Godot their own worktree (`isolation: "worktree"`). The first import takes a few seconds.
- Before long report runs (`balance_report`, `life_report`, `society_report`, `herd_lab`), try a short one first (`years=20 seeds=2`). Scale up only for the final number.
