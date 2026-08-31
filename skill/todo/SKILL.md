---
name: todo
description: Drive the claude-todo queue - the per-repo task queue enforced by four Claude Code hooks, one of which DENIES edits while a message is untriaged. Use whenever a QUEUE line appears, when a tool call is refused with a queue reason, when the user gives new instructions to record, when work starts, finishes or gets stuck, and before ending a turn with work outstanding.
---

# claude-todo — where the rules actually live

A per-repo task queue, worked in the order it was given, and **binding rather than advisory**: hooks
refuse rather than remind. **A refused tool call is the mechanism working, not a fault** — the refusal
says what to run, so run it.

This file is a pointer, on purpose. It used to carry the judgement rules and three copies of them
existed, none versioned with the binary that enforces them.

| what you want | where it is | why not here |
|---|---|---|
| the judgement rules — how many tasks a message is, `done` vs `drop`, what a `block` reason must be | printed by the **`SessionStart` hook**, injected as session context | it ships *inside* the binary, so it cannot disagree with the tool's behaviour |
| every command and what it takes | `todo help` | generated from the code, so it cannot be out of date |
| how any of it works, and why | `design.md` in the repo | reasoning, not reference |

**If you did not see the guidance this session**, the queue is still enforced but you are working
without the part no hook can check. It comes from the server, so a session that started with none —
or a project on a machine where nothing is wired — gets silence. Print it on demand:

    <the binary your hooks name> hook sessionstart

The exact path is in `.claude/settings.json`, or in `%USERPROFILE%\.claude\settings.json` when the
hooks are wired globally. There is deliberately no `todo` on `PATH`.

**If that prints nothing at all**, the project is wired to a tool too old to have this — v0.3.0 and
earlier printed no guidance. Re-run that release's `install.cmd`, or read the rules in `design.md`.
