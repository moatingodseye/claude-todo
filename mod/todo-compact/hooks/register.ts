import type { Register } from 'claude-code'

// Compact after a done - `#620`, design.md *Compact after a done*. todo's Stop hook lets the turn end once
// after a finished task, but only when `<repo>/.claude/compact.alive` names this session, and tells this
// mod which task in `compact.due`. Here: compact if the context is over the repo's `minPercent`, then
// ALWAYS submit the prompt that carries the queue on. A mod that fails must cost the compaction, never the
// flow.
const MARK = '[todo-compact]'
const NEXT = `${MARK} a task was finished - run todo next and carry on with the queue`
const DEFAULT_MIN = 10
// What `$.session.compact()` says when a turn is running - both spellings seen in compact.log (`#665`).
const BUSY = /a turn is (running|in flight)/
// `#718`, design.md *The carry-on prompt is checked, not trusted*. How long an accepted prompt has to start
// its turn (the UserPromptSubmit hooks alone take ~7s), how long after a refused one to send it again, and
// how many sends before giving up.
const SETTLE = 30_000
const RESEND = 5_000
const SENDS = 4
// A compaction refused over a turn that is not the main loop's: tried again this often, this many times.
const BUSYWAIT = 15_000
const BUSYTRIES = 8

// The main loop's `turn.start`s so far. A carry-on prompt has worked once this moves.
let starts = 0

type Files = {
  fs: {
    read: (p: string) => Promise<string>
    write: (p: string, t: string) => Promise<void>
    exists: (p: string) => Promise<boolean>
  }
}

function dir(root: string): string {
  return `${root.replace(/[\\/]+$/, '')}/.claude`
}

async function readtext($: Files, path: string): Promise<string> {
  try {
    return (await $.fs.exists(path)) ? await $.fs.read(path) : ''
  } catch {
    return ''
  }
}

// The switch: the repo's own `compact.json` when it has one, else the machine's `~/.claude/compact.json`
// (`#624`). Anything missing or unreadable is off - the same rule todo's half applies.
async function config($: Files, root: string, home: string): Promise<{ enabled: boolean; minPercent: number }> {
  try {
    const own = `${dir(root)}/compact.json`
    const path = (await $.fs.exists(own)) || home === '' ? own : `${dir(home)}/compact.json`
    const parsed = JSON.parse(await readtext($, path)) as {
      enabled?: unknown
      minPercent?: unknown
    }
    const min = typeof parsed.minPercent === 'number' ? parsed.minPercent : DEFAULT_MIN
    return { enabled: parsed.enabled === true, minPercent: min }
  } catch {
    return { enabled: false, minPercent: DEFAULT_MIN }
  }
}

// One JSON line per due, appended: `$.fs.write` replaces the whole file, so the log is read first.
async function log($: Files, root: string, o: object): Promise<void> {
  try {
    const path = `${dir(root)}/compact.log`
    const before = await readtext($, path)
    await $.fs.write(path, `${before}${JSON.stringify({ at: new Date().toISOString(), ...o })}\n`)
  } catch {
    // A log that cannot be written is no reason to stop the queue.
  }
}

type Engine = Files & {
  clock: { after: (ms: number, f: () => void) => unknown }
  env: { get: (name: string) => Promise<string | undefined> }
  session: {
    usage: () => Promise<{ context: { tokens?: number; percent?: number; window: number } }>
    compact: () => Promise<{ skip?: unknown; usage?: unknown }>
  }
  prompt: { submit: (input: { text: string }) => Promise<{ drop?: string }> }
}

// Submits the carry-on prompt, then checks a main-loop turn started from it - `#718`. A refused submit
// resolves `{ drop }` rather than rejecting, so the result is read; an accepted one that starts nothing is
// caught by the count not moving. Any main-loop turn counts: the Stop hook keeps it on the queue.
async function carryon($: Engine, root: string, due: string, sent = 0): Promise<void> {
  const before = starts
  let accepted = false
  try {
    const r = await $.prompt.submit({ text: NEXT })
    if (r?.drop !== undefined) {
      await log($, root, { task: due, step: 'dropped', reason: r.drop })
    } else {
      accepted = true
    }
  } catch (err) {
    await log($, root, { task: due, step: 'submit failed', error: String(err) })
  }
  $.clock.after(accepted ? SETTLE : RESEND, () => {
    if (starts !== before) return
    void (async () => {
      if (accepted) await log($, root, { task: due, step: 'no turn' })
      if (sent + 1 >= SENDS) {
        await log($, root, { task: due, step: 'gave up', sends: SENDS })
        return
      }
      await carryon($, root, due, sent + 1)
    })()
  })
}

