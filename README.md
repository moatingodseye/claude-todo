# todo — a task queue Claude Code has to actually work

A small Windows tool that gives [Claude Code](https://claude.com/claude-code) a per-project task
queue, and then **holds it to that queue** using Claude Code's own hooks.

Without it, a coding session drifts: you ask for five things, four get done, one is quietly forgotten,
and you find out a week later. With it:

- Every prompt you send is **recorded verbatim**, so nothing you asked for can appear to have vanished.
- The session is **told the head of the queue** at the start of every turn — and nothing else, so it
  cannot skip ahead to the easy items.
- A turn **cannot end** while work remains. Claude gets refused and pushed back to the queue.
- When a task is finished it is **archived with a note** saying what was actually done, so "what
  happened to that?" always has an answer.
- An always-on-top window shows every project's queue at a glance.

This repository is for **deployment only** — two binaries and these docs. The source is not here.

---

## What you get

The two binaries are attached to the [latest release](../../releases/latest) — they are not in the
repository itself, so cloning this stays small. Everything else is here.

| file | where | what it is |
|---|---|---|
| `todo.exe` | release | the command line tool and hook responder |
| `todoui.exe` | release | the viewer: a small always-on-top window showing every queue |
| `todoui-once.cmd` | repo | starts the viewer only if it is not already running — use this from the hook |
| `unhook.cmd` + `unhook.ps1` | repo | the escape hatch, if the hooks ever get in your way |

Both `.exe` files are single, self-contained binaries. Nothing is installed, no runtime is required,
no registry keys are written, and no service is created. Delete the files and the tool is gone.

**Requirements:** Windows x64, and Claude Code. That is all.

---

## Install

1. Make one folder for it. Put both `.exe` files from the [latest release](../../releases/latest) in
   it, along with the `.cmd` and `.ps1` files from this repository. Anywhere you like — `D:\tool`,
   `C:\tools`, a USB stick. The tool keeps its own state beside the exe, so it is portable.
2. Add that folder to your `PATH`, so `todo` and `todoui` work by name.
3. Open a **new** terminal (an existing one keeps its old `PATH`) and check:

   ```
   todo --help
   ```

That is the whole install. `todo` creates what it needs on first use.

### Where it keeps things

- **One queue per project**, in `<your-project>\.claude\todo.db`. Projects never share a queue.
- **One registry**, `registry.db`, in the same folder as the exe — so a portable copy carries its
  own state and nothing is hidden under your user profile.
- **A daily backup** of each queue, beside it, five generations kept.

---

## Wire it into Claude Code

Create or edit `.claude\settings.json` **in the project you want queued**, and add three hooks.
Replace `D:/tool` with wherever you put the binaries.

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "D:/tool/todoui-once.cmd" }] }
    ],
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "D:/tool/todo.exe hook prompt" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "D:/tool/todo.exe hook stop" }] }
    ]
  }
}
```

Restart Claude Code, queue something with `todo add "..."`, and you will see a `QUEUE #1 ...` line
arrive on your next message.

### Two things that will bite you if you use backslashes

**Use forward slashes in that JSON.** Hooks are run through a shell that **strips unquoted
backslashes**, so `D:\tool\todo.exe` arrives as `d:tooltodo.exe` and fails with *command not found*.
Forward slashes need no escaping in JSON and work fine on Windows. This cost real time to discover.

**Use the full path, not `todo`.** A hook's `PATH` is the harness's, not your shell's.

### Point SessionStart at `todoui-once.cmd`, not at the exe

`SessionStart` fires on startup, resume, clear **and** compact. Pointing it straight at `todoui.exe`
opens a new window every time — four windows into one afternoon. `todoui-once.cmd` checks whether the
viewer is already running and does nothing if it is.

### Per-project, not global

Putting the hooks in a project's `.claude\settings.json` means only that project is queued. Put them
in `%USERPROFILE%\.claude\settings.json` if you want every project queued — but try one project first.

---

## Using it

Queue work, and let Claude work it:

```
todo add "fix the drag handle so a mouse can grab it"
todo add "the archive should collapse like the queue rows do"
todo list
```

Claude then drives `next`, `done`, `block` and `resume` itself as it works. You mostly use `add`,
`list`, and the viewer.

```
todo - a per-repo task queue, worked in the order it was given.

  add       queue something at the tail of the list
  next      start the head task; refused if one is already in progress
  done      finish the current task, with an optional note on what was done
  block     park the current task and record what it is waiting on
  resume    un-park a blocked task, back at the head
  bump      move a task to the head - the only way to reorder
  drop      retire a task unworked, with an optional note saying why
  list      the whole queue, in order
  current   the one-line summary the prompt hook prints
  hook      answer a Claude Code hook: prompt or stop
  hold      let the turn end even though work remains
  help      this list; --help and -h do the same
  go        lift a hold and re-arm the stop gate
  promote   turn a capture into a real task, in your own words
  prune     trim archived work older than 90 days, or a given number
  future    work with no repo yet: list it, add to it, drop from it
  capture   record something said, verbatim, without deciding about it yet
```

