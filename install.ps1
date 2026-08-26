# Install todo from a downloaded release, and wire one project's hooks.
#
# Run install.cmd rather than this directly - it sets the execution policy for you.
#
# ONE QUESTION: which folder the tool goes into. Everything follows from that single answer - the
# binaries land there, `configuration.json` is written there, and the four hook entries are GENERATED
# from it. RB, 2026-08-25: *"install asks 1 question what path are you putting the tool into,
# everything goes into that folder, from that the configuration.json can be created in the folder and
# the hooks made. done."*
#
# **There is no default install location, and D:\tool is not one.** That is where RB puts things on
# his own machine; on yours there may be no D: drive at all. The suggestion offered is the folder you
# unzipped into, because the tool is portable by construction - `registry.db`, `server.bin` and
# `viewer.bin` all live beside the exe - so unzip-and-run is a real answer rather than a cop-out.
#
# Nothing goes on PATH. All four hooks call the binary by its absolute path, and the session-start
# text names the folder, so a bare `todo` was never needed.

param(
    # Where the binaries go. Asked for if not given; -To makes the whole thing non-interactive.
    [string]$To = '',
    # Which project gets the hooks. The folder you run this from, unless you say otherwise.
    [string]$Project = '',
    # Install the binaries but wire no hooks. For a second machine you are only staging.
    [switch]$NoHooks
)

$ErrorActionPreference = 'Stop'

$source = $PSScriptRoot
$config = 'configuration.json'

# Exactly these files, named one by one. Never a wildcard sweep of the source folder: this script runs
# in a directory somebody unzipped, and a copy loop that decides for itself what to take is how an
# installer ends up moving something it was never meant to touch.
$binaries = @(
    'todo-cli.exe',     # the Rust client - THE ONE THE HOOKS CALL, measured ~1.8x faster than the Dart one
    'todo-startup.exe', # the launcher - the ONLY program that starts anything; see design.md,
                        #   *Who starts the server*. SessionStart calls this, not the CLI
    'todo-server.exe',  # the resident server; owns SQLite. sqlite3.dll is Enigma-packed INSIDE it
    'todo-ui.exe'       # the viewer. flutter_windows.dll and data\ are Enigma-packed INSIDE it
)

# **FOUR FILES, AND NOT ONE DLL. RB, 2026-08-26: *"i want standalone things that dont need anything
# extra installed!"*** This list carried `sqlite3.dll` and `flutter_windows.dll` until then, and the
# install wrote a `data\` tree beside them.
#
# Each exe now carries what only it needs: sqlite goes in the server and nowhere else - *"the ui talks
# to the server, the cli talks to the server, neither talks to the db directly, so sqlite is only in
# one place!"* - and flutter goes in the viewer. The two Rust binaries carry nothing, because their PE
# import tables name only Windows system DLLs.
#
# The VC++ runtime the viewer also imports is deliberately NOT packed: *"leave the ms stuff, only pack
# the 'odd' dlls."* That is a Windows prerequisite, not a dependency of ours.

# **No folders. Empty since 2026-08-26, and kept as an empty list rather than deleted** so the copy
# loop below needs no change if a future artefact ever genuinely needs one.
#
# This was `@('data')` - the viewer's Flutter assets, copied as a tree beside the exe because Flutter
# resolves `data\` relative to the executable. It is inside `todo-ui.exe` now, which is what makes the
# install folder strictly flat: four files, nothing else, nothing to keep together.
$folders = @()

# Which binary the hooks name. RB, 2026-08-25: "rust replaces dart cli not just for some things do
# it!" - measured at median 92 ms against the Dart client's 176 ms, and `PreToolUse` fires on every
# gated tool call, so it is hundreds of invocations a session rather than a handful.
#
# FOUR binaries since 2026-08-26 - the launcher joined them. The Dart client is still not one of
# them: it is the other implementation of wire.md and it still exists
# - but it is NOT installed, on RB's ruling of 2026-08-25: "you said it was working so why deploy it at
# all?". Both bugs the two-client pair has caught were caught by the SUITE in the source tree, so the
# cross-check needs the repo and not the zip. Shipping it bought nobody anything and cost 7 MB, a
# second binary to keep version-locked, and a real chance of hooks wired to the slower client.
$hookbinary = 'todo-cli.exe'

# The four hooks, generated from the answer. Kept in step with unhook.ps1, which removes exactly these.
function Hookentries([string]$exe, [string]$startup) {
    return @(
        # **SessionStart runs the LAUNCHER, since 2026-08-26.** It ensures the server, then relays
        # `todo-cli hook sessionstart` itself - so the guidance still arrives, but the server is up
        # before anything asks for it. One hook rather than two, so the order cannot be a race.
        @{ Event = 'SessionStart';     Matcher = '';  Command = "$startup" },
        @{ Event = 'UserPromptSubmit'; Matcher = '';  Command = "$exe hook prompt" },
        @{ Event = 'PreToolUse';       Matcher = 'Edit|Write|MultiEdit|NotebookEdit|Bash|PowerShell';
                                                      Command = "$exe hook pretooluse" },
        @{ Event = 'Stop';             Matcher = '';  Command = "$exe hook stop" }
    )
}

