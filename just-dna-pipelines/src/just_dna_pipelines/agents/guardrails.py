"""
Post-run guardrails for Agno agents via Graunde.

Shells out to the ``graunde`` binary (if available on PATH) to enforce
policy controls on agent output text.  When a violation is detected,
returns a corrective message that the caller can feed back to the agent
for a retry.

The binary is invoked with a JSON payload on stdin that mirrors Claude
Code's ``Stop`` hook shape, so existing controls can be reused:

    {
        "hook_event_name": "AgnoPost",
        "session_id": "<run-id>",
        "cwd": "<working-dir>",
        "last_assistant_message": "<agent-output-text>"
    }

Exit codes:
    0  — output passes, no violation.
    2  — violation detected; stderr contains the corrective message.
    *  — non-blocking error in graunde itself; output passes.

This module is intentionally minimal — all policy logic lives in the
compiled Graunde binary and its ``.pbt`` control files.
"""
import json
import logging
import os
import shutil
import subprocess
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

# Maximum time we'll wait for graunde to respond (milliseconds → seconds).
_TIMEOUT_SEC = 5

# Exit code that graunde uses to signal a policy violation.
_BLOCK_EXIT_CODE = 2


def _find_graunde() -> Optional[str]:
    """Return the path to the graunde binary, or None if not installed."""
    return shutil.which("graunde")


def check_output(
    text: str,
    *,
    session_id: str = "",
    cwd: Optional[Path] = None,
) -> Optional[str]:
    """Run ``text`` through graunde policy controls.

    Args:
        text: The agent's output text to check.
        session_id: Opaque identifier tying retries to the same logical run.
        cwd: Working directory context for scope matching.  Defaults to
            the current process cwd.

    Returns:
        ``None`` if the output passes all controls, or a corrective-message
        string that should be fed back to the agent as a follow-up prompt.
    """
    binary = _find_graunde()
    if binary is None:
        logger.debug("graunde not found on PATH — skipping guardrails")
        return None

    payload = {
        "hook_event_name": "AgnoPost",
        "session_id": session_id or "",
        "cwd": str(cwd or Path.cwd()),
        "last_assistant_message": text,
    }

    try:
        result = subprocess.run(
            [binary],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            timeout=_TIMEOUT_SEC,
        )
    except subprocess.TimeoutExpired:
        logger.warning("graunde timed out after %ss — allowing output", _TIMEOUT_SEC)
        return None
    except OSError as exc:
        logger.warning("Failed to invoke graunde: %s — allowing output", exc)
        return None

    if result.returncode == 0:
        return None

    if result.returncode == _BLOCK_EXIT_CODE:
        correction = result.stderr.strip()
        if correction:
            logger.info("Graunde policy violation: %s", correction[:200])
            return correction
        logger.warning("graunde returned exit 2 but empty stderr — allowing output")
        return None

    # Any other exit code is a non-blocking graunde error.
    logger.debug(
        "graunde exited %d (non-blocking): %s",
        result.returncode,
        result.stderr.strip()[:200],
    )
    return None


async def check_and_retry(
    run_fn,
    *,
    max_retries: int = 2,
    session_id: str = "",
    cwd: Optional[Path] = None,
    on_violation=None,
    **run_kwargs,
) -> str:
    """Run an agent/team via ``run_fn``, retrying on guardrail violations.

    This is the main integration point.  It wraps ``run_agent_async`` or
    ``run_team_async`` (or any async callable that accepts ``message=``
    and returns a string) with a retry loop driven by graunde policy
    checks.

    Args:
        run_fn: Async callable — typically ``run_agent_async`` or
            ``run_team_async``.
        max_retries: How many times to re-run after a violation before
            giving up and returning the last output as-is.
        session_id: Passed to ``check_output`` for scope/attestation.
        cwd: Working directory context for graunde scope matching.
        on_violation: Optional async/sync callback ``(attempt, correction)``
            called when a violation is detected, before the retry.
        **run_kwargs: Forwarded to ``run_fn`` (must include ``message``).

    Returns:
        The final agent output text (either clean, or the last attempt
        if retries are exhausted).
    """
    original_message = run_kwargs["message"]

    for attempt in range(1 + max_retries):
        output = await run_fn(**run_kwargs)

        correction = check_output(output, session_id=session_id, cwd=cwd)
        if correction is None:
            return output

        if attempt >= max_retries:
            logger.warning(
                "Guardrail violation persists after %d retries — returning output as-is",
                max_retries,
            )
            return output

        # Notify caller (e.g. to update UI spinner).
        if on_violation is not None:
            import asyncio
            result = on_violation(attempt + 1, correction)
            if asyncio.iscoroutine(result):
                await result

        # Build retry message: original context + correction.
        run_kwargs["message"] = (
            f"{original_message}\n\n"
            f"---\n"
            f"Your previous response was flagged by a policy check:\n\n"
            f"{correction}\n\n"
            f"Please revise your response to address this issue."
        )

    return output  # unreachable, but keeps the type checker happy