// Compacts if over `minPercent`, then carries on. `seen` is the turn count at the `turn.complete` that
// consumed the due, so a refusal over a running turn can tell whose turn it is.
async function settle($: Engine, root: string, due: string, seen: number, tries = 0): Promise<void> {
  try {
    const home = (await $.env.get('USERPROFILE')) ?? (await $.env.get('HOME')) ?? ''
    const { minPercent } = await config($, root, home)
    const { context } = await $.session.usage()
    const tokens = context.tokens ?? 0
    const percent = context.percent ?? Math.round((tokens / context.window) * 100)
    if (percent <= minPercent) {
      await log($, root, { task: due, step: 'skipped', tokens, percent, min: minPercent })
    } else {
      const c = await $.session.compact()
      await log($, root, { task: due, step: 'compacted', tokens, percent, skip: c.skip, usage: c.usage })
    }
  } catch (err) {
    if (!BUSY.test(String(err))) {
      await log($, root, { task: due, step: 'error', error: String(err) })
    } else if (starts !== seen) {
      // `#665`: a main-loop turn started inside the wait. It carries the queue, so the due goes back for
      // its own turn.complete, and no prompt goes over it.
      try {
        await $.fs.write(`${dir(root)}/compact.due`, due)
        await log($, root, { task: due, step: 'busy', error: String(err) })
        return
      } catch {
        await log($, root, { task: due, step: 'error', error: String(err) })
      }
    } else if (tries + 1 < BUSYTRIES) {
      // `#718`: the turn holding the engine is a subagent's or a background agent's, whose end this mod
      // does not act on. Keep the due and try again.
      await log($, root, { task: due, step: 'busy, retrying', error: String(err) })
      $.clock.after(BUSYWAIT, () => void settle($, root, due, seen, tries + 1))
      return
    } else {
      await log($, root, { task: due, step: 'busy, gave up', tries: BUSYTRIES })
    }
  }
  await carryon($, root, due)
}

export const register: Register = on => {
  on('turn.start', async ($, e, next) => {
    const r = await next(e)
    if (e.agentId === undefined) starts++
    return r
  })

  on('session.start', async ($, e, next) => {
    const r = await next(e)
    try {
      await $.fs.write(`${dir(await $.session.root())}/compact.alive`, await $.session.id())
    } catch {
      // Without `alive` todo behaves as it always has; nothing to do.
    }
    return r
  })

  on('turn.complete', async ($, e, next) => {
    const r = await next(e)
    if (e.agentId !== undefined) {
      return r
    }
    let root = ''
    let due = ''
    try {
      root = await $.session.root()
      // Kept current every turn, so a `/clear` (a new session id) is matched again from its first turn.
      await $.fs.write(`${dir(root)}/compact.alive`, await $.session.id())
      due = (await readtext($, `${dir(root)}/compact.due`)).trim()
      if (due === '') {
        return r
      }
      // No delete in `$.fs`, so EMPTY is the consumed state.
      await $.fs.write(`${dir(root)}/compact.due`, '')
    } catch (err) {
      // Only emptying `compact.due` throws with a task in hand. It still names the task, so carrying on
      // would compact and prompt again at the end of every turn - `#641`. Stop here, and the queue waits
      // for the next prompt.
      if (due !== '') {
        await log($, root, { task: due, step: 'consume failed', error: String(err) })
      }
      return r
    }
    // Before the callback, so a callback that never runs is a `consumed` with nothing after it - `#660`.
    await log($, root, { task: due, step: 'consumed' })
    // After the turn has fully ended: compaction rejects while a turn runs.
    const seen = starts
    $.clock.after(500, () => void settle($ as unknown as Engine, root, due, seen))
    return r
  })
}
