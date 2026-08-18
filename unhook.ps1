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

# Anything that runs one of our binaries. Deliberately specific: a hook of yours that merely mentions
# the word "todo" is none of our business.
$ours = 'todo\.exe|todoui\.exe|todoui-once'

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
    foreach ($event in @('SessionStart', 'UserPromptSubmit', 'Stop')) {
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
