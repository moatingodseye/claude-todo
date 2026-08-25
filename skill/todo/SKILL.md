---
name: todo
description: Drive the claude-todo queue - the per-repo task queue enforced by four Claude Code hooks, one of which DENIES edits while a message is untriaged. Use whenever a QUEUE line appears, when a tool call is refused with a queue reason, when the user gives new instructions to record, when work starts, finishes or gets stuck, and before ending a turn with work outstanding.
---

# claude-todo

**The guidance is printed by the tool, at the start of every session.** There is nothing to read here.

`todo hook sessionstart` — one of the four hooks — writes it to stdout, and Claude Code injects a
`SessionStart` hook's stdout into the session as context. So the text ships inside the binary,
versioned with the behaviour it describes, and it cannot be missing, out of date, or disagree with a
copy somewhere else. It used to be 99 lines in this file, kept byte-identical to a copy in the repo and
a third attached to the release; three copies of one text is three chances to disagree.

`todo help` lists every command and what it takes. It is generated from the code, so it cannot be out
of date, and neither this file nor the session-start text repeats it.

**If a session did not begin with that guidance**, the tool wired into that project is older than
1.0.0. Run `install.cmd` from the project folder to upgrade it and re-wire the four hooks; the text
appears from the next session on.

`design.md` in the repo says how any of it works and why.
