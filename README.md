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

This repository is where you get it and how you set it up.

---

## What you get

The two programs are attached to the [latest release](../../releases/latest), so cloning this stays
small. The scripts are here in the repository.

| file | where | what it is |
|---|---|---|
| `todo.exe` | release | the command line tool and hook responder |
| `todoui.exe` | release | the viewer: a small always-on-top window showing every queue |
| `unhook.cmd` + `unhook.ps1` | repo | the escape hatch, if the hooks ever get in your way |

### Exactly what the binaries are

- **Native Windows 64-bit executables** (x86-64 / AMD64). Not scripts, not installers, not
  self-extracting archives.
- **Single self-contained files.** Everything each one needs is inside it — no runtime to install, no
  DLLs to place beside them, no redistributable.
- **Built and tested on Windows 11 (x64).** They are expected to work on Windows 10 x64, but that has
  not been tested and is not claimed.
- **Nothing is installed.** No registry keys, no services, no scheduled tasks, no start-up entries, no
  files outside the folders described below. Delete the two files and the tool is gone.
- `todo.exe` is roughly 9 MB and `todoui.exe` roughly 14 MB, because each carries what it needs.
- **No network access.** Neither program contacts anything; there is no telemetry and no update check.

**Requirements:** 64-bit Windows, and Claude Code. That is all.

---

## Install

1. Make one folder for it. Put both `.exe` files from the [latest release](../../releases/latest) in
   it, along with `unhook.cmd` and `unhook.ps1` from this repository. Anywhere you like — `D:\tool`,
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

Claude Code can run a command at certain moments — those are **hooks**. This tool is three of them.
Nothing happens until you add them, and removing them turns everything off again.

### What each hook does

| hook | when Claude Code runs it | what the tool does with it |
|---|---|---|
| `UserPromptSubmit` | every time you send a message | Records your message verbatim, then prints one line naming the head of the queue. Claude Code puts that line into the conversation, so the session is told what it is supposed to be working on — and nothing else, so it cannot skip ahead. |
| `Stop` | when Claude tries to end its turn | Checks whether work is outstanding. If it is, the tool **refuses**, and Claude is handed the reason and pushed back to the queue. This is the part that makes the queue binding rather than advisory. |
| `SessionStart` | when a session starts, resumes, or is cleared | Opens the viewer window. The viewer refuses to open a second copy of itself and brings the existing one to the front instead, so this firing repeatedly is harmless. Purely a convenience — leave it out if you do not want the window. |

Only `UserPromptSubmit` and `Stop` matter. `SessionStart` is optional.

### Adding them, step by step

1. **Pick the project you want queued.** Hooks live per project, so start with one rather than all of
   them.

2. **Find or create the settings file** at `.claude\settings.json` inside that project — the same
   `.claude` folder Claude Code already uses. Create both the folder and the file if they are not
   there.

3. **If the file is new**, paste this in whole. Change `D:/tool` to the folder you put the binaries in,
   and leave everything else exactly as it is:

   ```json
   {
     "hooks": {
       "UserPromptSubmit": [
         { "hooks": [ { "type": "command", "command": "D:/tool/todo.exe hook prompt" } ] }
       ],
       "Stop": [
         { "hooks": [ { "type": "command", "command": "D:/tool/todo.exe hook stop" } ] }
       ],
       "SessionStart": [
         { "hooks": [ { "type": "command", "command": "D:/tool/todoui.exe" } ] }
       ]
     }
   }
   ```

4. **If the file already exists**, do not replace it. Add the three entries inside its existing
   `"hooks"` object, keeping whatever is already in there. If it has no `"hooks"` object, add the whole
   block above as a new top-level key alongside what is already in the file.

5. **Check the JSON is valid.** A settings file that does not parse makes Claude Code ignore *every*
   setting in it, silently. A quick check from PowerShell:

   ```
   Get-Content .claude\settings.json -Raw | ConvertFrom-Json
   ```

   No output means it parsed. An error means fix it before going further.

6. **Restart Claude Code.** Settings are read when a session starts.

7. **Confirm it is working.** Queue something and send any message:

   ```
   todo add "prove the hooks are working"
   ```

   Your next message should come back with a line like:

   ```
   QUEUE #1 pending "prove the hooks are working" (+0 behind) — not started
   ```

   That line is the `UserPromptSubmit` hook. To see the `Stop` hook, let Claude start the task
   (`todo next`) and then try to end its turn — it will be refused and told to finish or park it.

### What goes in the `command` field, exactly

Three commands, and nothing else:

```
<your folder>/todo.exe hook prompt      for UserPromptSubmit
<your folder>/todo.exe hook stop        for Stop
<your folder>/todoui.exe                for SessionStart
```

`SessionStart` fires on startup, resume, clear **and** compact, so it will run several times in an
afternoon. That is fine: the viewer takes a single-instance lock and a second launch simply brings the
window you already have to the front.

`hook prompt` and `hook stop` are arguments to `todo.exe` — they tell it which hook is calling. You do
not need any other arguments, wrappers, shells or quoting.

### Two things that will bite you if you use backslashes

**Use forward slashes in that JSON.** Hooks are run through a shell that **strips unquoted
backslashes**, so `D:\tool\todo.exe` arrives as `d:tooltodo.exe` and fails with *command not found*.
Forward slashes need no escaping in JSON and work fine on Windows. This cost real time to discover.

**Use the full path, not `todo`.** A hook's `PATH` is the harness's, not your shell's.



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
