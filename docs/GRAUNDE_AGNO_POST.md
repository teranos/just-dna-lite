# Graunde: AgnoPost Event — Design Document

## Summary

Add a new hook event `AgnoPost` to Graunde that checks Agno agent output
against the same policy controls used by the existing `Stop` handler.
This lets the Python-side guardrails wrapper (`just_dna_pipelines.agents.guardrails`)
shell out to `graunde` and get a pass/fail decision for agent responses.

## Motivation

Claude Code's `Stop` hook already enforces "ego-death" controls — pattern
matching on `last_assistant_message` to catch undesirable agent behaviors
(premature sign-off, hallucinated claims, etc.).  Agno agents bypass Claude
Code entirely, so those controls don't fire.  `AgnoPost` reuses the same
matching logic for Agno output.

## Input Contract

The Python wrapper sends JSON on stdin:

```json
{
  "hook_event_name": "AgnoPost",
  "session_id": "run-abc123",
  "cwd": "/home/user/just-dna-lite",
  "last_assistant_message": "<full agent output text>"
}
```

Fields mirror the existing `Stop` payload so `parse.d` can handle both
without changes.

## Output Contract

| Exit code | Meaning | stdout | stderr |
|-----------|---------|--------|--------|
| 0 | Output passes | (ignored) | timing info |
| 2 | Violation detected | (ignored) | Corrective message for the agent |
| other | Graunde internal error | (ignored) | error detail |

This matches the existing Claude Code hook contract exactly.

## Implementation Plan

### 1. Add `AgnoPost` to `HookEvent` enum (`source/hooks.d`)

```d
enum HookEvent {
    // ... existing events ...
    AgnoPost,
}
```

### 2. Route in `main.d`

In the event dispatch switch, add:

```d
case HookEvent.AgnoPost:
    return handleAgnoPost(input);
```

### 3. Create handler (option A: reuse `stop.d`)

The simplest path — `AgnoPost` is logically identical to `Stop` minus the
deferred-message and trail-control machinery.  Extract the core pattern
matching from `handleStop()` into a shared function:

```d
// In stop.d:
auto matchStopControls(string text, Scope[] scopes) -> Nullable!string {
    // existing pattern matching logic from handleStop
    // returns the corrective message or null
}

// handleStop calls matchStopControls + trail/deferred logic
// handleAgnoPost calls matchStopControls only
```

### 4. Scope compatibility

Existing `.pbt` controls with `event: "Stop"` should also fire for
`AgnoPost`.  Two options:

- **Option A (recommended):** In the scope filter, treat `AgnoPost` as
  matching scopes that declare `event: "Stop"`.  No `.pbt` changes needed.
- **Option B:** Add explicit `event: "AgnoPost"` to controls that should
  also fire for Agno.  More precise but requires updating every `.pbt` file.

### 5. Attestation

Log `AgnoPost` firings to the SQLite attestation table with `session_id`
from the input payload.  The existing attestation system handles this
without changes — just pass `AgnoPost` as the event name.

### 6. No TTY changes

`AgnoPost` is never invoked interactively.  The existing TTY-detection
path (print version and exit) is unaffected.

## Scope of Change

| File | Change |
|------|--------|
| `source/hooks.d` | Add `AgnoPost` to `HookEvent` enum |
| `source/main.d` | Add dispatch case |
| `source/stop.d` | Extract `matchStopControls`, add `handleAgnoPost` |
| `controls/*.pbt` | None (scopes auto-match via Option A) |
| `source/sqlite.d` | None (attestation already generic) |

Estimated: ~30 lines of D code, no new dependencies, no binary size impact.

## Testing

1. Pipe a known-bad message to `graunde` with `"hook_event_name": "AgnoPost"`.
   Verify exit code 2 and corrective stderr.
2. Pipe a clean message.  Verify exit code 0.
3. Check attestation table has an `AgnoPost` row after a violation.
4. Verify existing `Stop` behavior is unchanged (regression).
