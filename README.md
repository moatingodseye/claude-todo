# todo — a task queue Claude Code has to actually work

A small Windows tool that gives [Claude Code](https://claude.com/claude-code) a per-project task
queue, and then **holds it to that queue** using Claude Code's own hooks.

Without it, a coding session drifts: you ask for five things, four get done, one is quietly forgotten,
and you find out a week later. With it:

- Every prompt you send is **recorded verbatim**, so nothing you asked for can appear to have vanished.
- The session is **told the head of the queue** at the start of every turn — and nothing else, so it
  cannot skip ahead to the easy items.
- Work **cannot start** while something you said is still untriaged. The edit is refused, not merely
  discouraged, until your message has been read and turned into tasks.
- A turn **cannot end** while work remains. Claude gets refused and pushed back to the queue.
- When a task is finished it is **archived with a note** saying what was actually done, so "what
  happened to that?" always has an answer.
- When Claude gets stuck it **parks the task with a reason**, and you answer that reason **in the
  window, against the task** — not somewhere up the chat.
- A window shows every project's queue at a glance; pinning it on top is a checkbox.

This repository is where you get it and how you set it up.

---

## What you get

The two programs are attached to the [latest release](../../releases/latest), so cloning this stays
small. The scripts are here in the repository.

| file | where | what it is |
|---|---|---|
| `todo.exe` | release | Windows x64: the command line tool and hook responder |
| `todoui.exe` | release | Windows x64: the viewer — a small window showing every queue, optionally pinned on top |
| `skill/todo/SKILL.md` | repo | the Claude Code skill - copy the folder into `~/.claude/skills/` |
| `unhook.cmd` + `unhook.ps1` | repo | the escape hatch, if the hooks ever get in your way |
| `SHA256SUMS.txt` | release | checksums for everything above, so you can verify what you downloaded |

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

#### Linux, and why this release has none

This release is **Windows only**, and the Linux binary the previous release carried is **withdrawn**.

It did not work. `package:sqlite3` asks the loader for the unversioned name `libsqlite3.so`, which on
Debian and Ubuntu exists only in `libsqlite3-dev`; a stock host has `libsqlite3.so.0` and nothing else,
so `todo --version` died on a nine-frame stack trace. The README claimed the ordinary `libsqlite3-0`
package was enough. That was wrong, and it was found only by running the shipped binary on a plain
Ubuntu 24.04 host rather than in the container it was built in.

Both faults are **fixed in the source** — the loader now tries `libsqlite3.so.0` as well, and
`--version` and `--help` no longer open a database at all. Neither fix is shipped here, because
without a viewer a Linux CLI is of little use, and a Linux viewer is not built: `todoui` is a native
Windows application. Everything the viewer shows is available from `todo list`, so a Linux build is a
reasonable thing to want — it is simply not what this release is.

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

That is the whole install. `todo` creates what it needs on first use, and `todo --help` works from any
directory — it opens no queue, so it cannot fail on an unwritable one.

### Where it keeps things

- **One queue per project**, in `<your-project>\.claude\todo.db`. Projects never share a queue.
- **One registry**, `registry.db`, in the same folder as the exe — so a portable copy carries its
  own state and nothing is hidden under your user profile.
- **A daily backup** of each queue, beside it, five generations kept.

---

## Wire it into Claude Code

Claude Code can run a command at certain moments — those are **hooks**. This tool is four of them.
Nothing happens until you add them, and removing them turns everything off again.

### What each hook does

| hook | when Claude Code runs it | what the tool does with it |
|---|---|---|
| `UserPromptSubmit` | every time you send a message | Records your message verbatim, then prints one line naming the head of the queue. Claude Code puts that line into the conversation, so the session is told what it is supposed to be working on — and nothing else, so it cannot skip ahead. |
| `Stop` | when Claude tries to end its turn | Checks whether work is outstanding. If it is, the tool **refuses**, and Claude is handed the reason and pushed back to the queue. This is the part that makes the queue binding rather than advisory. |
| `PreToolUse` | before Claude edits a file or runs a command | Checks whether anything you said is still untriaged. If it is, the tool **denies the call** and tells Claude to deal with your message first. `Stop` can only refuse at the *end* of a turn, by which point the work has already been chosen; this refuses at the moment of choosing. `todo` commands themselves are never denied, and reading is never denied. |
| `SessionStart` | when a session starts, resumes, or is cleared | Opens the viewer window. Purely a convenience — leave it out if you do not want the window. **Do not point this hook straight at `todoui.exe`:** on the first start with no viewer already running it never exits, and Claude Code waits for it forever. Point it at `todo.exe hook sessionstart`, which starts the viewer detached and returns in 76 ms from cold. |

`UserPromptSubmit` and `Stop` are the minimum. `PreToolUse` is what makes the queue bite *before* work
starts rather than after — add it if you want that, leave it out if you find it too strict.
`SessionStart` is optional.

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
       "PreToolUse": [
         { "matcher": "Edit|Write|MultiEdit|NotebookEdit|Bash",
           "hooks": [ { "type": "command", "command": "D:/tool/todo.exe hook pretooluse" } ] }
       ],
       "SessionStart": [
         { "hooks": [ { "type": "command", "command": "D:/tool/todo.exe hook sessionstart" } ] }
       ]
     }
   }
   ```

4. **If the file already exists**, do not replace it. Add the entries inside its existing
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

Four commands, and nothing else:

```
<your folder>/todo.exe hook prompt        for UserPromptSubmit
<your folder>/todo.exe hook stop          for Stop
<your folder>/todo.exe hook pretooluse    for PreToolUse       (optional, the strict one)
<your folder>/todo.exe hook sessionstart  for SessionStart     (optional, viewer only)
```

`PreToolUse` also takes a **matcher**, so the gate only sees the calls that change things:

```json
"PreToolUse": [
  { "matcher": "Edit|Write|MultiEdit|NotebookEdit|Bash",
    "hooks": [{ "type": "command", "command": "D:/tool/todo.exe hook pretooluse" }] }
]
```

`SessionStart` fires on startup, resume, clear **and** compact, so it will run several times in an
afternoon. Every firing is cheap: the viewer takes a single-instance lock, so a later launch finds the
lock held, brings the window you already have to the front, and exits at once.

`hook prompt` and `hook stop` are arguments to `todo.exe` — they tell it which hook is calling. You do
not need any other arguments, wrappers, shells or quoting.

### Two things that will bite you if you use backslashes

**Use forward slashes in that JSON.** Hooks are run through a shell that **strips unquoted
backslashes**, so `D:\tool\todo.exe` arrives as `d:tooltodo.exe` and fails with *command not found*.
Forward slashes need no escaping in JSON and work fine on Windows. This cost real time to discover.

**Use the full path, not `todo`.** A hook's `PATH` is the harness's, not your shell's, so a bare
`todo` fails even when it works perfectly in your terminal.



### Why the viewer hook is `todo.exe`, not `todoui.exe`

Claude Code waits for a `SessionStart` hook to **exit** *and* for its **stdout to reach EOF** before the
session becomes usable. `todoui.exe` does neither when it is the first copy to start: it takes the
single-instance lock and then runs, as a window should.

So wiring `SessionStart` straight to `todoui.exe` hangs Claude Code on the first start after a reboot —
totally, not slowly. No output, no error, no timeout, and `/exit` does not work either, because the
shutdown path is also waiting on the hook. The session has to be killed. Once a viewer *is* running the
same wiring is instant, which is what makes this easy to miss: it only bites from cold.

`todo.exe hook sessionstart` is the answer. It spawns the viewer **detached** — its own handles, its own
process group — so the hook exits and the pipe closes while the window stays up. Measured on this
machine: **76 ms from cold** with no viewer running, **52 ms** with one already up, rc=0 and no output
either way.

That hook is answered before the tool touches SQLite or the registry at all, so it cannot fail on an
unwritable folder and it creates nothing. It is also silent on purpose: a `SessionStart` hook's stdout is
injected into the session as context, and "started the viewer" is machinery, not something the session
needs told. A window that will not open is an annoyance, not a reason to fail a session start — so it
always exits 0.

Earlier releases used a `todoui-start.cmd` launcher for this. It worked (479 ms from cold) but it was a
second file to keep beside the exe, and one more thing to get wrong: the obvious "simplification" to
`start` fails in the worst possible way — the window appears, so it looks like it worked, but the child
inherits the stdout pipe and the session still hangs (measured: rc=124 after 15s). The binary now does
the job itself, and **the launcher is gone from this repository.** If you have a hook pointing at
`todoui-start.cmd`, change it to `todo.exe hook sessionstart`; the old wiring keeps working as long as
you keep your copy of the file, but it is no longer shipped or tested.

### Teach Claude how to drive it

The hooks make the queue binding, but they do not tell Claude *how* to work it — and without
that it tends to leave every captured message sitting in `thinking` and clear them with
`drop`, which archives finished work as if it had been abandoned. The skill in
`skill/todo/` is what closes that gap:

```
cp -r skill/todo ~/.claude/skills/          # or copy the folder on Windows
```

Restart Claude Code and it appears as the `todo` skill.

### Per-project, not global

Putting the hooks in a project's `.claude\settings.json` means only that project is queued. Put them
in `%USERPROFILE%\.claude\settings.json` if you want every project queued — but try one project first.

Scope decides one thing beyond which projects are queued: **whether you can get out.** Hooked into one
project, a hook that misbehaves kills only that project, and you can open Claude Code anywhere else and
run `unhook.cmd`. Hooked globally, every new session in every project is affected — including the fresh
one you would have opened to fix it. Then your way back in is `unhook.cmd` from a terminal with Claude
Code closed, or editing `settings.json` by hand.

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
  done      finish the task in hand, or one named by id, with a note on what was done
  block     park the task in hand, or one named by id, recording what it waits on
  resume    un-park a blocked task, back at the head
  bump      move a task to the head - the only way to reorder
  drop      retire a task unworked, with an optional note saying why
  list      the whole queue, in order
  current   the one-line summary the prompt hook prints
  hook      answer a Claude Code hook: prompt, stop, sessionstart, pretooluse
  hold      let the turn end even though work remains, with a reason RB can see
  help      this list; --help and -h do the same
  go        lift a hold and re-arm the stop gate
  promote   turn a capture into real tasks, in your own words - one argument per task
  prune     trim archived work older than 90 days, or a given number
  future    work with no repo yet: list it, add to it, drop from it
  capture   record something said, verbatim, without deciding about it yet
  comment   add a remark to the thread on a task, without changing its state
  thread    read the thread on a task, and mark replies from RB as read
  needs     record that one task cannot be worked until another leaves the queue
  archive   what has left the queue, completed or dropped, newest first
  version   which build this is; --version and -v do the same

The queue lives in <repo>/.claude/todo.db, one per working copy.
Exit codes: 0 fine, 1 usage or refused, 2 the Stop hook holding a turn open.
```

