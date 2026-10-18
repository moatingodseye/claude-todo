import type { Register } from 'claude-code'

// Compact after a done - `#620`, design.md *Compact after a done*. todo's Stop hook lets the turn end once
// after a finished task, but only when `<repo>/.claude/compact.alive` names this session, and tells this
// mod which task in `compact.due`. Here: compact if the context is over the repo's `minPercent`, then
// ALWAYS submit the prompt that carries the queue on. A mod that fails must cost the compaction, never the
// flow.
const MARK = '[todo-compact]'
const NEXT = `${MARK} a task was finished - run todo next and carry on with the queue`
const DEFAULT_MIN = 10

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

export const register: Register = on => {
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
      if (due === '') {
        return r
      }
      await log($, root, { task: due, step: 'error', error: String(err) })
    }
    // After the turn has fully ended: compaction rejects while a turn runs.
    $.clock.after(500, () => {
      void (async () => {
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
          await log($, root, { task: due, step: 'error', error: String(err) })
        } finally {
          try {
            await $.prompt.submit({ text: NEXT })
          } catch (err) {
            await log($, root, { task: due, step: 'submit failed', error: String(err) })
          }
        }
      })()
    })
    return r
  })
}
