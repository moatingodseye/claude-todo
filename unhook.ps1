# Removes the todo hooks from Claude Code's settings, and nothing else.
#
# Run unhook.cmd rather than this directly - it sets the execution policy for you.
#
# It scrubs both scopes, whichever exist:
#     this project   <the folder you run it from>\.claude\settings.json
#     global         %USERPROFILE%\.claude\settings.json
#
# It removes only the individual hook ENTRIES whose command runs todo.exe or the viewer. It does not
# remove a whole SessionStart or Stop section, because you may well have hooks of your own in there
# and taking them out with ours would be worse than the problem you are trying to fix.

# Which project to scrub. The deployment copy is run from the project folder, so the default is right
# there; the source repo's wrapper passes its own folder, because the repo root IS the project.
param([string]$Project = '')

$ErrorActionPreference = 'Stop'

# Anything that runs one of our binaries, or one of the two launchers that start the viewer for the
# SessionStart hook: `todoui-start.cmd` as shipped, `tool\showview.ps1` in this repo. Deliberately
# specific: a hook of yours that merely mentions the word "todo" is none of our business.
#
# The launchers have to be listed by name, because neither runs `todoui.exe` in its own command line -
# it is named inside the script. Without them this scrubber reported success while leaving the viewer
# hook in place, and the viewer hook is the one that hangs Claude Code on a cold start. Found at work
# on 2026-08-19 against the shipped launcher; `showview.ps1` had the identical hole here.
# See plan\2026-08-19-cli-papercuts.md, item 3.
# The v1 binaries are listed too, and NOT by widening `todo\.exe` to `todo.*\.exe`. Neither
# `todocli.exe` nor `todoserver.exe` nor `todo-rs.exe` contains the string "todo.exe", so a hook
# pointed at the v1 sandbox would have survived this scrubber untouched - the identical hole the
# shipped launcher had, in a new place, and on the hook that DENIES tool calls. A hook you cannot
# remove is the one you most need to be able to remove.
#
# Spelled out rather than pattern-matched so it stays "deliberately specific": a hook of RB's that
# merely mentions the word "todo" is still none of our business.
#
# The todo-xyz names were added on 2026-08-25 and the OLD ones were kept. A retired name is never
# removed from this list, because this scrubber's whole job is to remove hooks somebody installed
# EARLIER - dropping `todo-rs.exe` the day it became `todo-cli.exe` would leave every hook the previous
# release wrote pointing at a binary that is gone, which is exactly the hole described above in a third
# new place. Kept identical to $ours in install.ps1.
$ours = 'todo\.exe|todocli\.exe|todoserver\.exe|todo-rs\.exe|todoui\.exe|todo-cli\.exe|todo-server\.exe|todo-ui\.exe|todo-startup\.exe|todoui-once|todoui-start|showview'

function Scrub([string]$path, [string]$scope) {
    Write-Host ''
    Write-Host "[$scope] $path"
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host '  not present - nothing to undo.'
        return $true
    }

    try {
        $json = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json
    } catch {
        Write-Host "  this file does not parse as JSON, so it was not touched: $($_.Exception.Message)"
        return $false
    }

    if ($null -eq $json.hooks) {
        Write-Host '  no hooks section - left untouched.'
        return $true
    }

    $removed = 0
    # Every event this tool installs a hook into. PreToolUse added 2026-08-21 with the gate that
    # denies edits while a capture is untriaged - and it is the MOST important one to be able to
    # remove, because a hook that refuses tool calls is a hook that can stop you fixing it. Leaving
    # it off this list would have been the same hole as the viewer launcher: an escape hatch
    # reporting success while the thing you needed removing stayed put.
    foreach ($event in @('SessionStart', 'UserPromptSubmit', 'PreToolUse', 'Stop')) {
        if ($json.hooks.PSObject.Properties.Name -notcontains $event) { continue }

        $keptgroups = @()
        foreach ($group in @($json.hooks.$event)) {
            $keep = @()
            foreach ($hook in @($group.hooks)) {
                if ($hook.command -and ($hook.command -match $ours)) {
                    Write-Host "  removed from ${event}: $($hook.command)"
                    $removed++
                } else {
                    $keep += $hook
                }
            }
            # A group with nothing left in it goes; a group with your hooks still in it stays.
            if ($keep.Count -gt 0) {
                $group.hooks = $keep
                $keptgroups += $group
            }
        }
        if ($keptgroups.Count -gt 0) {
            $json.hooks.$event = $keptgroups
        } else {
            $json.hooks.PSObject.Properties.Remove($event)
        }
    }

    if ($removed -eq 0) {
        Write-Host '  none of our hooks present - left untouched.'
        return $true
    }

    # Written without a BOM, and read straight back: a settings file that no longer parses would
    # silently disable every setting in it, which is a worse outcome than the hooks staying put.
    $out = $json | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($path, $out, (New-Object System.Text.UTF8Encoding($false)))
    try {
        [void]([System.IO.File]::ReadAllText($path) | ConvertFrom-Json)
    } catch {
        Write-Host '  REWRITTEN FILE DOES NOT PARSE. Open it and remove the todo entries by hand.'
        return $false
    }
    Write-Host "  removed $removed hook(s), and the file still parses."
    return $true
}

$ok = $true
if ($env:TODOSETTINGS) {
    # One specific file, for testing this script.
    if (-not (Scrub $env:TODOSETTINGS 'named by TODOSETTINGS')) { $ok = $false }
} else {
    $where = if ($Project) { $Project } else { (Get-Location).Path }
    if (-not (Scrub (Join-Path $where '.claude\settings.json') 'this project')) { $ok = $false }
    if (-not (Scrub (Join-Path $env:USERPROFILE '.claude\settings.json') 'global')) { $ok = $false }
}

Write-Host ''
if ($ok) {
    Write-Host 'Done. Start Claude Code again.'
    exit 0
}
Write-Host 'ONE OR MORE FILES COULD NOT BE FIXED - see above.'
exit 1