### The viewer

![The viewer: a tab per project, the live queue with the active task at the top, the always-on-top checkbox and collapse control in the header, and the archive collapsed underneath](docs/img/todoui.png)

`todoui` opens a small window, docked top-left, showing a tab per project plus a `future` tab. It
deliberately **cannot** start, finish, block or drop anything — a button that finished a task nobody had
worked would make the queue describe something that never happened. It can add, reorder by dragging, and
switch a task off.

- **Always on top is a checkbox**, and it is remembered. Some people want the window pinned over
  everything; others find that maddening. Untick it and it behaves like an ordinary window.
- **Collapse** shrinks the window to the tabs plus the task actually being worked, which is the state
  worth having on screen all day. It measures the content it is collapsing to, rather than assuming a
  height — a blocked task with a long reason needs more room than a one-line active one, and guessing
  clipped it.
- **One window, however many sessions.** The viewer takes a single-instance lock, so a second launch
  raises the window you already have and exits. This matters if you open several terminals, or wire the
  hook globally rather than per project: without the lock you get a window per session.

### Answering a blocked task, in the viewer

When Claude parks a task with `block "<reason>"`, that reason is a question. The viewer gives you a box
to answer it **against the task**, rather than in the chat:

- Your reply is attached to the task, so there is no doubt which of five parked things you meant.
- The `Stop` gate will not let the turn end while a reply is unread, so an answer cannot be missed.
- `todo thread <id>` is how Claude reads it, and reading marks it read.