# Anything of ours already in a settings file, so a re-run REPLACES rather than appends. Same list as
# unhook.ps1 - a hook of yours that merely mentions the word "todo" is none of our business.
# EVERY name we have ever installed under, and the retired ones are never removed: an upgrade has to
# recognise the hooks the PREVIOUS version wrote, or it leaves them behind pointing at a binary that is
# no longer there. Same lesson as the gate's client allow-list, learned the same day.
$ours = 'todo\.exe|todocli\.exe|todoserver\.exe|todo-rs\.exe|todoui\.exe|todo-cli\.exe|todo-server\.exe|todo-ui\.exe|todo-startup\.exe|todoui-once|todoui-start|showview'

# ---------------------------------------------------------------- the one question

if (-not $To) {
    # A previous answer wins as the suggestion, so re-running is Enter-Enter rather than remembering.
    $previous = ''
    $existing = Join-Path $source $config
    if (Test-Path -LiteralPath $existing) {
        try {
            $previous = ([System.IO.File]::ReadAllText($existing) | ConvertFrom-Json).tool
        } catch {
            # A configuration file that does not parse is not a reason to refuse to install.
            $previous = ''
        }
    }
    $suggested = if ($previous) { $previous } else { $source }

    Write-Host ''
    Write-Host 'todo - install'
    Write-Host ''
    Write-Host 'Which folder should the tool go into? Everything lives there: the binaries, the'
    Write-Host 'queue registry, and the two runtime state files. Nothing is put on PATH.'
    Write-Host ''
    $answer = Read-Host "Folder [$suggested]"
    $To = if ($answer) { $answer } else { $suggested }
}

$To = [System.IO.Path]::GetFullPath($To)
if (-not (Test-Path -LiteralPath $To)) {
    New-Item -ItemType Directory -Path $To -Force | Out-Null
}

# ---------------------------------------------------------------- the binaries