### The viewer

`todoui` opens a small window, docked top-left and always on top, showing a tab per project plus a
`future` tab. It deliberately **cannot** start, finish, block or drop anything — a button that
finished a task nobody had worked would make the queue describe something that never happened. It can
add, reorder by dragging, and switch a task off.

---

## How it works

### The states a task moves through

| state | meaning |
|---|---|
| **thinking** | captured verbatim from something you said. Not work yet — nobody has decided anything about it. |
| **next / 2nd / 3rd…** | queued work, in the order you gave it. |
| **active** | being worked. Only ever one at a time, enforced by the database, not by good intentions. |
| **blocked** | parked, with a recorded reason — waiting on your answer, or on a machine that is down. |
| **off** | you have held it back. *Not yet*, rather than *never*. Sorts to the bottom and is skipped. |

Finished and abandoned work leaves the queue and lands in an **archive**, marked `done`, `zapped` or
`moved`, with a note. The viewer shows it, collapsed, below the live list.

### Capture, then decide

Everything you type is recorded before anyone judges it. That is the point: a receipt, not a
commitment. A capture can never become the next task by itself, can never hold a turn open, and is
never announced to Claude as work. Later it is either **promoted** into a properly worded task, or
dropped — and dropping archives it, so even a discarded remark can be found again.

### The stop gate

At the end of every turn, Claude Code asks the tool whether it may stop. If work remains — in
progress *or* merely queued — the tool refuses, and Claude is handed the reason and pushed back to the
queue.

That has to be escapable, so:

- **A hold.** `todo hold` lets a turn end with work outstanding. Your next message lifts it, so a hold
  ends a *run*, not the feature.
- **A stand-down.** After several consecutive refusals with nothing completed, the gate gives up and
  says so — a task that genuinely cannot be finished must not trap the session forever. Any completion
  resets the count, so a queue that is moving is never capped.

### Housekeeping

The archive is trimmed by **age, not row count** — a busy week must not evict a quiet month. It
happens on an ordinary command, at most once a month, with no daemon and nothing scheduled. Each
queue is also backed up daily, using SQLite's own consistent-snapshot mechanism rather than a file
copy.

---

## What has been tested

**280 automated tests**, all green, across the command line tool and the viewer. They are aimed at the
paths that actually run rather than at a coverage percentage:

- **The hook contracts**, driven as real processes rather than function calls — because the agreement
  with Claude Code is *"exit 2 with the reason on stderr"*, which is a claim about a process. Tests
  cover the exit codes, the stdout/stderr split, and that a hook never emits housekeeping on either.
- **The stop gate**: that it refuses on in-progress *and* pending work, that it stands down rather
  than wedging a session, that progress re-arms it, that `hold` and `go` work through a real process,
  and that held-back or merely-captured work does not hold a turn open.
- **Capture**: that a prompt is recorded verbatim, that seven kinds of malformed payload record
  nothing and still print the queue line, and that the tool's own harness notifications are not
  mistaken for something you said.
- **The database**: that the one-active-task rule is enforced by a constraint rather than by care,
  that reordering is atomic, that a queue created by an older version is migrated in place, and that
  a backup can be **reopened and read back** — a backup that cannot restore is worse than none.
- **The viewer**: that what the model reports reaches the screen, that an empty window and a broken
  one look different, and that a click asks for the right change with the right arguments.

Beyond the automated tests, every release is exercised by hand: the hooks are driven in a live Claude
Code session, and the binaries are run from a bare folder to confirm they are genuinely
self-contained.

---

## Known limits — read this bit

Being straight with you about what it does not do:

- **Windows only.** The viewer is a native Windows application.
- **Messages typed mid-turn are not captured automatically.** Claude Code raises the prompt hook for a
  *new* message only, so anything you type while Claude is already working never reaches it. There is a
  `todo capture "..."` command for recording those, but it relies on Claude running it.
- **It cannot make Claude competent**, only orderly. It stops work being forgotten or declared
  finished early. It does not check that the work was any good.
- **The queue is per working copy.** Two clones of one project have two separate queues.
- **Nothing is encrypted.** Task text sits in a local SQLite file in plain text. Do not put secrets in
  a task.

---

## If the hooks ever get in your way

From an ordinary command prompt, with Claude Code **closed**, in the folder of the project you want
unhooked:

```
cd C:\your\project
D:\tool\unhook.cmd
```

It needs nothing but Windows PowerShell — no Claude Code, no `todo.exe`, no toolchain. That is the
point: if the hooks have made a session unusable, the way out must not depend on any of them.

It removes **only** the individual hook entries that run `todo.exe` or the viewer, from this project's
settings and the global ones. Hooks of your own in the same sections are left exactly as they are, and
a settings file it cannot parse is reported rather than rewritten.

You can also just delete the `hooks` block you added, or move the binaries out of the way.

---

## Licence

See [LICENSE](LICENSE). Short version: **use it at your own risk.** It is provided as-is, with no
warranty of any kind, and the author is not liable for anything that happens as a result of using it.