This is the difference between "I said something about that somewhere above" and an answer filed
against the thing it answers.

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
commitment. A capture can never become the next task by itself and is never announced to Claude as work.
Later it is either **promoted** into a properly worded task, or dropped — and dropping archives it, so
even a discarded remark can be found again.

**Promoting takes as many tasks as the message contained**, in one transaction:

```
todo promote 42 "put the debug lines back" "use a flag instead of commenting out"                "check it in the debug classes" "cure the propagate problem"
```

One paragraph routinely carries four or five separate pieces of work, and one fat row called "do what
was asked" is a capture wearing a costume. Splitting is also how you see that the message was
understood: five rows say what one row cannot.

New instructions go to the **tail**, not the head. That is deliberate, and it is the whole premise —
you interrupted with something new, and the thing being worked when you interrupted must not be the
thing that gets forgotten.

**The `PreToolUse` gate is what makes this happen before the work rather than after.** While a capture
is untriaged, an `Edit`, `Write` or `Bash` call is denied outright and the refusal says what to run.
`Stop` can only object at the *end* of a turn, by which point the work has already been chosen — which
is how you get four thinking rows and a session that answered the first thing it saw.

### The stop gate

At the end of every turn, Claude Code asks the tool whether it may stop. The tool refuses if anything is
outstanding — work in progress, work merely queued, a message still sitting untriaged, or a reply of
yours that has not been read — and Claude is handed the reason and pushed back to the queue.