$samefolder = ([System.IO.Path]::GetFullPath($source)).TrimEnd('\') -ieq $To.TrimEnd('\')
$copied = @()
$missing = @()
foreach ($name in $binaries) {
    $from = Join-Path $source $name
    if (-not (Test-Path -LiteralPath $from)) { $missing += $name; continue }
    if ($samefolder) { $copied += $name; continue }
    # A running viewer or server holds its own exe open. Say which, rather than failing obscurely.
    try {
        Copy-Item -LiteralPath $from -Destination (Join-Path $To $name) -Force
        $copied += $name
    } catch {
        Write-Host ''
        Write-Host "Could not replace $name in ${To}: $($_.Exception.Message)"
        Write-Host 'Close the viewer and stop todo-server, then run this again.'
        exit 1
    }
}

foreach ($name in $folders) {
    $from = Join-Path $source $name
    if (-not (Test-Path -LiteralPath $from)) { $missing += "$name\"; continue }
    if ($samefolder) { $copied += "$name\"; continue }
    try {
        Copy-Item -LiteralPath $from -Destination $To -Recurse -Force
        $copied += "$name\"
    } catch {
        Write-Host ''
        Write-Host "Could not replace $name in ${To}: $($_.Exception.Message)"
        Write-Host 'Close the viewer, then run this again.'
        exit 1
    }
}

if ($copied -notcontains $hookbinary) {
    Write-Host ''
    Write-Host "$hookbinary is not in $source, so there is nothing to wire hooks to."
    Write-Host 'Run this from the folder you unzipped the release into.'
    exit 1
}

# ---------------------------------------------------------------- configuration.json

# Written in the tool folder, in plain JSON, so it can be opened and changed afterwards - which is the
# whole reason it exists rather than the answer living only inside generated hook commands.
#
# **Editing `tool` here does not move anything on its own.** It changes what the NEXT run of this
# script installs and wires; the hooks in each project still name the old path until you re-run it.
# Said plainly here and in the file, because a config key that looks live and is not is worse than no
# key at all.
$settingsfile = Join-Path $To $config
$configuration = [ordered]@{
    tool      = $To
    installed = (Get-Date).ToString('yyyy-MM-dd')
    note      = 'Change "tool" and re-run install.cmd to move the tool. Editing this file alone does not move anything.'
}
[System.IO.File]::WriteAllText(
    $settingsfile,
    ($configuration | ConvertTo-Json -Depth 5),
    (New-Object System.Text.UTF8Encoding($false)))

# ---------------------------------------------------------------- the hooks

function Wire([string]$path, [string]$exe) {
    $folder = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    $json = $null
    if (Test-Path -LiteralPath $path) {
        try {
            $json = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json
        } catch {
            # Refuse rather than overwrite. A settings file that does not parse is one somebody is in
            # the middle of editing, and replacing it would lose whatever else is in there.
            Write-Host "  $path does not parse as JSON, so it was NOT touched."
            return $false
        }
    }
    if ($null -eq $json) { $json = [pscustomobject]@{} }
    if ($null -eq $json.hooks) {
        $json | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    foreach ($entry in Hookentries $exe $startup) {
        $event = $entry.Event

        # Take OURS out first, so a re-run replaces instead of stacking a second copy of every hook.
        # Anything of yours in the same event is kept exactly where it was.
        $kept = @()
        if ($json.hooks.PSObject.Properties.Name -contains $event) {
            foreach ($group in @($json.hooks.$event)) {
                $keep = @(@($group.hooks) | Where-Object { $_.command -and ($_.command -notmatch $ours) })
                if ($keep.Count -gt 0) {
                    $group.hooks = $keep
                    $kept += $group
                }
            }
        }

        $new = [pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'command'; command = $entry.Command }) }
        if ($entry.Matcher) {
            $new | Add-Member -NotePropertyName matcher -NotePropertyValue $entry.Matcher -Force
        }
        $kept += $new
        $json.hooks | Add-Member -NotePropertyName $event -NotePropertyValue $kept -Force
    }

    # Without a BOM, and read straight back. A settings file that no longer parses silently disables
    # every setting in it, which is worse than not installing at all.
    $out = $json | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($path, $out, (New-Object System.Text.UTF8Encoding($false)))
    try {
        [void]([System.IO.File]::ReadAllText($path) | ConvertFrom-Json)
    } catch {
        Write-Host '  THE REWRITTEN FILE DOES NOT PARSE. Open it and take the todo entries out by hand.'
        return $false
    }
    return $true
}

# FORWARD SLASHES, and this is not cosmetic. A hook command is run through a shell that strips
# unquoted backslashes, so "D:\tool\todo-cli.exe" arrives as "d:tooltodo-cli.exe" and fails with
# "command not found". Forward slashes need no escaping in JSON and work perfectly well on Windows.
#
# The first version of this script used Join-Path and shipped in v1.1.0 with backslashes, which broke
# every hook it wired. Caught within minutes because it rewired this repo, and it is the reason
# `Wire` now asserts the path it is about to write.
# A literal .Replace with a char code, not a -replace with a regex: the escaping needed to write a
# backslash pattern inside a PowerShell string inside a generated file is exactly the sort of thing
# that silently produces the wrong character, which is the fault this line exists to prevent.
$exe = $To.Replace([char]92, '/').TrimEnd('/') + '/' + $hookbinary
$startup = $To.Replace([char]92, '/').TrimEnd('/') + '/' + 'todo-startup.exe'
foreach ($path in @($exe, $startup)) {
    if ($path.Contains([char]92)) {
        Write-Host "Refusing to write a hook command containing a backslash: $path"
        exit 1
    }
}
$wired = $false
$where = ''
if (-not $NoHooks) {
    $where = if ($Project) { $Project } else { (Get-Location).Path }
    $where = [System.IO.Path]::GetFullPath($where)
    $wired = Wire (Join-Path $where '.claude\settings.json') $exe
}

# ---------------------------------------------------------------- what happened

Write-Host ''
Write-Host "todo is installed in $To"
foreach ($name in $copied) { Write-Host "  $name" }
if ($missing.Count -gt 0) {
    Write-Host ''
    Write-Host "Not in the download, so not installed: $($missing -join ', ')"
    if ($missing -contains 'sqlite3.dll') {
        Write-Host '  sqlite3.dll is only needed if todo-server.exe was not packed with it inside.'
    }
    if (($missing -contains 'flutter_windows.dll') -or ($missing -contains 'data\')) {
        Write-Host '  flutter_windows.dll and data\ are the viewer''s. Without them todo-ui.exe will not start.'
    }
}
Write-Host ''
Write-Host "  $config written - open it to see where things went."
if ($NoHooks) {
    Write-Host '  No hooks wired (-NoHooks). Re-run from a project to wire one.'
} elseif ($wired) {
    Write-Host "  Four hooks wired into $where\.claude\settings.json"
    Write-Host '  Per project on purpose: try it in one repo before it affects every one of them.'
    Write-Host ''
    Write-Host '  Start Claude Code again in that project. Run install.cmd from any other project to'
    Write-Host '  wire it too - it will not ask again unless you want to move the tool.'
} else {
    Write-Host '  HOOKS NOT WIRED - see above.'
    exit 1
}
Write-Host ''
Write-Host 'To undo: unhook.cmd, from the project folder.'
exit 0
