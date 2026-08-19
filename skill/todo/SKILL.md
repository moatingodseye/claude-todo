---
name: todo
description: Drive the claude-todo queue - the per-repo task queue enforced by the UserPromptSubmit and Stop hooks. Use whenever a QUEUE line appears in the conversation, when the user gives new instructions to record, when work starts, finishes, or gets stuck, and before ending a turn with work outstanding.
---

# claude-todo

A per-repo task queue, worked in the order it was given. It is **binding, not advisory**: a
`Stop` hook refuses to let the turn end while work is outstanding, and a `UserPromptSubmit`
hook names the head of the queue on every message so the session cannot quietly skip ahead.

Binary: `todo` (`C:\tools\todo.exe` on Windows). Queue: `<repo>\.claude\todo.db`, one per
working copy. Viewer: `todoui`, launched by `SessionStart` via `todoui-start.cmd`.

## The one rule that matters

**A capture is not a task. Promote it.**

Every message the user sends is captured verbatim, as `thinking`. That is a record of what
was said, not a decision about it. It stays `thinking` until *you* turn it into work:

```
todo promote <id> "the task, in your own words"
```

`thinking` → `pending`. Then `next` → `inprogress`, then `done`.

**Do not clear a capture with `drop` because you have handled it.** `drop` means *retired
unworked*, and using it for finished work fills the archive with completed things labelled as
abandoned — which makes the archive lie about what got done. `drop` is only for work that is
genuinely not going to happen.

If the user says items are "still showing as thinking", this is what they mean: captures are
piling up unpromoted.

## Every turn ends with nothing left in `thinking`

**The last thing you do in a turn — after the work is done and the reply is settled, but
before you send it — is clear every outstanding capture.** Not at the start of the next turn,
and not "later". A capture left in `thinking` is an unanswered question on the board.

That includes the capture of the message you are answering right now. Three dispositions, and
every capture takes exactly one:

| the message was | do this |
|---|---|
| **work to do** | `promote <id> "<the task>"`, then `next`, and `done "<what happened>"` when it is finished — or `block "<reason>"` if it cannot be finished yet |
| **a question, answered in your reply** | `promote <id> "<what was asked>"` → `next` → `done "<the answer, in one line>"`. It *was* completed: the request was to answer, and you answered |
| **not going to happen** | `drop <id>` — the only correct use of `drop` |

A question is still work, so it still gets `done` rather than `drop`. The note is where the
answer goes, so the archive says what was asked *and* what came back.

If a turn ends and `todo list` shows anything in `thinking`, the turn is not finished.

## States

| state | meaning |
|---|---|
| `thinking` | captured verbatim from something the user said. Not work yet |
| `pending` | queued work, in the order given |
| `inprogress` | being worked. **Only ever one at a time**, enforced by the database |
| `blocked` | parked, with a recorded reason |

Finished and abandoned work leaves the queue for an **archive**, marked completed or dropped,
with an optional note. The viewer shows it collapsed under the live list.

## Commands

| command | what it does |
|---|---|
| `todo add "<text>"` | queue something at the tail |
| `todo capture "<text>"` | record something verbatim as `thinking`, without deciding |
| `todo promote <id> "<text>"` | turn a capture into a real task, in your own words |
| `todo next` | start the head task. Refused if one is already in progress |
| `todo done ["<note>"]` | finish **the in-progress task**. Takes no id |
| `todo block "<reason>"` | park the in-progress task, recording what it waits on |
| `todo resume <id>` | un-park a blocked task, back at the head |
| `todo bump <id>` | move a task to the head — the only way to reorder |
| `todo drop <id>` | retire a task **unworked**, with an optional note |
| `todo list` | the whole queue, in order |
| `todo current` | the one-line summary the prompt hook prints |
| `todo hold` | let the turn end even though work remains |
| `todo go` | lift a hold and re-arm the Stop gate |
| `todo prune [n]` | trim archived work older than 90 days, or n |
| `todo future …` | work with no repo yet: `future`, `future add "<text>"`, `future drop <id>`, `future move <id>`, `future queue <id>` |
| `todo hook prompt\|stop` | answer a Claude Code hook. Not for manual use |

Exit codes: **0** fine, **1** usage or refused, **2** the Stop hook holding a turn open.

## How to work a session

1. **A `QUEUE #n` line in the conversation is the task to work.** Do not skip ahead to
   something else in the queue, and do not start unrelated work.
2. **New instructions arrive as captures.** Promote the ones you are going to act on;
   `promote` rather than re-`add`, so the id and the verbatim text stay linked.
3. **`next` before working, `done` after.** One in progress at a time. `done` carries a note
   — use it to say what actually happened, including the URL, commit, or measurement, because
   that note is what the archive keeps.
4. **When you cannot proceed, `block` with the real reason.** Not "waiting" — name the thing:
   `todo block "needs a GitHub token with Issues:RW"`. The reason is shown in the viewer and
   is what the user answers.
5. **Split work that is really several things.** `add` the parts. A task that cannot be
   `done` in one go should not be one task.
6. **Ending a turn with work outstanding:** the Stop gate refuses, correctly. If stopping is
   genuinely right — you are waiting on the user — either `block` the task or `todo hold`.
   `hold` is for "let this turn end, the work remains"; lift it with `go`.
7. **Then run `todo list` as your last action.** Nothing should be in `thinking`. See
   [above](#every-turn-ends-with-nothing-left-in-thinking).

## Traps

**`done` only ever means the in-progress task.** It takes no id. So `todo done` right after
`todo next` on the wrong task closes the wrong thing — check `todo current` first when you are
not certain which is in progress. Recovering means `add`ing the task back, which loses its
history.

**`todo done` with nothing in progress prints `nothing is in progress` and exits 1.** The
wording reads mild enough to skim as "nothing left to do", so check the exit code rather than
the prose — it is a refusal, and nothing was closed.

**`--help` is not safe on every subcommand.** `add` and `capture` treat it as *content* and
queue a task literally called `--help`; `next` will then start it. `drop`, `bump`, `resume`
and `future` print usage properly. Use `todo help` for the command list.

**The queue is per working copy.** `<repo>\.claude\todo.db`. Two checkouts of the same
project have two queues, and running `todo` from the wrong directory silently addresses the
wrong one. `todo list` showing an unexpected queue usually means the working directory is
wrong.

## The hooks

```
UserPromptSubmit   todo.exe hook prompt        captures the message, prints the QUEUE line
Stop               todo.exe hook stop          refuses to end the turn while work is outstanding
SessionStart       todoui-start.cmd            opens the viewer
```

**`SessionStart` must point at `todoui-start.cmd`, never at `todoui.exe`.** The viewer does
not exit when it is the first instance, and Claude Code waits for a `SessionStart` hook to
exit *and* for its stdout to reach EOF — so wiring the exe directly hangs the session
outright on the first start after a reboot, with no error and no working `/exit`.

Escape hatch, with Claude Code closed: `unhook.cmd`, or edit `~/.claude/settings.json` by
hand.
