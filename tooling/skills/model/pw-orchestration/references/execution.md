# pw-orchestration — execution, repair, and checkpoints

Load this only when the operation schedules, spawns, repairs, or verifies worker tasks. The
routing ladder itself lives in
`pw-guide-workflow/references/execution-and-routing.md`; this reference does not restate it.

## Routing

The shared skill ladder owns provider availability, same-provider versus headless selection,
model/tuning binding, and supervision. This reference never restates or reinterprets it.

## Pre-flight

Run the entry point's deterministic pre-flight and relay a non-zero result verbatim. Never reason
around a failed gate. Re-check the PLAN gate on every invocation, including a resume.

## Scope

- Named task IDs: exactly those tasks, then stop.
- `--wave`: only the immediately runnable wave, then stop and report what became ready.
- No selector: resume every task not yet accepted, walking the DAG to the end of that scope.

## Spawning

Spawn one executor per task once its dependencies are `done`/`accepted`. Parallelize independent
tasks within the plan's limit. Route every spawn through the shared ladder: availability gate,
same-provider in-process worker, or supervised headless session. Bind only the approved task
model; record the actual or degraded identity.

Log every spawn and write the same session id to the task's `## Result → Session:`. Resume only
after the session check reports live.

## Checkpoints

After a task starts or returns, and after a repair changes a task file, synchronize the PLAN rows,
then the dashboard. Stop on sync failure. Re-read the synchronized PLAN before scheduling
dependents. Synchronization never auto-accepts a task.

## Repair

Drain all open items on one artifact as one fix pass. Preserve per-item replies. Route task
artifact repairs through the ladder; docs are driver-inline. Respect the shared repair budget.
A dependency's late fix fans at most one capped re-verify/de-impact pass.

## Completion

Stop at committed + verified unless the operation explicitly continues into ship. Do not push,
open MRs, or mark accepted without the human's separate authorization. Report which tasks reached
`done`, which failed verification, which were blocked, and what is newly ready.