It also **reads the session transcript** at this point, to catch the messages you typed while Claude was
already working. Claude Code does not raise the prompt hook for those, so without this they never reached
the queue at all.

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

**296 automated tests** (229 command line, 67 viewer), all green. They are aimed at the
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
  that any number of tasks can be parked at once while still only one is in progress, that a queue
  built by an earlier version has its constraint migrated in place on the next open,
  that reordering is atomic, that a queue created by an older version is migrated in place, and that
  a backup can be **reopened and read back** — a backup that cannot restore is worse than none.
- **The viewer**: that what the model reports reaches the screen, that an empty window and a broken
  one look different, and that a click asks for the right change with the right arguments.

Beyond the automated tests, every release is exercised by hand before it is published:

- **All four hooks driven in a live Claude Code session** — the queue line injected into a real prompt,
  the stop gate refusing a real attempt to end a turn, the `PreToolUse` gate denying a real `Edit` while
  a message sat untriaged, and the viewer opening from a cold start without hanging the session.
- **Each binary run from a bare folder** containing nothing but the binaries: `--help`, `add`, `next`,
  `block` twice, `list`, and every hook. This confirms they are genuinely self-contained — no DLL, no
  runtime, nothing beside them.
- **`--help` and `--version` run from a directory the user cannot write to** (`C:\Windows\System32`),
  because those are the first commands anyone runs and neither must need a queue. They are answered
  before the tool opens SQLite at all, which is what makes that true rather than merely likely.
- **The `PreToolUse` gate driven against real command lines**, not invented ones. Its allow-list was
  wrong four times over — first token only, then pipes into read-only filters, then shell punctuation
  inside quoted arguments, then a missing `echo` — and each fault was found by an ordinary command
  being refused, not by reading the code.

---

## Known limits — read this bit

Being straight with you about what it does not do:

- **This release is Windows only.** The viewer is a native Windows application, and no Linux build is
  published — see [Linux, and why this release has none](#linux-and-why-this-release-has-none). macOS is
  not built.
- **Messages typed mid-turn arrive late, not never.** Claude Code raises the prompt hook for a *new*
  message only, so anything you type while Claude is already working is invisible to it at the time. The
  `Stop` hook now reads the session transcript and picks those messages up at the **end of the turn**, so
  they do land in the queue — but they land after the turn that should have handled them, and that is the
  best a hook can do. Nothing is silently lost; it is simply recorded a turn later than you said it.
- **The `PreToolUse` gate is strict, and strict cuts both ways.** It refuses edits while a message is
  untriaged, which is the point, but a hook that can refuse tool calls is a hook that can get in your
  own way. It fails open — any error and the call is allowed — and `unhook` removes it. Leave it out of
  your settings if you would rather it only nagged at the end of a turn.
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
