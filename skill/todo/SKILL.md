---
name: todo
description: Drive the claude-todo queue - the per-repo task queue enforced by four Claude Code hooks, one of which DENIES edits while a message is untriaged. Use whenever a QUEUE line appears, when a tool call is refused with a queue reason, when the user gives new instructions to record, when work starts, finishes or gets stuck, and before ending a turn with work outstanding.
---

# claude-todo

A per-repo task queue, worked in the order it was given, and **binding rather than advisory**: hooks
refuse rather than remind. `todo help` lists every command and what it takes — it is generated from the
code, so it cannot be out of date and this file does not repeat it.

## What the tool enforces, so you need not remember it

| you cannot | because |
|---|---|
| work with a message untriaged | `PreToolUse` **denies** `Edit`, `Write` and `Bash` — everything except `todo` itself |
| end a turn with work or a capture outstanding | the `Stop` gate exits 2 |
| open a second task | a database constraint, not restraint |
| miss a reply, or a message typed mid-turn | the `QUEUE` line, the gate, and the transcript reconciliation |

**A refused tool call is the mechanism working, not a fault.** The refusal says what to run. Run it.

Because all of that is mechanical, **this file is only about the part that is not**.

## One message is usually SEVERAL tasks

The gate makes you triage. It cannot make you triage *well* — one `promote` satisfies it — and that is
the whole failure this skill exists to prevent.

Read the message and count the imperatives. *"Put the debug lines back, use a flag instead of commenting
out, check it in the debug classes, and work out how to cure the propagate problem"* is **four** tasks.
So is anything joined by "and", "also", "then", or a sentence that changes subject.

```
todo promote <id> "the first piece" "the second" "the third"
```

One command, one transaction. The first piece keeps the capture's id and its verbatim text.

**The test: if you cannot `done` it in one go with one honest note, it is more than one task.** A task
called "do the thing RB asked for" is a capture wearing a costume.

Splitting is also how the user sees you understood him. One fat row says "I read a message"; five rows
say "I read the message and here is what is in it".

## `done` is the default; `drop` is the exception

Only you know whether work happened, so no hook can decide this.

| the message was | do this |
|---|---|
| work to do | `promote` → `next` → `done "<what happened>"`, or `block "<reason>"` if it cannot finish |
| a question you answered in your reply | `done <id> "<the answer, in one line>"`. It *was* completed — the request was to answer |
| an acknowledgement, a correction, a sign-off | the same. It carried information and you acted on it |
| work that will genuinely never happen | `drop <id>` — and nothing else, ever |

The test for `drop` is **not** "was there anything for me to do". It is "is this a piece of work that
will never be done". A sign-off is not that. Reaching for `drop` because it is one command instead of
three is what fills the archive with completed work labelled abandoned — and the archive is the only
answer to "what happened to that?".

## Say what actually happened

A note and a reason are read by a person later. Both pass every check while being useless.

- `done "<note>"` — what was *actually* done, with the commit, the URL, the measurement. "fixed it" is
  not a note.
- `block "<reason>"` — name the thing. `block "needs a GitHub token with Issues:RW"`, never
  `block "waiting"`. The reason is the question the user answers, and he answers it **in the viewer**,
  against the task.
- `promote <id> "<text>"` — your own words, not the raw prompt. It refuses to reuse the prompt, but only
  you can make the restatement a good one.

## Never `capture` a user message yourself

Two mechanisms record what he says, and neither is you:

| the message | recorded by | when |
|---|---|---|
| starts a turn | the `UserPromptSubmit` hook | immediately |
| arrives **mid-turn** | the `Stop` hook, reading the transcript | at the **end of the turn** |

So a mid-turn message **is genuinely not in the queue while the turn runs**. That is expected. Act on
what was said; it lands as a capture at the end, and then usually wants `done <id>`, because you have
already handled it.

Calling `todo capture` on it duplicates the row, and clearing the duplicate leaves a `drop` reading as
abandoned work. `capture` is for something *you* need on the board that he did not say — which is almost
never.

## Two things that are his, not yours

- **`bump`** — priority is his to give. The one exception: bump without asking when a task **blocks other
  queued work**, and say in the `done` note what it unblocked.
- **`enabled`** — never switch a task on or off, not even as a side effect.

---

`todo help` for the commands. `design.md` in the repo for how any of it works and why.
